#!/usr/bin/env bash
# =====================================================================
# PrevIA - Monitor de infraestrutura (roda como servico systemd)
# Instalado em /usr/local/bin/previa-monitor pelo 03-monitoring-setup.sh
#
# A cada MON_INTERVAL segundos:
#   1. Coleta CPU, memoria e disco
#   2. Verifica servicos (previa-app, nginx) e a resposta HTTP da aplicacao
#   3. Grava uma linha em monitor.log (historico de metricas)
#   4. Gera ALERTA em alerts.log quando passa do limite e RECUPERADO quando volta
#   5. Auto-heal: reinicia app/nginx se estiverem fora do ar
#   6. Publica metrics.json, exibido na pagina /infra da aplicacao
# =====================================================================
set -uo pipefail

# Configuracao (vem do EnvironmentFile do systemd; fallback para o arquivo)
[[ -z "${APP_NAME:-}" && -f /etc/previa/previa.env ]] && source /etc/previa/previa.env

LOG_DIR="${LOG_DIR:-/var/log/previa}"
DATA_DIR="${DATA_DIR:-/var/lib/previa}"
MON_INTERVAL="${MON_INTERVAL:-15}"
CPU_LIMIT="${CPU_LIMIT:-80}"
MEM_LIMIT="${MEM_LIMIT:-80}"
DISK_LIMIT="${DISK_LIMIT:-85}"
AUTO_HEAL="${AUTO_HEAL:-true}"
HEALTH_URL="http://127.0.0.1/api/health"

MON_LOG="$LOG_DIR/monitor.log"
ALERT_LOG="$LOG_DIR/alerts.log"
METRICS_JSON="$DATA_DIR/metrics.json"
mkdir -p "$LOG_DIR" "$DATA_DIR"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Estado anterior de cada alerta (evita repetir o mesmo alerta a cada ciclo)
declare -A STATE=( [CPU]=OK [MEM]=OK [DISK]=OK [APP]=OK [NGINX]=OK )

alert() {
    # $1=recurso $2=severidade $3=mensagem
    local line
    line="$(ts) | $2 | $1 | $3"
    echo "$line" >> "$ALERT_LOG"
    case "$2" in
        CRITICO) logger -p user.crit    -t previa-monitor -- "$1 $3" ;;
        ALERTA)  logger -p user.warning -t previa-monitor -- "$1 $3" ;;
        *)       logger -p user.notice  -t previa-monitor -- "$1 $3" ;;
    esac
    echo "$line"
}

# Avalia valor x limite e registra mudanca de estado
check_threshold() {
    # $1=recurso $2=valor $3=limite
    local res="$1" val="$2" lim="$3" sev="OK"
    if   (( val >= 95 ));   then sev="CRITICO"
    elif (( val >= lim ));  then sev="ALERTA"
    fi
    if [[ "$sev" != "OK" && "${STATE[$res]}" != "$sev" ]]; then
        alert "$res" "$sev" "uso=${val}% limite=${lim}%"
    elif [[ "$sev" == "OK" && "${STATE[$res]}" != "OK" ]]; then
        alert "$res" "RECUPERADO" "uso=${val}% voltou abaixo de ${lim}%"
    fi
    STATE[$res]="$sev"
}

# CPU: diferenca entre duas leituras de /proc/stat com 1s de intervalo
cpu_usage() {

    read -r _ a1 a2 a3 a4 a5 a6 a7 _ < /proc/stat
    sleep 1
    read -r _ b1 b2 b3 b4 b5 b6 b7 _ < /proc/stat
    local idle=$(( (b4 + b5) - (a4 + a5) ))
    local total=$(( (b1+b2+b3+b4+b5+b6+b7) - (a1+a2+a3+a4+a5+a6+a7) ))
    (( total > 0 )) && echo $(( (100 * (total - idle)) / total )) || echo 0
}

# Memoria: (MemTotal - MemAvailable) / MemTotal
mem_usage() {
    awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {printf "%d", (t-a)*100/t}' /proc/meminfo
}

