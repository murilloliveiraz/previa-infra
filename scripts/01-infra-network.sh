#!/usr/bin/env bash
# =====================================================================
# PrevIA - 01: Provisionamento da INFRAESTRUTURA
#   - Pacotes base do sistema
#   - Hostname e FQDN
#   - Rede: deteccao da interface, IP fixo opcional (netplan)
#   - DNS: servidores (systemd-resolved) + nomes internos (/etc/hosts)
#   - Fuso horario
#   - Firewall (ufw): somente SSH e HTTP
#   - Auditoria do kernel (auditd) para os arquivos da PrevIA
# Uso: sudo ./scripts/01-infra-network.sh
# =====================================================================
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
require_root
audit_begin "$@"

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------
log_step "1/7 Instalando pacotes base"
BASE_PKGS=(tzdata curl jq iproute2 iputils-ping dnsutils ufw auditd logrotate rsync procps cron)
if run apt-get update -y && run apt-get install -y "${BASE_PKGS[@]}"; then
    log_ok "Pacotes base instalados: ${BASE_PKGS[*]}"
else
    die "Falha ao instalar pacotes base (veja $EXEC_LOG)"
fi

# ---------------------------------------------------------------------
log_step "2/7 Configurando hostname"
FQDN="$PREVIA_HOSTNAME.$PREVIA_DOMAIN"
OLD_HOST="$(hostname)"
if has_systemd && hostnamectl set-hostname "$PREVIA_HOSTNAME" 2>/dev/null; then
    log_ok "hostnamectl: $OLD_HOST -> $PREVIA_HOSTNAME"
else
    echo "$PREVIA_HOSTNAME" > /etc/hostname
    hostname "$PREVIA_HOSTNAME" 2>/dev/null || log_warn "Sem permissao para alterar hostname em tempo real (container?)"
    log_ok "/etc/hostname gravado: $PREVIA_HOSTNAME"
fi
audit_event "HOSTNAME" "old=$OLD_HOST new=$PREVIA_HOSTNAME fqdn=$FQDN"

# ---------------------------------------------------------------------
log_step "3/7 Detectando rede e configurando IP"
if [[ "$NET_INTERFACE" == "auto" ]]; then
    NET_INTERFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
fi
[[ -n "$NET_INTERFACE" ]] || die "Nao foi possivel detectar a interface de rede"
CURRENT_IP="$(ip -4 -o addr show dev "$NET_INTERFACE" | awk '{print $4}' | head -n1)"
CURRENT_GW="$(ip route show default | awk '/default/ {print $3; exit}')"
log_info "Interface: $NET_INTERFACE | IP atual: $CURRENT_IP | Gateway: $CURRENT_GW"

if [[ -n "$STATIC_IP" ]]; then
    if command -v netplan >/dev/null 2>&1; then
        NETPLAN_FILE="/etc/netplan/90-previa.yaml"
        cat > "$NETPLAN_FILE" <<EOF
# Gerado por PrevIA 01-infra-network.sh em $(ts)
network:
  version: 2
  ethernets:
    $NET_INTERFACE:
      dhcp4: false
      addresses: [$STATIC_IP]
      routes:
        - to: default
          via: $STATIC_GATEWAY
      nameservers:
        addresses: [$(echo "$DNS_SERVERS" | sed 's/ /, /g')]
        search: [$PREVIA_DOMAIN]
EOF
        chmod 600 "$NETPLAN_FILE"
        if run netplan apply; then
            log_ok "IP fixo aplicado: $STATIC_IP via $STATIC_GATEWAY ($NETPLAN_FILE)"
            audit_event "NETWORK" "static_ip=$STATIC_IP gw=$STATIC_GATEWAY iface=$NET_INTERFACE"
        else
            log_error "netplan apply falhou - revertendo arquivo"
            rm -f "$NETPLAN_FILE"; run netplan apply
        fi
    else
        log_warn "netplan nao encontrado; IP fixo nao aplicado"
    fi
else
    log_ok "STATIC_IP vazio: mantendo DHCP ($CURRENT_IP)"
fi
SERVER_IP="${STATIC_IP%%/*}"
SERVER_IP="${SERVER_IP:-${CURRENT_IP%%/*}}"

