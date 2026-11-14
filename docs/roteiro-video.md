# Roteiro do vídeo: Operating Systems (máx. 7 min)

Cada cena traz **o que fazer** (cliques e comandos) e **o que falar**. As falas são sugestões: falem com as próprias palavras, mas mantenham a ordem.

---

## Antes de gravar (preparação, não aparece no vídeo)

1. **Deixe a VM rápida (recomendado).** No PowerShell **como Administrador**: `bcdedit /set hypervisorlaunchtype off`. Depois desligue a Integridade de memória (Segurança do Windows → Segurança do dispositivo → Isolamento de núcleo) e **reinicie o PC**.
2. **Gravador:** use o **OBS Studio** (grátis) ou o Clipchamp, que já vem no Windows 11. Grave a tela inteira, com microfone.
3. **Janelas abertas e organizadas:**
   - **Windows Terminal, aba 1 (PowerShell)**, já na pasta do projeto:
     ```powershell
     cd C:\Users\Muril\Downloads\GS-112026\OperatingSystems-PrevIA
     ```
   - **Navegador** com 2 abas: o repositório no GitHub e `http://localhost:8080` (vai dar erro até a VM subir; tudo bem).
   - **VS Code** com o projeto aberto (para mostrar os arquivos).
4. **Fonte grande no terminal:** `Ctrl` + `+` umas 3 vezes.
5. **Apague a VM** para provisionar do zero no vídeo:
   ```powershell
   vagrant destroy -f
   ```
6. Deixe a box já baixada: se você já rodou `vagrant up` uma vez, ela já está no PC.

> **Sobre o tempo:** o `vagrant up` do zero leva de 5 a 10 minutos. **Grave tudo e corte as esperas na edição** (no Clipchamp: selecionar o trecho → Delete; ou acelerar o trecho em 8x). As falas das cenas 3 e 4 foram feitas para serem ditas **enquanto o terminal roda**.

---

## Cena 1: Abertura (0:00 a 0:30)

**Tela:** README do repositório no GitHub (topo, com a Ficha da CitizenTech).

**Falar:**
> "Olá, somos a equipe da **PrevIA**, Quadras Inteligentes contra Alagamentos. Em São Paulo, a rua só alaga de verdade porque a drenagem está entupida e o alerta chega tarde. A PrevIA usa sensores e IA para prever o alagamento, desentupir a rede antes da chuva e transformar quadras esportivas em reservatórios. Neste vídeo vamos mostrar a **infraestrutura Linux** que hospeda a aplicação web da PrevIA, provisionada **inteiramente por Shell Script**."

---

## Cena 2: O repositório e a configuração (0:30 a 1:15)

**Tela:** VS Code.

**Fazer:** mostrar a árvore de pastas → abrir `config/previa.env` → abrir rapidamente `provision.sh`.

**Falar:**
> "O repositório está organizado assim: o `provision.sh` é o ponto de entrada e chama três scripts em ordem: **01**, que prepara a infraestrutura, com rede, DNS, hostname, firewall e auditoria; **02**, que provisiona a aplicação; e **03**, que configura o monitoramento.
> Todas as variáveis ficam num único arquivo, o `previa.env`: hostname, domínio, servidores DNS, IP fixo opcional, porta da aplicação e os limites de alerta de CPU, memória e disco. Nenhum valor fica escondido dentro dos scripts.
> O Vagrantfile cria uma VM Ubuntu 22.04 no VirtualBox e executa o `provision.sh` automaticamente."

---

## Cena 3: Provisionamento automático: infraestrutura (1:15 a 2:30)

**Tela:** Windows Terminal (aba 1).

**Fazer:** digitar
```powershell
vagrant up
```
Espere aparecer o banner **PrevIA** e as etapas `==> 1/7 ... 7/7`. *(Corte a espera do download e da criação da VM.)*

**Falar, enquanto as linhas aparecem:**
> "Com um único comando, o Vagrant cria a máquina virtual e chama o nosso script. Repare nas etapas do **script 01**:
> instala os pacotes base;
> define o **hostname** `previa-srv01` e o nome completo `previa-srv01.previa.local`;
> detecta a interface de rede, o **IP** e o gateway; se quisermos IP fixo, ele gera a configuração do netplan;
> configura o **DNS**: servidores 1.1.1.1 e 8.8.8.8 no systemd-resolved e os nomes internos `app`, `api` e `painel.previa.local`, e depois **valida** se cada nome resolve;
> ajusta o fuso horário, liga o **firewall** liberando só SSH e HTTP;
> e carrega as **regras do auditd**, que registram no kernel qualquer alteração na configuração, no código e na rede."

---

## Cena 4: Provisionamento automático: aplicação e monitoramento (2:30 a 3:30)

**Tela:** mesmo terminal, rolando para o **script 02** e depois o **03**. *(Corte as esperas.)*

**Falar:**
> "O **script 02** sobe a aplicação: instala Python, nginx e SQLite; cria um **usuário de serviço** sem login, por segurança; cria as pastas com as permissões certas; instala as **variáveis de ambiente** em `/etc/previa` e gera uma chave secreta única; cria o ambiente virtual Python, instala as bibliotecas e inicializa o banco de dados.
> Na **orquestração**, a aplicação vira um serviço do systemd rodando com Gunicorn, e o nginx funciona como proxy reverso na porta 80. No final, o script **testa sozinho** o health check da aplicação.
> O **script 03** instala o monitor como serviço do systemd, o watchdog com timer de 1 minuto e a rotação de logs."

