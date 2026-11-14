#!/usr/bin/env bash
# =====================================================================
# PrevIA - Painel rapido de status no terminal (ideal para o video)
# Uso: sudo ./scripts/status.sh        (uma vez)
#      sudo watch -n 5 ./scripts/status.sh   (atualizando)
# =====================================================================
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

echo "=========== PrevIA - STATUS $(ts) ==========="
echo "Host : $(hostname)  |  IP: $(hostname -I 2>/dev/null | awk '{print $1}')  |  Uptime: $(uptime -p 2>/dev/null)"
echo
for s in previa-app previa-monitor previa-healthcheck.timer nginx auditd; do
    st=$(systemctl is-active "$s" 2>/dev/null)
    [[ "$st" == "active" ]] && c="$C_GRN" || c="$C_RED"
    printf '  %-26s %s%-10s%s restarts=%s\n' "$s" "$c" "$st" "$C_RST" "$(systemctl show "$s" -p NRestarts --value 2>/dev/null)"
done
echo
printf '  HTTP /api/health: %s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1/api/health)"
echo
echo "--- Ultima coleta do monitor ---"
tail -n 1 "$LOG_DIR/monitor.log" 2>/dev/null
echo
echo "--- Ultimos 5 alertas ---"
tail -n 5 "$LOG_DIR/alerts.log" 2>/dev/null || echo "  nenhum"
