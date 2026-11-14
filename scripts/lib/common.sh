#!/usr/bin/env bash
# =====================================================================
# PrevIA - Biblioteca comum dos scripts
# - Carrega a configuracao central (config/previa.env)
# - Funcoes de log padronizadas (tela + arquivo)
# - Trilha de auditoria: toda execucao de script e registrada em
#   /var/log/previa/audit.log (quem, quando, o que, resultado, duracao)
# =====================================================================

# Diretorio raiz do projeto (pasta acima de scripts/)
PREVIA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 1) Configuracao: usa /etc/previa/previa.env se ja instalado, senao a do repositorio
if [[ -f "${PREVIA_CONFIG:-}" ]]; then
    CONFIG_FILE="$PREVIA_CONFIG"
elif [[ -f "$PREVIA_ROOT/config/previa.env" ]]; then
    CONFIG_FILE="$PREVIA_ROOT/config/previa.env"
else
    CONFIG_FILE="/etc/previa/previa.env"
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

LOG_DIR="${LOG_DIR:-/var/log/previa}"
SCRIPT_NAME="$(basename "$0")"
EXEC_LOG="$LOG_DIR/provision.log"
AUDIT_LOG="$LOG_DIR/audit.log"

# Cores so quando a saida e um terminal
if [[ -t 1 ]]; then
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_RST=$'\e[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_RST=""
fi

ts() { date '+%Y-%m-%d %H:%M:%S'; }

_write_log() {
    # $1 = nivel, $2.. = mensagem
    local level="$1"; shift
    local line
    line="$(ts) [$level] [$SCRIPT_NAME] $*"
    mkdir -p "$LOG_DIR" 2>/dev/null
    echo "$line" >> "$EXEC_LOG" 2>/dev/null
    logger -t "previa-$SCRIPT_NAME" -- "[$level] $*" 2>/dev/null || true
}

log_info()  { echo "${C_BLU}[INFO]${C_RST}  $*"; _write_log INFO "$*"; }
log_ok()    { echo "${C_GRN}[ OK ]${C_RST}  $*"; _write_log OK "$*"; }
log_warn()  { echo "${C_YEL}[WARN]${C_RST}  $*"; _write_log WARN "$*"; }
log_error() { echo "${C_RED}[ERRO]${C_RST}  $*" >&2; _write_log ERROR "$*"; }
log_step()  { echo; echo "${C_BLU}==> $*${C_RST}"; _write_log STEP "$*"; }

die() { log_error "$*"; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Este script precisa ser executado como root (use sudo)."
}

# Executa um comando registrando-o no log; nao aborta, devolve o codigo
run() {
    _write_log CMD "$*"
    "$@" >> "$EXEC_LOG" 2>&1
}

has_systemd() { [[ -d /run/systemd/system ]]; }

# ---------- Auditoria ----------
# audit_event ACAO DETALHE  -> linha no audit.log
audit_event() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    local who="${SUDO_USER:-$(id -un)}"
    printf '%s | user=%s | uid=%s | host=%s | script=%s | action=%s | %s\n' \
        "$(ts)" "$who" "$EUID" "$(hostname)" "$SCRIPT_NAME" "$1" "${2:-}" >> "$AUDIT_LOG" 2>/dev/null
}

_audit_start_epoch=0
_audit_on_exit() {
    local rc=$?
    local dur=$(( $(date +%s) - _audit_start_epoch ))
    if [[ $rc -eq 0 ]]; then
        audit_event "END" "status=SUCCESS rc=0 duration=${dur}s"
    else
        audit_event "END" "status=FAILURE rc=$rc duration=${dur}s"
    fi
}

# Chamar no inicio de cada script: registra INICIO e, via trap, o FIM com resultado
audit_begin() {
    _audit_start_epoch=$(date +%s)
    audit_event "START" "args='$*' config=$CONFIG_FILE"
    trap _audit_on_exit EXIT
}

# Substitui {{VAR}} de um template pelos valores das variaveis de ambiente
render_template() {
    # $1 = template, $2 = destino
    local content
    content="$(cat "$1")"
    local var
    for var in PREVIA_HOSTNAME PREVIA_DOMAIN APP_NAME APP_USER APP_DIR APP_PORT \
               APP_WORKERS CONF_DIR DATA_DIR LOG_DIR APP_HOSTNAMES; do
        content="${content//\{\{$var\}\}/${!var}}"
    done
    printf '%s\n' "$content" > "$2"
}