# Disco: uso da particao raiz
disk_usage() {
    df -P / | awk 'NR==2 {gsub("%","",$5); print $5}'
}

svc_state() { systemctl is-active "$1" 2>/dev/null || true; }

heal() {
    # $1=servico $2=recurso
    if [[ "$AUTO_HEAL" == "true" ]]; then
        systemctl restart "$1" 2>/dev/null
        sleep 2
        alert "$2" "AUTO-HEAL" "servico $1 reiniciado pelo monitor -> $(svc_state "$1")"
    fi
}

echo "$(ts) | INFO | previa-monitor iniciado (pid=$$ intervalo=${MON_INTERVAL}s CPU<${CPU_LIMIT}% MEM<${MEM_LIMIT}% DISK<${DISK_LIMIT}%)" | tee -a "$MON_LOG"
logger -t previa-monitor -- "monitor iniciado pid=$$"
trap 'echo "$(ts) | INFO | previa-monitor encerrado (sinal recebido)" >> "$MON_LOG"; exit 0' TERM INT

while true; do
    CPU=$(cpu_usage)
    MEM=$(mem_usage)
    DISK=$(disk_usage)
    LOAD=$(cut -d' ' -f1 /proc/loadavg)
    APP=$(svc_state previa-app)
    NGX=$(svc_state nginx)
    HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" || true)
    HTTP="${HTTP:-000}"

    # 1) Linha de historico
    printf '%s | CPU=%3s%% | MEM=%3s%% | DISK=%3s%% | LOAD=%s | APP=%s | NGINX=%s | HTTP=%s\n' \
        "$(ts)" "$CPU" "$MEM" "$DISK" "$LOAD" "$APP" "$NGX" "$HTTP" >> "$MON_LOG"

    # 2) Limites de recursos
    check_threshold CPU  "$CPU"  "$CPU_LIMIT"
    check_threshold MEM  "$MEM"  "$MEM_LIMIT"
    check_threshold DISK "$DISK" "$DISK_LIMIT"

    # 3) Servicos + auto-heal
    if [[ "$NGX" != "active" ]]; then
        [[ "${STATE[NGINX]}" == "OK" ]] && alert NGINX CRITICO "nginx esta '$NGX'"
        STATE[NGINX]="DOWN"; heal nginx NGINX
    elif [[ "${STATE[NGINX]}" != "OK" ]]; then
        alert NGINX RECUPERADO "nginx ativo novamente"; STATE[NGINX]="OK"
    fi

    if [[ "$APP" != "active" || "$HTTP" != "200" ]]; then
        [[ "${STATE[APP]}" == "OK" ]] && alert APP CRITICO "previa-app=$APP http=$HTTP"
        STATE[APP]="DOWN"
        [[ "$APP" != "active" ]] && heal previa-app APP
    elif [[ "${STATE[APP]}" != "OK" ]]; then
        alert APP RECUPERADO "aplicacao respondendo http=200"; STATE[APP]="OK"
    fi

    # 4) Metricas para a pagina /infra da aplicacao
    cat > "$METRICS_JSON.tmp" <<EOF
{"timestamp":"$(ts)","hostname":"$(hostname)","cpu":$CPU,"mem":$MEM,"disk":$DISK,"load":"$LOAD",
 "limits":{"cpu":$CPU_LIMIT,"mem":$MEM_LIMIT,"disk":$DISK_LIMIT},
 "services":{"previa-app":"$APP","nginx":"$NGX","http":"$HTTP"},
 "state":{"cpu":"${STATE[CPU]}","mem":"${STATE[MEM]}","disk":"${STATE[DISK]}","app":"${STATE[APP]}","nginx":"${STATE[NGINX]}"}}
EOF
    chmod 644 "$METRICS_JSON.tmp"; mv -f "$METRICS_JSON.tmp" "$METRICS_JSON"

    sleep "$MON_INTERVAL" &
    wait $!
done
