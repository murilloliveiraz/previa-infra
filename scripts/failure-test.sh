#!/usr/bin/env bash
# =====================================================================
# PrevIA - TESTES DE FALHA
# Provoca falhas reais e verifica se a infraestrutura detecta e se recupera.
# Cada teste registra PASSOU/FALHOU em /var/log/previa/failure-tests.log
#
# Uso: sudo ./scripts/failure-test.sh [teste]
#   app-crash    kill -9 no processo da aplicacao -> systemd reinicia
#   app-stop     systemctl stop previa-app       -> monitor/healthcheck sobem
#   nginx-stop   systemctl stop nginx            -> monitor reinicia (auto-heal)
#   monitor-kill kill -9 no proprio monitor      -> systemd reinicia o monitor
#   cpu          estresse de CPU                 -> alerta de CPU
#   mem          estresse de memoria             -> alerta de memoria
#   disk         enche o disco ate o limite      -> alerta de disco
#   all          executa todos (padrao)
# =====================================================================
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
require_root
audit_begin "$@"

RESULT_LOG="$LOG_DIR/failure-tests.log"
ALERT_LOG="$LOG_DIR/alerts.log"
WAIT_MON=$(( MON_INTERVAL * 2 + 5 ))   # tempo para o monitor perceber (2 ciclos)
PASS=0; FAIL=0

touch "$ALERT_LOG"

result() {
    # $1=teste $2=PASSOU|FALHOU $3=detalhe
    local line
    line="$(ts) | $1 | $2 | $3"
    echo "$line" >> "$RESULT_LOG"
    audit_event "FAILURE_TEST" "test=$1 result=$2"
    if [[ "$2" == "PASSOU" ]]; then log_ok "[$1] PASSOU - $3"; PASS=$((PASS+1))
    else log_error "[$1] FALHOU - $3"; FAIL=$((FAIL+1)); fi
}

alerts_mark() { wc -l < "$ALERT_LOG"; }
alerts_since() { tail -n +"$(( $1 + 1 ))" "$ALERT_LOG"; }

# Aguarda (ate $3 segundos) um alerta do recurso $2 surgir apos a marca $1.
# Sob estresse o ciclo do monitor pode atrasar, entao conferimos a cada 2s
# em vez de olhar uma unica vez num horario fixo.
wait_alert() {
    local mark="$1" res="$2" max="$3" t=0
    while (( t < max )); do
        alerts_since "$mark" | grep -qE "\| (ALERTA|CRITICO) \| $res" && return 0
        sleep 2; t=$(( t + 2 ))
    done
    return 1
}

wait_http_ok() {
    local i
    for i in $(seq 1 "$1"); do
        [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1/api/health)" == "200" ]] && { echo "$i"; return 0; }
        sleep 1
    done
    return 1
}

# ---------------------------------------------------------------------
test_app_crash() {
    log_step "TESTE app-crash: kill -9 no processo da aplicacao"
    local pid_before pid_after secs
    pid_before=$(systemctl show previa-app -p MainPID --value)
    log_info "PID antes: $pid_before -> enviando SIGKILL"
    kill -9 "$pid_before"
    if secs=$(wait_http_ok 30); then
        pid_after=$(systemctl show previa-app -p MainPID --value)
        result app-crash PASSOU "systemd reiniciou (PID $pid_before -> $pid_after) e HTTP 200 em ${secs}s; NRestarts=$(systemctl show previa-app -p NRestarts --value)"
    else
        result app-crash FALHOU "aplicacao nao voltou em 30s"
    fi
}

test_app_stop() {
    log_step "TESTE app-stop: parada manual (systemctl stop) - Restart=always NAO atua"
    local mark; mark=$(alerts_mark)
    systemctl stop previa-app
    log_info "previa-app parado. Aguardando monitor/healthcheck (ate $((WAIT_MON+60))s)..."
    if secs=$(wait_http_ok $((WAIT_MON + 60))); then
        result app-stop PASSOU "app recuperado automaticamente em ${secs}s | $(alerts_since "$mark" | grep -E 'APP|WATCHDOG' | tail -n1)"
    else
        result app-stop FALHOU "app nao foi recuperado"; systemctl start previa-app
    fi
}

test_nginx_stop() {
    log_step "TESTE nginx-stop: proxy reverso derrubado"
    local mark; mark=$(alerts_mark)
    systemctl stop nginx
    if secs=$(wait_http_ok $((WAIT_MON + 60))); then
        result nginx-stop PASSOU "nginx recuperado em ${secs}s | $(alerts_since "$mark" | grep -E 'NGINX|WATCHDOG' | tail -n1)"
    else
        result nginx-stop FALHOU "nginx nao foi recuperado"; systemctl start nginx
    fi
}

test_monitor_kill() {
    log_step "TESTE monitor-kill: o proprio monitor e derrubado"
    local pid_before pid_after
    pid_before=$(systemctl show previa-monitor -p MainPID --value)
    kill -9 "$pid_before"
    sleep 8
    pid_after=$(systemctl show previa-monitor -p MainPID --value)
    if systemctl is-active --quiet previa-monitor && [[ "$pid_after" != "$pid_before" ]]; then
        result monitor-kill PASSOU "monitor reiniciado pelo systemd (PID $pid_before -> $pid_after)"
    else
        result monitor-kill FALHOU "monitor nao voltou (estado $(systemctl is-active previa-monitor))"
    fi
}

