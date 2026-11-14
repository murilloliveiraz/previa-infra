#!/usr/bin/env bash
# =====================================================================
# PrevIA - 02: Provisionamento da APLICACAO WEB
#   - Dependencias (python3, venv, nginx, sqlite3)
#   - Usuario de servico dedicado (sem login)
#   - Estrutura de diretorios e permissoes
#   - Variaveis de ambiente em /etc/previa/previa.env
#   - Ambiente virtual Python + bibliotecas
#   - Banco de dados SQLite inicial (dados SIMULADOS)
#   - Orquestracao: servico systemd (gunicorn) + nginx (proxy reverso)
#   - Validacao final via health check HTTP
# Uso: sudo ./scripts/02-app-provision.sh
# =====================================================================
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
require_root
audit_begin "$@"

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------
log_step "1/8 Instalando dependencias da aplicacao"
APP_PKGS=(python3 python3-venv python3-pip nginx sqlite3 curl)
if run apt-get install -y "${APP_PKGS[@]}"; then
    log_ok "Dependencias: ${APP_PKGS[*]}"
    log_info "Versoes: $(python3 --version 2>&1) | $(nginx -v 2>&1) | sqlite $(sqlite3 --version | cut -d' ' -f1)"
else
    die "Falha ao instalar dependencias (veja $EXEC_LOG)"
fi

# ---------------------------------------------------------------------
log_step "2/8 Usuario de servico"
if id "$APP_USER" >/dev/null 2>&1; then
    log_ok "Usuario $APP_USER ja existe"
else
    useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
    log_ok "Usuario de sistema criado: $APP_USER (sem shell de login)"
    audit_event "USER_CREATE" "user=$APP_USER"
fi

# ---------------------------------------------------------------------
log_step "3/8 Diretorios e permissoes"
install -d -o "$APP_USER" -g "$APP_USER" -m 755 "$APP_DIR"
install -d -o "$APP_USER" -g "$APP_USER" -m 750 "$DATA_DIR"
install -d -o root       -g "$APP_USER" -m 750 "$CONF_DIR"
install -d -o "$APP_USER" -g "$APP_USER" -m 775 "$LOG_DIR"
log_ok "$APP_DIR (codigo) | $DATA_DIR (dados) | $CONF_DIR (config) | $LOG_DIR (logs)"

# ---------------------------------------------------------------------
log_step "4/8 Variaveis de ambiente"
install -o root -g "$APP_USER" -m 640 "$CONFIG_FILE" "$CONF_DIR/previa.env"
# SECRET_KEY gerada uma unica vez por servidor (nao fica no repositorio)
if [[ ! -f "$CONF_DIR/secret.env" ]]; then
    echo "PREVIA_SECRET_KEY=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$CONF_DIR/secret.env"
    chown root:"$APP_USER" "$CONF_DIR/secret.env"; chmod 640 "$CONF_DIR/secret.env"
    log_ok "Chave secreta gerada em $CONF_DIR/secret.env"
fi
log_ok "Variaveis instaladas em $CONF_DIR/previa.env (APP_ENV=$APP_ENV, APP_PORT=$APP_PORT)"
audit_event "CONFIG" "env=$CONF_DIR/previa.env"

# ---------------------------------------------------------------------
log_step "5/8 Codigo da aplicacao + ambiente virtual"
rsync -a --delete --exclude 'venv' --exclude '__pycache__' "$PREVIA_ROOT/app/" "$APP_DIR/app/"
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
    run runuser -u "$APP_USER" -- python3 -m venv "$APP_DIR/venv" || die "Falha ao criar venv"
fi
if run runuser -u "$APP_USER" -- "$APP_DIR/venv/bin/pip" install --upgrade pip && \
   run runuser -u "$APP_USER" -- "$APP_DIR/venv/bin/pip" install -r "$APP_DIR/app/requirements.txt"; then
    log_ok "Bibliotecas Python: $(tr '\n' ' ' < "$APP_DIR/app/requirements.txt")"
else
    die "Falha no pip install (veja $EXEC_LOG)"
fi
audit_event "DEPLOY" "version=$APP_VERSION dir=$APP_DIR"

# ---------------------------------------------------------------------
log_step "6/8 Banco de dados"
if runuser -u "$APP_USER" -- env DB_PATH="$DB_PATH" "$APP_DIR/venv/bin/python" "$APP_DIR/app/init_db.py" >> "$EXEC_LOG" 2>&1; then
    log_ok "SQLite pronto em $DB_PATH ($(sqlite3 "$DB_PATH" 'select count(*) from sensores;') sensores simulados)"
else
    die "Falha ao inicializar o banco"
fi

# ---------------------------------------------------------------------
log_step "7/8 Orquestracao: systemd + nginx"
render_template "$PREVIA_ROOT/systemd/previa-app.service" /etc/systemd/system/previa-app.service
render_template "$PREVIA_ROOT/nginx/previa.conf" /etc/nginx/sites-available/previa.conf
ln -sf /etc/nginx/sites-available/previa.conf /etc/nginx/sites-enabled/previa.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t >> "$EXEC_LOG" 2>&1 || die "Configuracao do nginx invalida (nginx -t)"
log_ok "nginx: proxy reverso :80 -> 127.0.0.1:$APP_PORT"

run systemctl daemon-reload
run systemctl enable previa-app nginx
run systemctl restart previa-app
run systemctl restart nginx
audit_event "SERVICE" "previa-app enabled+restarted; nginx enabled+restarted"

# ---------------------------------------------------------------------
log_step "8/8 Validando a aplicacao"
OK=false
for i in $(seq 1 20); do
    if curl -fsS "http://app.$PREVIA_DOMAIN/api/health" -o /tmp/previa-health.json 2>/dev/null; then
        OK=true; break
    fi
    sleep 1
done
if $OK; then
    log_ok "Aplicacao no ar em http://app.$PREVIA_DOMAIN  -> $(cat /tmp/previa-health.json)"
    audit_event "HEALTHCHECK" "status=UP url=http://app.$PREVIA_DOMAIN/api/health"
else
    systemctl --no-pager status previa-app | tail -n 20
    die "Aplicacao nao respondeu ao health check"
fi
