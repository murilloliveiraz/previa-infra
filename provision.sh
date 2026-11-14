#!/usr/bin/env bash
# =====================================================================
# PrevIA - PROVISIONAMENTO COMPLETO (ponto de entrada unico)
# Sobe do zero, de forma automatizada, toda a infraestrutura Linux
# que hospeda a aplicacao web PrevIA.
#
#   01-infra-network.sh   -> hostname, rede/IP, DNS, timezone, firewall, auditd
#   02-app-provision.sh   -> dependencias, usuario, variaveis, app, banco, systemd, nginx
#   03-monitoring-setup.sh-> monitor como servico + watchdog + logrotate
#
# Uso: sudo ./provision.sh
# Idempotente: pode ser executado de novo sem quebrar o ambiente.
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")"
chmod +x scripts/*.sh
source scripts/lib/common.sh
require_root
audit_begin "$@"

START=$(date +%s)
cat <<'BANNER'

   ____                 ___    _
  |  _ \ _ __ _____   _|_ _|  / \      Quadras Inteligentes contra Alagamentos
  | |_) | '__/ _ \ \ / /| |  / _ \     Provisionamento automatizado da infraestrutura
  |  __/| | |  __/\ V / | | / ___ \
  |_|   |_|  \___| \_/ |___/_/   \_\

BANNER
log_info "Configuracao: $CONFIG_FILE"
log_info "Logs de execucao: $EXEC_LOG | Auditoria: $AUDIT_LOG"

for step in scripts/01-infra-network.sh scripts/02-app-provision.sh scripts/03-monitoring-setup.sh; do
    log_step ">>> Executando $step"
    if ! bash "$step"; then
        die "Etapa $step falhou. Provisionamento interrompido (veja $EXEC_LOG)"
    fi
done

DUR=$(( $(date +%s) - START ))
echo
bash scripts/status.sh
echo
log_ok "PrevIA provisionada em ${DUR}s"
log_info "Acesse: http://app.$PREVIA_DOMAIN  (na VM)  ou  http://<IP-da-VM>  (no seu computador)"
log_info "Teste de falha: sudo ./scripts/failure-test.sh all"
log_info "Relatorio de auditoria: sudo ./scripts/audit-report.sh"
