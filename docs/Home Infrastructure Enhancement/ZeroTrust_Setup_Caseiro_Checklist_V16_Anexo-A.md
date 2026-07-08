# **Anexo Técnico V16-A — Rede Zero-Trust Residencial OpenWrt (Vivo Fibra 600 Mbps, Brasília/DF)**

## **TL;DR**

* O **Xiaomi AX3000T (MT7981B / Filogic 820, ARM dual-core A53)** segue sendo a melhor compra presencial em Brasília: único roteador com suporte oficial OpenWrt e CPU ARM forte no varejo físico (Kabum, Amazon BR, ML Full), ~R$ 335–370. Belkin RT3200/Linksys E8450 e GL.iNet Flint 2, embora melhores para flash, são praticamente só importação.
* 🆕 **WAN — rota principal recomendada: HGU da Vivo em Modo Bridge** (Wi-Fi desligado) → cabo LAN1 → porta WAN do AX3000T, que assume PPPoE + VLAN 10 + firewall. **Não exige** extração GPON nem ONT standalone. A ONT TP-Link XZ000-G3 vira **trilha avançada opcional** (Parte 2F).
* A arquitetura Zero-Trust: **5 zonas** (work/home/iot/guest + wan) com DSA bridge no OpenWrt 24.10, forwarding stateful unidirecional 30→40, mDNS reflector restrito a VLANs 30/40, WAN PPPoE em VLAN 10 (`cliente@cliente`/`cliente`, MTU 1492).
* 🆕 **Correções da V16 no firewall:** (1) **zona GUEST (vlan50) criada de fato** — faltava na V15; (2) **regras de DHCP+DNS para as zonas com input REJECT** (work/iot/guest), sem as quais os clientes não pegam IP; (3) **redirect forçado de DNS (porta 53)** para o resolvedor local; (4) **blindagem do plano de gestão** (dropbear/uhttpd só na vlan30, WPA3+PMF, WPS off). **Atenção (mantido da V14):** zonas com porta restrita **não** levam `config forwarding` para a WAN — a liberação é só por `config rule` de portas específicas.

## **Key Findings**

### **Decisão de hardware (Parte 1\)**

A restrição dominante é **logística**: comprar presencialmente em Brasília. Isso elimina RT3200/E8450 e Flint 2 (só importação). O **Xiaomi AX3000T** vence por cruzar (a) suporte OpenWrt oficial, (b) CPU ARM Cortex-A53 com hardware flow offloading capaz de NAT em gigabit, e (c) disponibilidade real no varejo brasileiro.
Os TP-Link Archer AX55/AX73 foram **rejeitados**: AX55 V1 e AX73 usam Qualcomm IPQ5018/IPQ0518 (sem OpenWrt estável); AX55 V2/V4 usa Broadcom (sem OpenWrt). Só o AX55 **Pro V2** usa MT7981B, mas tem suporte incipiente (WIP) e é raro no Brasil.

### **🆕 Risco de flash confirmado (Winbond) — verificado**

