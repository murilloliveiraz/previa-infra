# PrevIA - VM Ubuntu 22.04 provisionada automaticamente
# Requisitos: VirtualBox + Vagrant
#   vagrant up          -> cria a VM e roda ./provision.sh sozinho
#   vagrant ssh         -> entra na VM
#   vagrant provision   -> reenvia os arquivos e roda o provisionamento de novo
#   Navegador no seu PC: http://localhost:8080  ou  http://192.168.56.10
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "previa-srv01"
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.network "forwarded_port", guest: 80, host: 8080
  config.vm.boot_timeout = 600

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "PrevIA-srv01"
    vb.memory = 2048
    vb.cpus   = 2
  end

  # Sem pasta compartilhada (evita depender das Guest Additions):
  # os arquivos sao enviados por SSH para dentro da VM.
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provision "file", source: ".", destination: "/tmp/previa-src"

  config.vm.provision "shell", inline: <<-SHELL
    set -e
    rm -rf /opt/previa-infra && mkdir -p /opt/previa-infra
    cp -a /tmp/previa-src/. /opt/previa-infra/ && rm -rf /tmp/previa-src /opt/previa-infra/.vagrant
    # Garante finais de linha Unix (caso o Git do Windows converta para CRLF)
    find /opt/previa-infra -type f \\( -name '*.sh' -o -name '*.env' -o -name '*.service' \\
         -o -name '*.timer' -o -name '*.conf' -o -name '*.py' \\) -exec sed -i 's/\\r$//' {} +
    # Arquivos vindos do Windows chegam sem permissao de execucao
    chmod +x /opt/previa-infra/provision.sh /opt/previa-infra/scripts/*.sh
    cd /opt/previa-infra && bash ./provision.sh
  SHELL
end
