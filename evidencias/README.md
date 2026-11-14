# Evidências técnicas

Todas as evidências abaixo saíram da VM **PrevIA-srv01** (Ubuntu 22.04 no VirtualBox, criada com `vagrant up`). Os prints de terminal foram tirados do console da própria VM.

## Prints (`prints/`)

| # | Print | O que comprova | Critério |
|---|---|---|---|
| 01 | [Provisionamento: infra](prints/01-provisionamento-infra-rede-dns.png) | Pacotes base, hostname, detecção de IP/gateway, DNS (systemd-resolved + nomes internos), timezone | Infra: rede, DNS, IP |
| 02 | [Provisionamento: aplicação](prints/02-provisionamento-aplicacao.png) | Dependências, usuário de serviço, diretórios, variáveis, venv, banco, systemd + nginx, health check | Provisionamento da aplicação |
| 03 | [Provisionamento concluído](prints/03-provisionamento-concluido-status.png) | Monitor como serviço, logrotate, todos os serviços `active`, "PrevIA provisionada em 64s" | Funcionamento completo |
| 04 | [Painel de risco](prints/04-app-painel-de-risco.png) | Aplicação web hospedada respondendo pelo nginx | Funcionamento completo |
| 05 | [Página /infra](prints/05-app-pagina-infra.png) | Métricas do monitor exibidas na aplicação | Monitoramento |
| 06 | [API /api/health](prints/06-app-api-health.png) | Health check JSON (app + banco) | Funcionamento completo |
| 07 | [Rede, DNS e firewall](prints/07-rede-dns-firewall.png) | Hostname, IPs, rotas, DNS 1.1.1.1/8.8.8.8, domínio previa.local, ufw | Infra: rede, DNS, IP |
| 08 | [Serviços e tolerância a falhas](prints/08-servicos-systemd-tolerancia.png) | `Restart=always`, `StartLimitIntervalUSec=0`, `OOMScoreAdjust=-900`, timer do watchdog | Serviço tolerante a falhas |
| 09 | [monitor.log](prints/09-monitor-log.png) | Coleta de CPU, memória, disco e serviços a cada 15 s | Monitoramento via log |
| 10 | [Testes de falha 7/7](prints/10-testes-de-falha-7-de-7.png) | kill -9, monitor derrubado, nginx parado, app parado, CPU, memória, disco: todos recuperados ou alertados | Teste de falha |
| 11 | [alerts.log](prints/11-alertas-log.png) | Ciclo CRITICO → AUTO-HEAL → RECUPERADO | Alertas CPU/disco/memória |
| 12 | [auditd](prints/12-auditd-regras-eventos.png) | 9 regras `previa_*` no kernel e os eventos registrados por chave | Logs de auditoria |
| 13 | [audit.log](prints/13-audit-log-scripts.png) | Trilha de cada script: usuário, ação, resultado e duração | Logs de auditoria e execução |
| 14 | [Relatório de auditoria](prints/14-relatorio-auditoria.png) | Relatório consolidado gerado pelo `audit-report.sh` | Logs de auditoria |

## Logs e relatório da VM (`execucao-vm-virtualbox/`)

Cópia dos arquivos reais de `/var/log/previa/` e do relatório consolidado (`relatorio-auditoria.txt`).

## Execução em container (`exemplo-execucao-container/`)

Execução feita antes, num container Ubuntu 22.04 com systemd, usada para validar os scripts durante o desenvolvimento. Particularidades do container: o auditd não roda em container, e o limite de disco foi reduzido para 3 % porque o disco do container tem 1 TB.

## Problemas encontrados pelos testes e corrigidos

| Problema | Como apareceu | Correção |
|---|---|---|
| Limites de alerta lidos errado pelo systemd | Alertas de memória/disco não disparavam (valor vinha com o comentário junto) | Comentários do `previa.env` movidos para linhas próprias |
| Teste de CPU falhava com 2 vCPUs | O teste conferia o log no mesmo segundo em que o alerta era escrito | Testes passaram a aguardar o alerta (checagem a cada 2 s) |
| Scripts sem permissão de execução | Arquivos copiados do Windows chegavam sem o bit `+x` | `chmod +x` no Vagrantfile e bit executável gravado no Git |