O AX3000T sai de fábrica com NAND **ESMT F50L1G41LB** ou **Winbond W25N01KV**. A camada NMBM do OpenWrt **não funcionava com o Winbond**, causando **softbrick** — e isso apareceu em **23.05, 24.10 e snapshot** do ramo oficial (issues openwrt #16002 e #16972). O patch chegou antes em **ImmortalWrt / X-WRT**. **Conclusão prática:** não confie que "24.10 já resolve"; **confirme no changelog/página do device** que a build trata o Winbond, tenha o **recovery TFTP montado antes de gravar**, e mantenha uma imagem **ImmortalWrt** como plano B se a sua unidade for Winbond.

### **Coração técnico (Parte 2\)**

* **Flash do AX3000T** exige obter SSH no firmware stock via `xmir-patcher` antes de gravar o OpenWrt. Documentado abaixo; E8450 (importado) como plano B usa só upload web do `.itb`.
* **WAN Vivo**: VLAN 10, PPPoE `cliente@cliente`/`cliente`, MTU 1492; Software/Hardware flow offloading obrigatório para 600 Mbps.
* **VLANs DSA**: criadas em `br-lan` via Bridge VLAN filtering; cada VLAN vira device `br-lan.20`, etc.; cada uma com interface lógica + zona de firewall.
* **Regra direcional 30→40**: `forwarding` 30→40 + zona IOT `forward REJECT`; retorno 40→30 é liberado por conntrack (stateful), sem forwarding 40→30.
* 🆕 **Regra IOT/GUEST para internet**: como a zona é `forward REJECT` e **não** há `config forwarding` para a WAN, a saída é liberada **só por `config rule ... target ACCEPT`** em portas específicas. Verificado: uma `config rule` com `src`/`dest` de zona atua na cadeia FORWARD e permite o tráfego mesmo com a política REJECT.

## **Details**

## **PARTE 1 — HARDWARE: PESQUISA DE CAMPO EM BRASÍLIA**

### **1A. Roteador principal (firewall all-in-one com OpenWrt)**

| Modelo | SoC | OpenWrt | NAT 600 Mbps | Presencial BSB? | Preço |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Xiaomi AX3000T** | MT7981B (2× ARM A53), Switch MT7531AE, 256 MB RAM, 128 MB NAND | **Oficial desde 23.05.4** | Sim, com flow offload | **Sim** — Kabum, Amazon, ML Full | R$ 335–370 |
| Belkin RT3200 / Linksys E8450 | MT7622BV + MT7915AN, 512 MB RAM | Oficial, excelente | Sim (~850 Mbps) | **Não** — importação | ~US$ 70–120 |
| GL.iNet Flint 2 (GL-MT6000) | MT7986A, 2.5GbE | Oficial + GL | Sim, folgado | **Não** — importação | ~R$ 900–1.300 |
| TP-Link Archer AX55 V1 / AX73 | Qualcomm IPQ5018/IPQ0518 | **Sem suporte estável** | — | Inútil p/ OpenWrt | — |

**Veredito — comprar: Xiaomi AX3000T (MT7981B).** Confirme no ato que é o AX3000T e não o "AX3000" com chip Qualcomm.
⚠️ **Risco Winbond (ver Key Findings):** unidades com **W25N01KV** podem dar softbrick; **recovery TFTP pronto + build que trata o Winbond (ou ImmortalWrt)** antes de gravar. **Plano B de hardware:** Belkin RT3200 / Linksys E8450.

### **1B. WAN — HGU Vivo em Bridge (principal) ou ONT standalone (opcional)**

🆕 **Principal:** manter a **HGU da Vivo em Modo Bridge**, Wi-Fi desligado, LAN1 → WAN do AX3000T. Zero custo extra, zero risco de OMCI.
**Opcional (Parte 2F):** **TP-Link XZ000-G3** — GPON 1 porta Gigabit, conector SC/APC (verde), alimentação 9 VDC, R$ 100–270. Alternativa VSOL V2802RH.

### **1C. Mini UPS DC**

**Marsriva KP3** (10.000 mAh, saídas 12V e 9V simultâneas). **Knup KP-TC44** bivolt — confirme 9V e 12V simultâneos fisicamente.

## **PARTE 2 — PROCEDIMENTOS TÉCNICOS**

### **2A. Flash do OpenWrt (Xiaomi AX3000T / MT7981B)**

1. **Preparação:**
   * 🔴 **Ambiente isolado:** PC **100% limpo** (Live USB Linux Ubuntu/Mint) com Python 3.x e Git. **NÃO** use um SO da rede possivelmente comprometido.
   * 🆕 **Recovery ANTES do flash:** PC com IP estático **192.168.31.100/24** + servidor TFTP servindo a imagem de recuperação. O U-Boot do AX3000T busca por TFTP ao ligar segurando o reset. **Monte e teste isso antes de gravar.**
   * Baixe do target mediatek/filogic (build estável que trate o Winbond, 24.10.x+; ImmortalWrt como plano B):
     * `...xiaomi_mi-router-ax3000t-initramfs-factory.ubi`
     * `...xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin`
   * **Reset de fábrica** (segure reset ~10 s ligado).
2. **Firmware stock:** IP 192.168.31.1. Complete o wizard e defina senha admin.
3. **Obter SSH com xmir-patcher:** clone o repo e rode `./run.sh` (ou `run.bat`); use a opção de obter token/criar acesso (extrai o stok e habilita SSH).
4. **Gravar OpenWrt (initramfs) + sysupgrade:** copie as imagens via scp para /tmp e grave pela CLI/patcher. Após o initramfs reiniciar, acesse LuCI em 192.168.1.1 e faça upload do sysupgrade.bin.
5. **Verificar:** IP volta a 192.168.1.1, LuCI mostra OpenWrt.

**Recuperação (brick):** já montada acima (TFTP/U-Boot, 192.168.31.100/24).

**Plano B — Linksys E8450 / Belkin RT3200 (MT7622):** acesso 192.168.1.1, upload web do instalador `.itb`, reinicie e aplique `sysupgrade.itb`.

### **2B. WAN (ordem correta)**

🆕 **Rota principal (HGU em bridge):** a HGU autentica GPON; o OpenWrt faz o PPPoE. Não precisa de clonagem de MAC na maioria dos casos.

* **Passo 1 — VLAN 10 na WAN (DSA):** Network → Interfaces → Devices → Add device. Type: VLAN (802.1q). Base device: `wan`. VLAN ID: 10. Cria `wan.10`.
* **Passo 2 — Interface PPPoE:** Add interface. Protocol: PPPoE. Device: `wan.10`. Usuário/Senha: `cliente@cliente`/`cliente`. MTU 1492. Firewall zone: `wan`.
* **Passo 3 — Flow offload:** Network → Firewall → General → habilite **Software** e **Hardware flow offloading**. (Obrigatório p/ 600 Mbps.)
* **Passo 4 — Testar.**
* **Passo 4-B — Override do MAC (SÓ se o PPPoE NÃO autenticar):** device `wan.10`, aba Advanced, cole o MAC da HGU Vivo.

### **2C. Segmentação por VLANs (DSA, OpenWrt 24.10)**

**Bridge VLANs:** Network → Interfaces → Devices → Configure `br-lan` → Bridge VLAN filtering. Atribua as portas untagged (`u*`).
🔴 **EVITE LOCKOUT:** as 4 portas LAN viram acesso das 4 VLANs — não sobra VLAN 1 de gestão. **Administre pela vlan30** e esteja na porta untagged dela antes de aplicar.

**/etc/config/network (trecho):**
```
config device
 option name 'br-lan'
 option type 'bridge'
 list ports 'lan1'
 list ports 'lan2'
 list ports 'lan3'
 list ports 'lan4'

config bridge-vlan
 option device 'br-lan'
 option vlan '20'
 list ports 'lan4:u*'   # WORK-DEV

config bridge-vlan
 option device 'br-lan'
 option vlan '30'
 list ports 'lan1:u*'   # HOME-MAIN (gestão)

config bridge-vlan
 option device 'br-lan'
 option vlan '40'
 list ports 'lan2:u*'   # HOME-IOT

config bridge-vlan
 option device 'br-lan'
 option vlan '50'
 list ports 'lan3:u*'   # GUEST-WIFI

# Interfaces lógicas vlan20/30/40/50 (IPs estáticos) + dnsmasq por interface
# WAN: wan.10 + interface pppoe
```

### **2D. Regras de Firewall (🆕 versão V16 — guest + DHCP/DNS + DNS forçado)**

**/etc/config/firewall (completo):**
```
# ---------- WORK-DEV (VLAN 20): só internet, zero lateral ----------
config zone
 option name 'work'
 list network 'vlan20'
 option input 'REJECT'
 option output 'ACCEPT'
 option forward 'REJECT'

config forwarding
 option src 'work'
 option dest 'wan'

# ---------- HOME-MAIN (VLAN 30): internet + inicia p/ IOT + gestão ----------
config zone
 option name 'home'
 list network 'vlan30'
 option input 'ACCEPT'      # gestão do roteador vem daqui
 option output 'ACCEPT'
 option forward 'REJECT'

config forwarding
 option src 'home'
 option dest 'wan'

config forwarding
 option src 'home'
 option dest 'iot'          # 30 -> 40 permitido (retorno via conntrack)

# ---------- HOME-IOT (VLAN 40): isolada, só portas de saída ----------
config zone
 option name 'iot'
 list network 'vlan40'
 option input 'REJECT'
 option output 'ACCEPT'
 option forward 'REJECT'

config rule
 option name 'iot-internet-limited'
 option src 'iot'
 option dest 'wan'
 option proto 'tcp udp'
 option dest_port '80 123 443 8883'
 option target 'ACCEPT'

# ---------- GUEST-WIFI (VLAN 50): 🆕 zona criada na V16 ----------
config zone
 option name 'guest'
 list network 'vlan50'
 option input 'REJECT'
 option output 'ACCEPT'
 option forward 'REJECT'

config rule
 option name 'guest-web-only'
 option src 'guest'
 option dest 'wan'
 option proto 'tcp udp'
 option dest_port '80 443'
 option target 'ACCEPT'

# ---------- 🆕 DHCP + DNS para o roteador (zonas com input REJECT) ----------
# Sem estas regras, work/iot/guest NÃO pegam IP nem resolvem nomes.
config rule
 option name 'allow-dhcp-restricted'
 list src 'work'
 list src 'iot'
 list src 'guest'
 option proto 'udp'
 option dest_port '67 68'
 option target 'ACCEPT'

config rule
 option name 'allow-dns-restricted'
 list src 'work'
 list src 'iot'
 list src 'guest'
 option proto 'tcp udp'
 option dest_port '53'
 option target 'ACCEPT'
```

### **2D-bis. 🆕 DNS forçado (redirect da porta 53 para o roteador)**

Intercepta qualquer cliente com DNS "chumbado" e o obriga a usar o resolvedor local. Aplique por zona (repita para work/home/iot/guest conforme desejado):
```
config redirect
 option name 'force-dns-iot'
 option src 'iot'
 option proto 'tcp udp'
 option src_dport '53'
 option dest_port '53'
 option target 'DNAT'
 # sem 'dest_ip' -> redireciona para o próprio roteador (resolvedor local)
```
Opcional: uma `config rule` com `dest_port '853' target 'REJECT'` para barrar DNS-over-TLS externo e evitar bypass do filtro. **Limite:** não impede DNS tunelado por porta não-padrão.

### **2E. mDNS Repeater (refletir só entre VLAN 30 e 40)**

`/etc/avahi/avahi-daemon.conf`:
```
[reflector]
enable-reflector=yes
[server]
allow-interfaces=br-lan.30,br-lan.40
```
Libere UDP 5353 (dest 224.0.0.251) entre as zonas home e iot. **Não** inclua br-lan.20 nem br-lan.50 no `allow-interfaces` (mantém trabalho e visitantes invisíveis).

### **2F. 🆕 Blindagem do plano de gestão (novo — corresponde ao Bloco 5.5)**

**dropbear (SSH) só na vlan30, sem senha, só chave —** `/etc/config/dropbear`:
```
config dropbear
 option PasswordAuth 'off'
 option RootPasswordAuth 'off'
 option Port '22'
 option Interface 'vlan30'
```
Suba a chave pública em `/etc/dropbear/authorized_keys` (ou LuCI → System → Administration → SSH-Keys).

**LuCI (uhttpd) só na vlan30 —** em `/etc/config/uhttpd`, ajuste `list listen_http`/`list listen_https` para o IP da interface vlan30 (não `0.0.0.0`). **Nunca** exponha LuCI na WAN.

**Wi-Fi (WPA3 + PMF, WPS off, isolamento no guest) —** em cada `config wifi-iface`:
```
option encryption 'sae'          # WPA3-SAE (ou 'sae-mixed' p/ compat.)
option ieee80211w '2'            # PMF obrigatório
option wps_pushbutton '0'        # WPS desligado
# no SSID de visitantes (vlan50):
option isolate '1'               # Client Isolation
```
Um SSID por VLAN, cada um com PSK forte e único (gerado no Bitwarden). **uPnP desligado.**

### **2G. ONT TP-Link XZ000-G3 (SÓ trilha avançada 3B)**

* Acesso 192.168.1.1. Insira **GPON SN** em hex (16 dígitos; 4 primeiras letras ASCII→HEX) + **SLID**. VLAN 10 modo TAG.
* **PON pisca eternamente / fake O5:** SN/SLID incorretos ou conversão hex errada — recolha os dados pela HGU (página /padrao ou status GPON) e refaça.
* 🟡 **Bloqueio OMCI:** central pode exigir assinatura Askey/MitraStar. **Solução = usar a rota principal (HGU em bridge, Parte 2B).**
* **Registra (O5) mas sem internet:** VLAN ou PPPoE errados no roteador.

## **PARTE 3 — LOJAS FÍSICAS EM BRASÍLIA**

Roteador e UPS presencial; ONT (se for a trilha avançada) online. Lojas: Kalunga, Netshop Informática, Glacon Informática, lojas de provedores (SIA/Taguatinga). Varejo de massa no ParkShopping, Conjunto Nacional. As **chaves FIDO2** geralmente saem melhor online (Amazon BR/importação).

## **Recommendations e Caveats**

* **Prioridade de segurança (verificada):** para atacante externo, o maior retorno está em **MFA por hardware (FIDO2)** + reinstalação limpa + higiene de contas — não na rede. A rede contém e amplifica, mas raramente é o vetor de recontágio numa casa.
* **WAN:** prefira a **HGU em bridge**; a troca por ONT não adiciona segurança e adiciona risco de OMCI.
* **Flash AX3000T:** confirme suporte ao Winbond e tenha recovery TFTP pronto **antes** de gravar; ImmortalWrt como plano B.
* **Firewall:** nomes de zona **não** devem começar com dígito (fw4/24.10 ignora zonas assim). Use `work/home/iot/guest` (como acima). Verifique nomes de device (`wan`, `lan1..lan4`) por build.
* **UEFI reflash:** só com evidência; não cobre ME/AMT; risco de brick. Secure Boot + senha de firmware são o mínimo mandatório.
* **DNS forçado:** mitiga a maioria dos casos de DNS malicioso, não 100% (túnel por porta não-padrão escapa).
