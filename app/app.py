"""PrevIA - Quadras Inteligentes contra Alagamentos (aplicacao web hospedada).

Painel web + API REST que a infraestrutura Linux sobe automaticamente.
O calculo de risco aqui e uma regra simplificada para demonstracao; o modelo
de IA completo e entregue na disciplina de Inteligencia Artificial & ML.
"""
import json
import os
import socket
import sqlite3
from datetime import datetime

from flask import Flask, jsonify, render_template

DB_PATH = os.environ.get("DB_PATH", "/var/lib/previa/previa.db")
DATA_DIR = os.environ.get("DATA_DIR", "/var/lib/previa")
APP_VERSION = os.environ.get("APP_VERSION", "dev")
APP_ENV = os.environ.get("APP_ENV", "development")

app = Flask(__name__)
app.secret_key = os.environ.get("PREVIA_SECRET_KEY", "dev-only")


def db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def nivel_risco(score: float) -> str:
    if score >= 75:
        return "Critico"
    if score >= 55:
        return "Alto"
    if score >= 35:
        return "Moderado"
    return "Baixo"


def calcular_risco():
    """Score 0-100 por bairro: chuva prevista (50%), nivel medio (30%), obstrucao media (20%)."""
    con = db()
    rows = con.execute(
        """SELECT b.id, b.nome, b.chuva_prevista_mmh AS chuva,
                  AVG(s.nivel_pct) AS nivel, AVG(s.obstrucao_pct) AS obstrucao,
                  SUM(CASE WHEN s.online = 0 THEN 1 ELSE 0 END) AS offline
           FROM bairros b JOIN sensores s ON s.bairro_id = b.id
           GROUP BY b.id ORDER BY b.nome"""
    ).fetchall()
    con.close()
    out = []
    for r in rows:
        chuva_norm = min(r["chuva"] / 60 * 100, 100)
        score = round(0.5 * chuva_norm + 0.3 * r["nivel"] + 0.2 * r["obstrucao"], 1)
        nivel = nivel_risco(score)
        out.append({
            "bairro": r["nome"],
            "chuva_prevista_mmh": r["chuva"],
            "nivel_medio_pct": round(r["nivel"], 1),
            "obstrucao_media_pct": round(r["obstrucao"], 1),
            "sensores_offline": r["offline"],
            "score": score,
            "risco": nivel,
            "acao": {
                "Critico": "Alertar moradores, travar e abrir comporta da quadra",
                "Alto": "Travar quadra e despachar robo desentupidor",
                "Moderado": "Agendar inspecao das bocas de lobo",
                "Baixo": "Monitoramento normal",
            }[nivel],
        })
    return out


def infra_metrics():
    try:
        with open(os.path.join(DATA_DIR, "metrics.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


@app.get("/")
def index():
    con = db()
    quadras = con.execute(
        "SELECT q.*, b.nome AS bairro FROM quadras q JOIN bairros b ON b.id = q.bairro_id"
    ).fetchall()
    con.close()
    return render_template("index.html", riscos=calcular_risco(), quadras=quadras,
                           host=socket.gethostname(), versao=APP_VERSION,
                           agora=datetime.now().strftime("%d/%m/%Y %H:%M:%S"))


@app.get("/infra")
def infra():
    return render_template("infra.html", m=infra_metrics(), host=socket.gethostname())


@app.get("/api/health")
def health():
    try:
        con = db()
        con.execute("SELECT 1").fetchone()
        con.close()
        db_ok = "ok"
    except sqlite3.Error as exc:  # banco indisponivel -> 503
        return jsonify(status="degraded", db=str(exc)), 503
    return jsonify(status="ok", db=db_ok, app="previa", version=APP_VERSION,
                   env=APP_ENV, host=socket.gethostname(), pid=os.getpid(),
                   time=datetime.now().isoformat(timespec="seconds"))


@app.get("/api/risco")
def api_risco():
    return jsonify(calcular_risco())


@app.get("/api/sensores")
def api_sensores():
    con = db()
    rows = [dict(r) for r in con.execute(
        "SELECT s.*, b.nome AS bairro FROM sensores s JOIN bairros b ON b.id = s.bairro_id")]
    con.close()
    return jsonify(rows)


@app.get("/api/quadras")
def api_quadras():
    con = db()
    rows = [dict(r) for r in con.execute(
        "SELECT q.*, b.nome AS bairro FROM quadras q JOIN bairros b ON b.id = q.bairro_id")]
    con.close()
    return jsonify(rows)


@app.get("/api/infra")
def api_infra():
    m = infra_metrics()
    return (jsonify(m), 200) if m else (jsonify(error="monitor sem dados"), 503)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.environ.get("APP_PORT", 8000)), debug=True)
