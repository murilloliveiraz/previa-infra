#!/usr/bin/env bash
# =====================================================================
# PrevIA - 03: MONITORAMENTO como servico tolerante a falhas
#   Camada 1: previa-app.service / previa-monitor.service com Restart=always
#   Camada 2: previa-monitor reinicia app/nginx se cairem (auto-heal)
#   Camada 3: previa-healthcheck.timer (1 min) sobe qualquer servico parado,
#             inclusive o proprio monitor
#   + logrotate para os logs da PrevIA
# Uso: sudo ./scripts/03-monitoring-setup.sh
# =====================================================================
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
require_root
audit_begin "$@"

log_step "1/4 Instalando scripts de monitoramento"
install -o root -g root -m 755 "$PREVIA_ROOT/scripts/monitor.sh"     /usr/local/bin/previa-monitor
install -o root -g root -m 755 "$PREVIA_ROOT/scripts/healthcheck.sh" /usr/local/bin/previa-healthcheck
log_ok "/usr/local/bin/previa-monitor e /usr/local/bin/previa-healthcheck"

# Cria os logs vazios para que "tail -f" funcione mesmo antes do primeiro alerta
for f in monitor.log alerts.log healthcheck.log failure-tests.log; do
    touch "$LOG_DIR/$f"
done
chmod 644 "$LOG_DIR"/*.log

log_step "2/4 Registrando servicos systemd"
for unit in previa-monitor.service previa-healthcheck.service previa-healthcheck.timer; do
    render_template "$PREVIA_ROOT/systemd/$unit" "/etc/systemd/system/$unit"
    log_ok "/etc/systemd/system/$unit"
done
run systemctl daemon-reload
run systemctl enable previa-monitor.service previa-healthcheck.timer
# restart (e nao so start) para recarregar config/script em re-provisionamentos
run systemctl restart previa-monitor.service
run systemctl restart previa-healthcheck.timer
audit_event "SERVICE" "previa-monitor + previa-healthcheck.timer enabled"

log_step "3/4 Rotacao de logs (logrotate)"
cat > /etc/logrotate.d/previa <<EOF
$LOG_DIR/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su root $APP_USER
}
EOF
if logrotate -d /etc/logrotate.d/previa 2>&1 | grep -q '^error:'; then
    log_warn "logrotate -d reportou erros (veja: logrotate -d /etc/logrotate.d/previa)"
else
    log_ok "logrotate: diario, 14 dias, compactado"
fi

log_step "4/4 Validando"
sleep 3
for svc in previa-monitor.service previa-healthcheck.timer; do
    if systemctl is-active --quiet "$svc"; then
        log_ok "$svc ativo"
    else
        log_error "$svc NAO esta ativo"; systemctl --no-pager status "$svc" | tail -n 10
    fi
done
log_info "Restart policy do monitor: $(systemctl show previa-monitor -p Restart --value), RestartSec=$(systemctl show previa-monitor -p RestartUSec --value)"
log_info "Ultimas metricas: $(tail -n 1 "$LOG_DIR/monitor.log" 2>/dev/null)"
log_ok "Monitoramento configurado"
