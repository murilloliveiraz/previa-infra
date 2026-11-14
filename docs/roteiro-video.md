# Roteiro do vídeo (máximo 7 minutos)

Grave a tela da VM (OBS Studio ou a gravação do próprio Windows: `Win + Alt + R`). Deixe a fonte do terminal grande.
Antes de gravar, faça **uma execução de ensaio** para baixar a box do Vagrant (o download não precisa aparecer no vídeo).

| Tempo | Cena | O que mostrar / falar |
|---|---|---|
| 0:00 a 0:40 | **Abertura** | Nome da equipe e da PrevIA. O problema em uma frase. "Esta é a infraestrutura Linux que hospeda o painel da PrevIA, provisionada 100 % por Shell Script." |
| 0:40 a 1:20 | **Repositório** | Estrutura de pastas no GitHub. Abrir `config/previa.env`: "todas as variáveis ficam num lugar só: hostname, DNS, porta, limites de alerta." |
| 1:20 a 3:00 | **Provisionamento automático** | `vagrant destroy -f && vagrant up` (ou `sudo ./provision.sh` numa VM limpa). Narre as etapas conforme aparecem: **01** hostname, IP, DNS, firewall, auditd; **02** dependências, usuário de serviço, variáveis, venv, banco, systemd, nginx, health check; **03** monitor como serviço, watchdog e logrotate. Se demorar, acelere o trecho na edição. |
| 3:00 a 3:40 | **Aplicação no ar** | Navegador em `http://localhost:8080`: painel de risco e página `/infra`. No terminal: `hostname -f`, `getent hosts app.previa.local`, `curl http://app.previa.local/api/health`. |
| 3:40 a 4:20 | **Monitoramento** | `sudo ./scripts/status.sh`, `tail -f /var/log/previa/monitor.log`, `systemctl status previa-monitor` (mostrar `Restart=always`). |
| 4:20 a 6:00 | **Teste de falha** | Em um terminal: `tail -f /var/log/previa/alerts.log`. No outro: `sudo ./scripts/failure-test.sh all`. Comente cada alerta aparecendo: kill -9 → app volta com novo PID; nginx parado → `CRITICO` → `AUTO-HEAL`; CPU/memória/disco → `ALERTA` → `RECUPERADO`. Mostrar o placar final "7 PASSOU / 0 FALHOU". |
| 6:00 a 6:40 | **Auditoria** | `sudo ./scripts/audit-report.sh` e abrir o relatório. `tail /var/log/previa/audit.log` (quem executou o quê e o resultado). `sudo ausearch -k previa_config -i \| tail`. |
| 6:40 a 7:00 | **Fechamento** | "A infraestrutura sobe sozinha, avisa quando algo passa do limite e se recupera de falhas sem intervenção humana, como a PrevIA precisa estar no dia da chuva." |

Dica: o teste `all` leva uns 4 minutos. Se o tempo apertar, rode só `app-crash`, `nginx-stop` e `cpu` no vídeo e mostre o `failure-tests.log` de uma execução completa feita antes.
