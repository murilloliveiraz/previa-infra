#!/usr/bin/env bash
# =====================================================================
# PrevIA - RELATORIO DE AUDITORIA E ACOMPANHAMENTO
# Consolida em um unico arquivo (evidencias/) tudo o que comprova o
# funcionamento da infraestrutura: identidade, rede, servicos, metricas,
# alertas, testes de falha, trilha de auditoria e eventos do auditd.
# Uso: sudo ./scripts/audit-report.sh
# =====================================================================
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
require_root
audit_begin "$@"

OUT_DIR="$PREVIA_ROOT/evidencias"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/relatorio-auditoria-$(date '+%Y%m%d-%H%M%S').txt"

section() { printf '\n==================== %s ====================\n' "$1"; }

{
    echo "PrevIA - Relatorio de auditoria da infraestrutura"
    echo "Gerado em: $(ts) por ${SUDO_USER:-$(id -un)}"

    section "1. IDENTIDADE DO SERVIDOR"
    hostnamectl 2>/dev/null || { echo "hostname: $(hostname)"; cat /etc/os-release | head -n 4; }
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"

    section "2. REDE E DNS"
    ip -4 -brief addr
    echo; ip route
    echo; echo "--- /etc/hosts (bloco PrevIA) ---"
    sed -n '/>>> PREVIA/,/<<< PREVIA/p' /etc/hosts
    echo; echo "--- Resolucao de nomes ---"
    for n in "$PREVIA_HOSTNAME.$PREVIA_DOMAIN" $APP_HOSTNAMES github.com; do
        printf '%-28s -> %s\n' "$n" "$(getent hosts "$n" | awk '{print $1}' | head -n1)"
    done
    echo; resolvectl status 2>/dev/null | sed -n '1,15p'
    echo; echo "--- Firewall ---"; ufw status verbose 2>/dev/null || echo "ufw indisponivel"

    section "3. SERVICOS"
    for s in previa-app previa-monitor previa-healthcheck.timer nginx auditd; do
        printf '%-26s %-10s enabled=%-8s restarts=%s\n' "$s" \
            "$(systemctl is-active "$s" 2>/dev/null)" "$(systemctl is-enabled "$s" 2>/dev/null)" \
            "$(systemctl show "$s" -p NRestarts --value 2>/dev/null)"
    done
    echo; echo "--- Health check da aplicacao ---"
    curl -s --max-time 5 http://127.0.0.1/api/health; echo

    section "4. RECURSOS (ultimas 15 coletas do monitor)"
    tail -n 15 "$LOG_DIR/monitor.log" 2>/dev/null

    section "5. ALERTAS (ultimos 40)"
    tail -n 40 "$LOG_DIR/alerts.log" 2>/dev/null || echo "nenhum alerta"
    echo; echo "Totais por tipo:"
    awk -F' \\| ' '{print $2" "$3}' "$LOG_DIR/alerts.log" 2>/dev/null | sort | uniq -c | sort -rn

    section "6. TESTES DE FALHA"
    tail -n 40 "$LOG_DIR/failure-tests.log" 2>/dev/null || echo "nenhum teste executado"

    section "7. TRILHA DE AUDITORIA DOS SCRIPTS (audit.log)"
    tail -n 60 "$LOG_DIR/audit.log" 2>/dev/null

    section "8. AUDITD - eventos do kernel (chaves previa_*)"
    if command -v ausearch >/dev/null 2>&1 && auditctl -l >/dev/null 2>&1; then
        auditctl -l | grep previa
        for k in previa_config previa_app previa_service previa_exec previa_network; do
            echo; echo "--- $k ---"
            ausearch -k "$k" -i 2>/dev/null | grep -E '^type=SYSCALL' | tail -n 5 \
                | sed -E 's/.*msg=audit\(([^)]*)\).*comm=([^ ]*).*exe=([^ ]*).*/\1 comm=\2 exe=\3/' \
                || echo "sem eventos"
        done
    else
        echo "auditd indisponivel neste ambiente"
    fi

    section "9. JOURNALD (ultimos eventos dos servicos PrevIA)"
    journalctl -u previa-app -u previa-monitor -u previa-healthcheck --no-pager -n 30 2>/dev/null
} > "$REPORT" 2>&1

log_ok "Relatorio gerado: $REPORT ($(wc -l < "$REPORT") linhas)"