test_cpu() {
    local max=$(( WAIT_MON * 6 ))
    log_step "TESTE cpu: estresse de CPU em $(nproc) nucleos (ate ${max}s, para assim que o alerta surgir)"
    local mark i pids=(); mark=$(alerts_mark)
    # nice 19: a CPU vai a 100%, mas o monitor (nice -5) continua tendo prioridade
    for i in $(seq 1 "$(nproc)"); do nice -n 19 timeout "$max" sh -c 'while :; do :; done' & pids+=($!); done
    if wait_alert "$mark" CPU "$max"; then
        result cpu PASSOU "$(alerts_since "$mark" | grep -E '\| CPU' | head -n1)"
    else
        result cpu FALHOU "nenhum alerta de CPU gerado em ${max}s"
    fi
    kill "${pids[@]}" 2>/dev/null; wait "${pids[@]}" 2>/dev/null
}

test_mem() {
    log_step "TESTE mem: alocando memoria ate passar de ${MEM_LIMIT}%"
    local mark total avail used target need; mark=$(alerts_mark)
    total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)       # kB
    avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    used=$(( total - avail ))
    target=$(( total * (MEM_LIMIT + 5) / 100 ))
    need=$(( target - used ))
    if (( need <= 0 )); then need=$(( 100 * 1024 )); fi
    if (( need > avail * 90 / 100 )); then
        log_warn "Pouca memoria livre; limitando alocacao a 90% do disponivel"; need=$(( avail * 90 / 100 ))
    fi
    log_info "Alocando $(( need / 1024 )) MB por $((WAIT_MON + 5))s"
    local flag=/tmp/previa-mem-ready; rm -f "$flag"
    # bytearray(b'\x01') * n grava todos os bytes -> memoria realmente ocupada (RSS)
    local max=$(( WAIT_MON * 6 ))
    python3 -c "import time; b=bytearray(b'\x01')*($need*1024); open('$flag','w').close(); time.sleep($max)" &
    local pid=$! i
    for i in $(seq 1 120); do [[ -f "$flag" ]] && break; sleep 1; done
    log_info "Memoria alocada em ${i}s; aguardando o alerta do monitor (ate ${max}s)"
    if wait_alert "$mark" MEM "$max"; then
        result mem PASSOU "$(alerts_since "$mark" | grep -E '\| MEM' | head -n1)"
    else
        result mem FALHOU "nenhum alerta de memoria gerado em ${max}s"
    fi
    rm -f "$flag"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}

test_disk() {
    log_step "TESTE disk: ocupando disco ate passar de ${DISK_LIMIT}%"
    local mark size used avail target need file=/var/tmp/previa-disk-test.img
    mark=$(alerts_mark)
    read -r size used avail < <(df -P -B1 / | awk 'NR==2 {print $2, $3, $4}')
    target=$(( size / 100 * (DISK_LIMIT + 2) ))
    need=$(( target - used ))
    if (( need > avail - 300*1024*1024 )); then
        result disk FALHOU "espaco livre insuficiente para o teste com seguranca"; return
    fi
    # Trava de seguranca: nunca reservar mais que DISK_TEST_MAX_GB (padrao 60 GB)
    if (( need > ${DISK_TEST_MAX_GB:-60} * 1024*1024*1024 )); then
        result disk FALHOU "seria preciso reservar $(( need/1024/1024/1024 )) GB; disco grande demais para o teste (reduza DISK_LIMIT)"; return
    fi
    if (( need > 0 )); then
        log_info "Criando arquivo de $(( need / 1024 / 1024 )) MB em $file"
        fallocate -l "$need" "$file" 2>/dev/null || dd if=/dev/zero of="$file" bs=1M count=$(( need / 1024 / 1024 )) status=none
    fi
    if wait_alert "$mark" DISK $(( WAIT_MON * 6 )); then
        result disk PASSOU "$(alerts_since "$mark" | grep -E '\| DISK' | head -n1)"
    else
        result disk FALHOU "nenhum alerta de disco gerado em $(( WAIT_MON * 6 ))s"
    fi
    rm -f "$file"
    log_info "Arquivo removido; o monitor deve registrar RECUPERADO no proximo ciclo"
}

# ---------------------------------------------------------------------
TEST="${1:-all}"
log_info "Iniciando testes de falha: $TEST (intervalo do monitor ${MON_INTERVAL}s)"
echo "$(ts) | ===== INICIO bateria '$TEST' =====" >> "$RESULT_LOG"
case "$TEST" in
    app-crash)    test_app_crash ;;
    app-stop)     test_app_stop ;;
    nginx-stop)   test_nginx_stop ;;
    monitor-kill) test_monitor_kill ;;
    cpu)          test_cpu ;;
    mem)          test_mem ;;
    disk)         test_disk ;;
    all)          test_app_crash; test_monitor_kill; test_nginx_stop; test_app_stop; test_cpu; test_mem; test_disk ;;
    *) die "Teste desconhecido: $TEST (use: app-crash app-stop nginx-stop monitor-kill cpu mem disk all)" ;;
esac
echo "$(ts) | ===== FIM bateria '$TEST': $PASS passou, $FAIL falhou =====" >> "$RESULT_LOG"

echo
log_info "Resultado: ${PASS} PASSOU / ${FAIL} FALHOU  (detalhes em $RESULT_LOG)"
log_info "Alertas gerados durante os testes: tail -n 30 $ALERT_LOG"
[[ $FAIL -eq 0 ]]