**Fazer:** quando terminar, mostrar o painel final com tudo `active` e a linha **"PrevIA provisionada em …s"**.

> "Pronto: todos os serviços ativos e a aplicação respondendo, sem nenhum comando manual."

---

## Cena 5: A aplicação hospedada (3:30 a 4:05)

**Tela:** navegador, aba `http://localhost:8080` → **F5**.

**Fazer:** mostrar o painel de risco → clicar em **Infraestrutura** → clicar em **API**.

**Falar:**
> "Aqui está a aplicação da PrevIA rodando dentro da VM: o painel de risco de alagamento por bairro e o status das quadras-reservatório.
> Na aba **Infraestrutura**, a própria aplicação mostra a saúde do servidor, com CPU, memória, disco e serviços. Esses dados vêm do nosso serviço de monitoramento.
> E esta é a API de health check, que o monitor usa para saber se a aplicação está no ar."

---

## Cena 6: Rede, serviços e monitoramento (4:05 a 4:45)

**Tela:** Windows Terminal. Abra a **aba 2** (`Ctrl+Shift+T`) e digite:
```powershell
vagrant ssh
```
Dentro da VM:
```bash
cd /opt/previa-infra
hostname -f && getent hosts app.previa.local
sudo ./scripts/status.sh
systemctl show previa-app previa-monitor -p Id -p Restart -p RestartUSec
tail -n 5 /var/log/previa/monitor.log
```

**Falar:**
> "Dentro da VM, o hostname e o DNS interno estão funcionando. O status mostra os cinco serviços ativos: aplicação, monitor, watchdog, nginx e auditd.
> A **tolerância a falhas** tem três camadas: primeiro, o systemd com `Restart=always`, que reinicia qualquer serviço que cair; segundo, o monitor, que faz **auto-heal** da aplicação e do nginx; terceiro, um watchdog a cada minuto que sobe até o próprio monitor.
> O monitor grava uma linha a cada 15 segundos com CPU, memória, disco e o estado dos serviços."

---

## Cena 7: Teste de falha ao vivo (4:45 a 6:05)

**Tela:** divida o terminal em dois painéis (`Alt+Shift+D` no Windows Terminal) ou use as duas abas.

**Painel de cima:** `vagrant ssh` e depois:
```bash
tail -F /var/log/previa/alerts.log
```
**Painel de baixo** (na VM, em `/opt/previa-infra`):
```bash
sudo ./scripts/failure-test.sh app-crash
sudo ./scripts/failure-test.sh nginx-stop
sudo ./scripts/failure-test.sh disk
```

**Falar:**
> "Agora vamos **quebrar** o servidor de propósito. Em cima ficam os alertas em tempo real.
> **Primeiro teste:** um `kill -9` no processo da aplicação, simulando um crash. Vejam: o systemd sobe a aplicação de novo em poucos segundos, com outro PID. **Passou.**
> **Segundo teste:** derrubamos o nginx. O monitor detecta, gera o alerta **CRÍTICO**, reinicia o serviço sozinho com **AUTO-HEAL** e registra **RECUPERADO**. Ninguém precisou intervir.
> **Terceiro teste:** enchemos o disco até passar do limite de 85%. O monitor gera o **ALERTA de disco**; o teste apaga o arquivo e o monitor registra a recuperação."

**Fazer:** `Ctrl+C` no painel de cima e mostrar o placar completo da bateria (CPU e memória incluídos):
```bash
grep -E 'PASSOU|FALHOU' /var/log/previa/failure-tests.log | tail -n 7
```
> "A bateria completa também testa estresse de CPU, de memória e a queda do próprio monitor: **sete de sete testes passando**."

---

## Cena 8: Auditoria (6:05 a 6:45)

**Fazer:**
```bash
sudo tail -n 8 /var/log/previa/audit.log
sudo aureport -k --summary -i
sudo ./scripts/audit-report.sh
```

**Falar:**
> "Toda execução de script fica registrada no **audit.log**: quem rodou, quando, o que fez, o resultado e a duração. No nível do kernel, o **auditd** registra qualquer alteração na configuração, no código, nos serviços e na rede da PrevIA; aqui está o resumo por categoria.
> E o `audit-report.sh` gera um relatório consolidado com identidade do servidor, rede, serviços, alertas, testes de falha e trilha de auditoria, que fica guardado nas evidências do repositório."

---

## Cena 9: Fechamento (6:45 a 7:00)

**Tela:** README no GitHub (seção de Evidências).

**Falar:**
> "Resumindo: a infraestrutura da PrevIA **sobe sozinha**, **avisa** quando algo passa do limite e **se recupera** de falhas sem intervenção humana, como um sistema contra alagamentos precisa ser no dia da chuva. Todo o código, os logs e as evidências estão no repositório. Obrigado!"

---

## Checklist final

- [ ] Vídeo com **até 7:00**
- [ ] Subir no YouTube como **Não listado** e copiar o link
- [ ] Colar o link no topo do `README.md` e rodar `git commit -am "Link do video"; git push`
- [ ] Um integrante envia o link do **repositório** no Teams até **19/11, 23h55**
