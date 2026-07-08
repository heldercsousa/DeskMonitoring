=======================================================================
 V16 — Arquivos /etc/config prontos p/ upload (Xiaomi AX3000T, OpenWrt 24.10)
=======================================================================

ESQUEMA DE IP
  VLAN 20 WORK-DEV   192.168.20.1/24
  VLAN 30 HOME/GESTAO 192.168.30.1/24   <- administre SEMPRE por aqui (lan1)
  VLAN 40 HOME-IOT   192.168.40.1/24
  VLAN 50 GUEST      192.168.50.1/24
  WAN     PPPoE sobre VLAN 10 (cliente@cliente / cliente, MTU 1492)
  Portas: lan1=vlan30  lan2=vlan40  lan3=vlan50  lan4=vlan20

ANTES DE COMEÇAR (faça no ENSAIO A SECO, Bloco 0.5)
  - Recovery TFTP montado e testado (risco Winbond).
  - Pacotes: opkg update && opkg install wpad-openssl avahi-daemon
    (remova wpad-basic-mbedtls antes de instalar wpad-openssl).
  - Opcional (DNS filtrado): adguardhome OU https-dns-proxy.

ORDEM DE APLICAÇÃO (conecte o PC na porta lan1 / vlan30!)
  1. /etc/config/network      (cria VLANs + WAN)   -> aplique e reconecte na lan1
  2. /etc/config/dhcp         (DHCP + DNS por VLAN)
  3. /etc/config/firewall     (zonas + regras + DNS forcado)
  4. /etc/config/wireless     (troque os PSKs antes!)
  5. /etc/avahi/avahi-daemon.conf
  6. /etc/config/uhttpd  (trecho: LuCI so na vlan30)
  7. /etc/config/dropbear (SO depois de subir sua chave publica e testar login)
  Reinicie os serviços:  /etc/init.d/network restart ; /etc/init.d/firewall restart ;
                         wifi reload ; /etc/init.d/avahi-daemon restart ;
                         /etc/init.d/uhttpd restart ; /etc/init.d/dropbear restart

AVISOS
  - Nomes de zona NAO podem comecar com digito (fw4/24.10 ignora). Use work/home/iot/guest.
  - Confirme os nomes de device (wan, lan1..lan4) na sua build: LuCI > Network > Interfaces > Devices.
  - Confirme os 'path' dos radios: veja em /etc/config/wireless gerado de fabrica ou 'iw phy'.
  - dropbear: só desative PasswordAuth DEPOIS de confirmar que a chave SSH funciona,
    senao voce se tranca para fora.
  - Faca backup (LuCI > System > Backup) e guarde CIFRADO (contem senhas/PSKs).

VALIDACAO (Bloco 8)
  - 40 -> 20 deve FALHAR ; 30 -> 40 OK ; 40 -> 30 FALHA ; 50 -> so 80/443.
  - De fora da vlan30, abrir LuCI/SSH deve FALHAR.
  - Fixe um DNS externo num cliente: deve continuar sendo atendido pelo roteador.
