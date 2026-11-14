# Registro de uso de IA (prompts.md)

Conforme as regras da GS, a IA foi usada como copiloto. Todos os integrantes revisaram e sabem explicar cada script.

| # | Ferramenta | Prompt (resumo) | Como usamos o resultado |
|---|---|---|---|
| 1 | Claude (Claude Code) | "Com base na ideia da PrevIA e no enunciado de Operating Systems, monte um repositório com scripts Bash de provisionamento de infra (rede, DNS, IP), provisionamento da aplicação, monitoramento de CPU/disco/memória como serviço tolerante a falhas, logs de auditoria e teste de falha." | Estrutura inicial dos scripts, units systemd e README. Revisamos linha a linha e testamos num container Ubuntu com systemd. |
| 2 | Claude (Claude Code) | Depuração: os alertas de memória e disco não disparavam no teste de falha. | Descobrimos que o `EnvironmentFile` do systemd não aceita comentário na mesma linha da variável e corrigimos o `config/previa.env`. |

> Equipe: acrescentem aqui os prompts que vocês usarem a partir de agora.