# ---------------------------------------------------------------------
log_step "4/7 Configurando DNS"
# 4a) Nomes internos -> bloco gerenciado no /etc/hosts (idempotente)
HOSTS_BEGIN="# >>> PREVIA (gerenciado automaticamente) >>>"
HOSTS_END="# <<< PREVIA <<<"
cp /etc/hosts "/etc/hosts.bak.previa" 2>/dev/null
HOSTS_TMP="$(mktemp)"
sed "/$HOSTS_BEGIN/,/$HOSTS_END/d" /etc/hosts > "$HOSTS_TMP"
{
    echo "$HOSTS_BEGIN"
    echo "127.0.1.1   $FQDN $PREVIA_HOSTNAME"
    echo "$SERVER_IP   $APP_HOSTNAMES"
    echo "$HOSTS_END"
} >> "$HOSTS_TMP"
# cat > preserva o inode (necessario quando /etc/hosts e montado, ex.: containers)
cat "$HOSTS_TMP" > /etc/hosts && rm -f "$HOSTS_TMP"
log_ok "/etc/hosts: $FQDN e [$APP_HOSTNAMES] -> $SERVER_IP"

# 4b) Servidores DNS externos via systemd-resolved
if has_systemd && systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/10-previa.conf <<EOF
# Gerado por PrevIA em $(ts)
[Resolve]
DNS=$DNS_SERVERS
FallbackDNS=9.9.9.9
Domains=$PREVIA_DOMAIN
EOF
    run systemctl restart systemd-resolved
    log_ok "systemd-resolved: DNS=$DNS_SERVERS Domains=$PREVIA_DOMAIN"
else
    log_warn "systemd-resolved inativo; DNS externo mantido como esta (/etc/resolv.conf)"
fi
audit_event "DNS" "servers='$DNS_SERVERS' domain=$PREVIA_DOMAIN internal='$APP_HOSTNAMES'"

# 4c) Validacao
for name in $FQDN $APP_HOSTNAMES; do
    if getent hosts "$name" >/dev/null; then
        log_ok "Resolve $name -> $(getent hosts "$name" | awk '{print $1}')"
    else
        log_error "Nao resolve $name"
    fi
done
if getent hosts github.com >/dev/null; then
    log_ok "DNS externo funcionando (github.com resolvido)"
else
    log_warn "DNS externo nao respondeu"
fi

# ---------------------------------------------------------------------
log_step "5/7 Fuso horario"
if has_systemd && timedatectl set-timezone "$TIMEZONE" 2>/dev/null; then
    log_ok "Timezone: $TIMEZONE"
else
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime && echo "$TIMEZONE" > /etc/timezone
    log_ok "Timezone (link /etc/localtime): $TIMEZONE"
fi

# ---------------------------------------------------------------------
log_step "6/7 Firewall (ufw)"
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow OpenSSH
run ufw allow 80/tcp comment 'PrevIA HTTP'
if run ufw --force enable; then
    log_ok "ufw ativo: entrada bloqueada, liberado SSH(22) e HTTP(80)"
    audit_event "FIREWALL" "ufw enabled allow=22,80"
else
    log_warn "ufw nao pode ser ativado neste ambiente (ex.: container sem iptables)"
fi

# ---------------------------------------------------------------------
log_step "7/7 Auditoria do kernel (auditd)"
cat > /etc/audit/rules.d/previa.rules <<EOF
# PrevIA - regras de auditoria (gerado em $(ts))
# Alteracoes na configuracao da PrevIA
-w $CONF_DIR -p wa -k previa_config
# Alteracoes no codigo da aplicacao
-w $APP_DIR -p wa -k previa_app
# Alteracoes nos servicos systemd da PrevIA
-w /etc/systemd/system/previa-app.service -p wa -k previa_service
-w /etc/systemd/system/previa-monitor.service -p wa -k previa_service
# Execucao dos scripts de operacao
-w /usr/local/bin/previa-monitor -p x -k previa_exec
-w /usr/local/bin/previa-healthcheck -p x -k previa_exec
# Alteracoes de rede / DNS / hostname
-w /etc/hosts -p wa -k previa_network
-w /etc/hostname -p wa -k previa_network
-w /etc/netplan -p wa -k previa_network
EOF
if has_systemd && run systemctl enable --now auditd && run augenrules --load; then
    log_ok "auditd ativo com regras previa_* ($(auditctl -l 2>/dev/null | grep -c previa) regras carregadas)"
else
    log_warn "auditd indisponivel neste ambiente; trilha de auditoria segue em $AUDIT_LOG"
fi

# ---------------------------------------------------------------------
log_step "Resumo da infraestrutura"
{
    echo "Hostname : $(hostname)  (FQDN: $FQDN)"
    echo "Interface: $NET_INTERFACE"
    echo "IP       : $SERVER_IP"
    echo "Gateway  : $CURRENT_GW"
    echo "DNS      : $DNS_SERVERS (dominio $PREVIA_DOMAIN)"
    echo "Timezone : $TIMEZONE  -> $(date)"
} | tee -a "$EXEC_LOG"
log_ok "Infraestrutura provisionada"
