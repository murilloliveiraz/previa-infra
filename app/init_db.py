"""PrevIA - cria o banco SQLite com dados SIMULADOS (nenhum dado pessoal real).

Executado pelo 02-app-provision.sh. Idempotente: recria as tabelas de demonstracao.
"""
import os
import random
import sqlite3

DB_PATH = os.environ.get("DB_PATH", "/var/lib/previa/previa.db")

BAIRROS = [
    # (nome, chuva prevista mm/h nas proximas 2h)
    ("Vila Prudente", 38),
    ("Jardim Pantanal", 52),
    ("Lapa de Baixo", 22),
    ("Ipiranga", 30),
    ("Casa Verde", 12),
]

SCHEMA = """
DROP TABLE IF EXISTS sensores;
DROP TABLE IF EXISTS quadras;
DROP TABLE IF EXISTS bairros;
CREATE TABLE bairros (
    id INTEGER PRIMARY KEY,
    nome TEXT NOT NULL,
    chuva_prevista_mmh REAL NOT NULL
);
CREATE TABLE sensores (
    id INTEGER PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    tipo TEXT NOT NULL,            -- boca_de_lobo | galeria | pluviometro
    bairro_id INTEGER NOT NULL REFERENCES bairros(id),
    nivel_pct REAL NOT NULL,       -- ocupacao da capacidade (%)
    obstrucao_pct REAL NOT NULL,   -- entupimento estimado (%)
    online INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE quadras (
    id INTEGER PRIMARY KEY,
    nome TEXT NOT NULL,
    bairro_id INTEGER NOT NULL REFERENCES bairros(id),
    capacidade_m3 REAL NOT NULL,
    volume_m3 REAL NOT NULL,
    status TEXT NOT NULL           -- Disponivel | Travada | Retendo | Esvaziando
);
"""


def main() -> None:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    random.seed(2026)
    con = sqlite3.connect(DB_PATH)
    con.executescript(SCHEMA)
    for i, (nome, chuva) in enumerate(BAIRROS, start=1):
        con.execute("INSERT INTO bairros VALUES (?,?,?)", (i, nome, chuva))
        for j in range(1, 7):
            tipo = random.choice(["boca_de_lobo", "boca_de_lobo", "galeria", "pluviometro"])
            con.execute(
                "INSERT INTO sensores (codigo,tipo,bairro_id,nivel_pct,obstrucao_pct,online) VALUES (?,?,?,?,?,?)",
                (f"S-{i:02d}{j:02d}", tipo, i, round(random.uniform(10, 95), 1),
                 round(random.uniform(0, 80), 1), 0 if random.random() < 0.08 else 1),
            )
        con.execute(
            "INSERT INTO quadras (nome,bairro_id,capacidade_m3,volume_m3,status) VALUES (?,?,?,?,?)",
            (f"Quadra {nome}", i, 420.0, 0.0, "Disponivel"),
        )
    con.commit()
    total = con.execute("SELECT COUNT(*) FROM sensores").fetchone()[0]
    con.close()
    print(f"Banco criado em {DB_PATH} com {len(BAIRROS)} bairros e {total} sensores simulados")


if __name__ == "__main__":
    main()
