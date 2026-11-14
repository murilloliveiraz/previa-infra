#!/usr/bin/env bash
# =====================================================================
# PrevIA - Watchdog de segunda camada
# Instalado em /usr/local/bin/previa-healthcheck e executado pelo
# previa-healthcheck.timer a cada minuto.
# Se o monitor, a aplicacao ou o nginx estiverem parados (inclusive por
# "systemctl stop" manual), sobe novamente e registra o evento.
# =====================================================================
set -uo pipefail
[[ -z "${APP_NAME:-}" && -f /etc/previa/previa.env ]] && source /etc/previa/previa.env
LOG_DIR="${LOG_DIR:-/var/log/previa}"
HC_LOG="$LOG_DIR/healthcheck.log"
ALERT_LOG="$LOG_DIR/alerts.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

status_line=""
for svc in previa-monitor previa-app nginx; do
    st="$(systemctl is-active "$svc" 2>/dev/null || true)"
    if [[ "$st" != "active" ]]; then
        systemctl start "$svc" 2>/dev/null
        sleep 2
        new="$(systemctl is-active "$svc" 2>/dev/null || true)"
        echo "$(ts) | AUTO-HEAL | WATCHDOG | $svc estava '$st' -> iniciado pelo healthcheck -> $new" | tee -a "$ALERT_LOG"
        logger -p user.warning -t previa-healthcheck -- "$svc estava $st, reiniciado -> $new"
        st="$new"
    fi
    status_line+="$svc=$st "
done
echo "$(ts) | $status_line" >> "$HC_LOG"
