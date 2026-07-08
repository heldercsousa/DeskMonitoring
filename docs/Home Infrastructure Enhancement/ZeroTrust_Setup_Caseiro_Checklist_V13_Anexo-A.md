# Anexo Técnico V13-A — Rede Zero-Trust Residencial OpenWrt (Vivo Fibra 600 Mbps, Brasília/DF)

## TL;DR
- O **Xiaomi AX3000T (MT7981B / Filogic 820, ARM dual-core A53)** é a melhor compra presencial em Brasília: é o único roteador com suporte oficial OpenWrt e CPU ARM forte realmente disponível no varejo físico brasileiro (Kabum, Amazon BR, Mercado Livre Full), por ~R$ 335–370. O Belkin RT3200/Linksys E8450 e o GL.iNet Flint 2, embora superiores para flash, são praticamente só importação (eBay/AliExpress/Ubuy) e não devem ser comprados presencialmente no DF.
- ONT standalone recomendada: **TP-Link XZ000-G3** (conector **SC/APC**, R$ 100–270, amplamente disponível), com Mini UPS DC **Marsriva KP3** (R$ 200–280, saídas 9V/12V/5V simultâneas, comutação 0 ms). Ambos compráveis online com entrega rápida no DF; presencialmente o XZ000-G3 aparece em redes como Kalunga/Fujioka e lojas de redes/ISP.
- A arquitetura Zero-Trust se implementa com 4 VLANs (DSA bridge no OpenWrt 24.10) + zonas de firewall com forwarding stateful unidirecional 30→40, mDNS reflector restrito a VLANs 30/40, e WAN PPPoE em VLAN 10 (`cliente@cliente`/`cliente`, MTU 1492).

---

## Key Findings

### Decisão de hardware (Parte 1)
A restrição dominante do projeto não é técnica, é **logística**: comprar presencialmente em Brasília. Isso elimina os dois melhores candidatos de flash (RT3200/E8450 e Flint 2), que no Brasil só existem via importação. O **Xiaomi AX3000T** vence por ser o único cruzamento de (a) suporte OpenWrt oficial, (b) CPU ARM Cortex-A53 com hardware flow offloading capaz de NAT em gigabit, e (c) disponibilidade real no varejo brasileiro.

Os TP-Link Archer AX55/AX73 foram **rejeitados**: o AX55 V1 e o AX73 usam Qualcomm IPQ5018/IPQ0518, sem suporte OpenWrt estável; o AX55 V2/V4 usa Broadcom (sem OpenWrt). Só o AX55 **Pro V2** usa MT7981B, mas tem suporte incipiente (snapshot/WIP) e é raro no Brasil.

### Coração técnico (Parte 2)
- **Flash do AX3000T** é mais trabalhoso que o do E8450 (requer obter SSH no firmware stock via ferramenta `xmir-patcher` antes de gravar o OpenWrt). Documento o procedimento e também o do E8450 como alternativa "plano B" (importado), que usa apenas upload web do instalador `.itb`.
- **WAN Vivo**: VLAN 10, PPPoE `cliente@cliente`/`cliente`, MTU 1492; habilitar Software/Hardware flow offloading é obrigatório para chegar a 600 Mbps.
- **VLANs DSA**: criadas em `br-lan` via *Bridge VLAN filtering*; cada VLAN vira device `br-lan.20`, `br-lan.30`, etc.; cada uma recebe interface lógica + zona de firewall.
- **Regra direcional 30→40**: implementada com `forwarding` 30→40 + zona IOT com `forward REJECT`; o retorno 40→30 é permitido automaticamente por conntrack (stateful), sem precisar de forwarding 40→30.

---

## Details

## PARTE 1 — HARDWARE: PESQUISA DE CAMPO EM BRASÍLIA

### 1A. Roteador principal (firewall all-in-one com OpenWrt)

**Análise dos candidatos:**

| Modelo | SoC | OpenWrt | NAT 600 Mbps | Disponível presencialmente em BSB? | Preço |
|---|---|---|---|---|---|
| **Xiaomi AX3000T** | MediaTek MT7981B (2× ARM A53), Switch MT7531AE, 256 MB RAM, 128 MB NAND | **Oficial, suportado desde 23.05.4** (target mediatek/filogic, aarch64_cortex-a53) | Sim, com flow offload (gigabit) | **Sim** — Kabum, Amazon BR, ML Full; varejo nacional | R$ 335–370 |
| Belkin RT3200 / Linksys E8450 | MediaTek MT7622BV (2 cores @1.35 GHz) + MT7915AN/MT7975AN 4×4, 512 MB RAM, 128 MB flash | Oficial, excelente (HW flow offload) | Sim — ~850 Mbps de download medido com HW offload (~30% CPU) | **Não** — só importação (eBay) | ~US$ 70–120 import |
| GL.iNet Flint 2 (GL-MT6000) | MediaTek MT7986A (Filogic 830), 2.5GbE | Oficial + firmware GL | Sim, folgado | **Não** — Ubuy/AliExpress/Amazon import | ~R$ 900–1.300 import |
| TP-Link Archer AX55 V1 / AX73 | Qualcomm IPQ5018/IPQ0518 | **Sem suporte estável** | — | Sim, mas inútil p/ OpenWrt | — |
| TP-Link Archer AX55 Pro V2 | MediaTek MT7981B | Incipiente (snapshot/WIP) | Provável | Raro no BR | — |

> **Nota técnica MIPS:** a premissa do checklist está correta — roteadores MIPS (ex.: Archer C6, com MT7621 MIPS) ficam limitados por CPU em ~300–400 Mbps com NAT/firewall ativo. Todos os recomendados aqui usam **ARM Cortex-A53**, que com hardware flow offloading habilitado roteia em velocidade de linha gigabit com CPU quase ociosa. O E8450/RT3200 documentadamente **não** atinge gigabit no WAN sem flow offloading habilitado — esse é um ajuste obrigatório, não opcional.

**Veredito — comprar:** **Xiaomi AX3000T (versão RD23, MT7981B).** Confirme no ato que é o modelo **AX3000T** (RD03/RD23) e **não** o "RD03V2"/AX3000 com chip Qualcomm IPQ5018, que não tem suporte OpenWrt. O SoC correto é **MediaTek MT7981B** (2× A53), com switch MediaTek MT7531AE, 256 MB de RAM e 128 MB de flash NAND, 4 portas Gigabit.

> ⚠️ **Risco de hardware em unidades recentes:** segundo a documentação técnica da comunidade (specs UART no fórum OpenWrt e issue #16002 no GitHub), o AX3000T sai de fábrica com flash NAND **ESMT F50L1G41LB** *ou* **Winbond W25N01KV**; unidades com a variante Winbond **W25N01KV** podem sofrer *softbrick* com builds OpenWrt que não tratam esse chip. Use uma build OpenWrt recente (24.10.x ou superior) que já corrige isso e tenha o procedimento de recovery preparado **antes** de iniciar o flash.

**Plano B (se quiser o flash mais simples e aceitar importar):** Belkin RT3200 ou Linksys E8450 — hardware idêntico (MT7622BV, 512 MB RAM). Não há varejo físico em Brasília; via eBay/importação.

### 1B. ONT Standalone

**TP-Link XZ000-G3** — terminal GPON de 1 porta Gigabit. Especificações oficiais: compatível com o padrão **ITU-T G.984 GPON**, **downstream até 2.488 Gbps / upstream até 1.244 Gbps**; **1× porta RJ45 10/100/1000 Mbps + 1× porta SC/APC**; óptica Classe B+ (Tx 1310 nm / Rx 1490 nm); alcance 0–20 km; criptografia AES; alimentação **9 VDC / 0,6 A**. É a ONT mais usada na comunidade brasileira para substituir a HGU da Vivo. Disponível em Kabum, Amazon BR, Magazine Luiza, Fujioka e Mercado Livre, faixa **R$ 100–270** (mediana ~R$ 130–180; no Magazine Luiza foi visto a partir de R$ 100,71 no Pix).

- **Conector de fibra:** o XZ000-G3 usa conector **SC/APC** (verde) — confirmado nas fichas técnicas oficiais (Anatel) e padrão da Vivo GPON. Confirme que a sua fibra termina em SC/APC e ela encaixa direto.
- **Alimentação 9 VDC:** importante para casar com o Mini UPS DC (saída 9V do Marsriva KP3 atende a ONT diretamente).
- **Alternativa:** **VSOL V2802RH** — tem porta Ethernet de **2.5 Gbps** (vantagem para planos >1 Gbps), bem relatada na comunidade; geralmente importada do Paraguai ou via ML. Para o plano de 600 Mbps a porta gigabit do XZ000-G3 é mais que suficiente.

**Onde comprar fisicamente em Brasília:** lojas de redes/telecom e ISP (ver Parte 3); o XZ000-G3 raramente está em prateleira de Americanas/Casas Bahia — o caminho mais confiável é Kabum/Amazon com entrega no DF, ou lojas especializadas em equipamentos para provedores.

### 1C. Mini UPS DC

**Marsriva KP3** — mini nobreak DC. Ficha técnica oficial: bateria **10.000 mAh (2×5.000 mAh) / 3,7 V / 37 Wh**; **entrada DC 12V/2,0A**; **saídas: DC 12V/1,5A + DC 9V/2,0A + DC 5V/2,0A + USB 5V/2,0A** (todas simultâneas); **18 W máximos**; **comutação 0 ms** (não é inversor AC); dimensões 115×83×27 mm; ~278 g. Atende exatamente o requisito de alimentar ONT (9V/12V) e roteador (12V) simultaneamente. Preço **R$ 200–280**. Disponível em Kabum, Mercado Livre, Magazine Luiza, Carrefour, MadeiraMadeira.
- Variante **KP3 Pro** (36 W / 8.400 mAh) recomendada se ONT + roteador + AP somarem perto de 18 W — relato de usuário: segurou roteador Vivo + Deco por ~2h44.

**Knup KP-TC44** — mini nobreak DC bivolt (100–240 V), bateria ~10.400 mAh, saídas **5V/9V/12V DC selecionáveis + POE 15V/24V + USB**, 18 W; acompanha cabo Y (2 saídas P4). Preço **~R$ 150–170**. Disponível na Shopee, Mercado Livre, OLX, Kabum.
- **Atenção:** nas fichas do KP-TC44 as saídas DC aparecem como **selecionáveis** (5/9/12V) — confirme no ato que há duas saídas P4 independentes (via cabo Y) capazes de entregar 9V **e** 12V ao mesmo tempo. O **Marsriva KP3 é mais garantido** para 9V **e** 12V simultâneos por ter saídas físicas dedicadas para cada tensão.

**Fallback Mercado Livre com retirada em Brasília:** ambos os modelos têm vendedores com "Mercado Envios Full" e/ou "retirar com o vendedor" no DF; filtrar por localização "Distrito Federal" na busca.

---

## PARTE 2 — PROCEDIMENTOS TÉCNICOS

> Procedimentos documentados para o **Xiaomi AX3000T (MT7981B)** como opção principal e **Linksys E8450/Belkin RT3200** como alternativa.

### 2A. Flash do OpenWrt

**factory.bin vs sysupgrade.bin — regra geral:**
- **factory** (`*-initramfs-factory.ubi` / `*-factory.bin`): imagem para sair do firmware **de fábrica** para o OpenWrt na primeira vez. No MT7981B é uma imagem **UBI/initramfs** que roda na RAM.
- **sysupgrade** (`*-squashfs-sysupgrade.bin`): imagem para gravar permanentemente na flash **quando já se está no OpenWrt** (seja initramfs, seja uma versão antiga). É também a imagem de atualização entre versões.
- Sequência típica no AX3000T: gravar/inicializar o **initramfs (factory)** → entrar no OpenWrt rodando na RAM → fazer **sysupgrade** com a imagem squashfs para instalação permanente.

#### Procedimento AX3000T (MT7981B)

O AX3000T **não aceita upload direto de .bin pela web do firmware stock**. É preciso primeiro obter acesso SSH ao firmware Xiaomi usando a ferramenta open-source **`xmir-patcher`** (repositório `openwrt-xiaomi/xmir-patcher` no GitHub).

1. **Preparação:**
   - PC com Python 3.x e Git instalados.
   - Baixe as imagens OpenWrt do target `mediatek/filogic` (use uma versão estável recente, 24.10.x ou superior, pela correção do chip Winbond):
     - `openwrt-24.10.x-mediatek-filogic-xiaomi_mi-router-ax3000t-initramfs-factory.ubi`
     - `openwrt-24.10.x-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin`
   - Faça **reset de fábrica** no roteador (segure o botão reset ~10 s com o aparelho ligado).

2. **Acesso ao firmware stock:**
   - IP padrão do AX3000T: **`192.168.31.1`**. Conecte o PC numa porta LAN, acesse `http://192.168.31.1`, complete o wizard e defina uma senha de administrador.

3. **Obter SSH com xmir-patcher:**
   - Clone o repositório e rode o `run.bat` (Windows) ou `./run.sh` (Linux).
   - No menu, use a opção de **obter token/criar acesso** (a ferramenta extrai o `stok` da sessão web e habilita SSH/telnet). Defina senha root quando solicitado.
   - Resultado: você terá `ssh root@192.168.31.1` funcional no firmware Xiaomi.

4. **Gravar o OpenWrt (initramfs) e fazer sysupgrade:**
   - O fluxo recomendado pela ferramenta é usar a própria opção de **flash do firmware** do xmir-patcher para gravar o `initramfs-factory.ubi`, **ou** copiar as imagens via `scp` para `/tmp` e gravar pela CLI. Após gravar o initramfs e reiniciar, o roteador sobe o **OpenWrt em modo initramfs** (LuCI em `http://192.168.1.1`).
   - Em seguida, em LuCI **System → Backup / Flash Firmware → Flash image**, faça upload do `*-squashfs-sysupgrade.bin` (desmarque "keep settings" na primeira instalação). O aparelho grava e reinicia com OpenWrt permanente.

5. **Verificar OpenWrt ativo:** após o flash o IP volta para **`192.168.1.1`**; LuCI deve mostrar "OpenWrt 24.10" no rodapé e o `System → Overview` deve identificar o modelo "Xiaomi Mi Router AX3000T" com 2 rádios MediaTek.

**Comportamento esperado durante o flash:** o LED da frente pisca/troca de cor; aguarde ~2–3 min sem desligar; o aparelho reinicia sozinho. Não interrompa energia (use o UPS DC já durante o flash, opcional mas recomendado).

**Recuperação (brick) — TFTP/U-Boot do AX3000T:**
- Materiais: cabo Ethernet, PC com cliente/servidor TFTP, fonte do roteador.
- O AX3000T tem **recovery via U-Boot por TFTP**. Configure o PC com IP estático **`192.168.31.100`**/24. Suba um servidor TFTP servindo a imagem de recuperação. Ligue o aparelho segurando o **botão reset**; o U-Boot busca a imagem por TFTP no IP `192.168.31.1`. (O nome de arquivo exato esperado varia por versão de U-Boot; consultar a página do dispositivo no wiki OpenWrt no momento do procedimento.)
- Em caso de falha, há recuperação via **console serial UART** (pads na placa) que sempre funciona — método de último recurso.

#### Procedimento alternativo — Linksys E8450 / Belkin RT3200 (MT7622)

Mais simples (só upload web), por isso documentado como referência:

1. PC com IP estático **`192.168.1.254`**/24 (sem gateway/DNS), conectado a uma porta LAN.
2. Acesse `http://192.168.1.1`, aborte o wizard, faça login (senha stock `admin`).
3. Em **System → Backup/Flash firmware**, faça upload do instalador:
   - se firmware stock **< 1.2.00.273012**: `openwrt-...-linksys_e8450-ubi-initramfs-recovery-installer.itb`
   - se **≥ 1.2.00.273012**: a versão `..._signed.itb`.
4. Aguarde ~1 min; sobe a **imagem de recuperação OpenWrt**. Em **System → Backup/Flash Firmware**, faça upload do `openwrt-...-linksys_e8450-ubi-squashfs-sysupgrade.itb`. Reinicia em OpenWrt.
   - ⚠️ O instalador troca o bootloader (TF-A + U-Boot) e converte o layout para UBI; **execute o instalador só uma vez**. Atualizações futuras usam o sysupgrade normal.
5. **Recuperação:** segure **reset** ao ligar até o LED ficar âmbar/amarelo → modo recovery web em `192.168.1.1`. TFTP só é necessário em casos de bad block, via console serial.

### 2B. Configuração da WAN (ordem correta)

**Ordem obrigatória:** (1) criar o device VLAN 10 na WAN → (2) override MAC → (3) PPPoE.

**Passo 1 — VLAN 10 na interface WAN (modelo DSA):**
No DSA não se usa a aba "Switch". Vá em **Network → Interfaces → aba Devices → Add device configuration**:
- **Type:** `VLAN (802.1q)`
- **Base device:** o device físico WAN (no AX3000T tipicamente `wan`, que mapeia para a porta WAN; em alguns builds a porta WAN é uma das `lanX` do switch — verifique em Devices).
- **VLAN ID:** `10`
- Isso cria o device **`wan.10`** (nomenclatura DSA: `<base>.<vid>`). Save.

**Passo 2 — Override do MAC address:**
Ainda em **Network → Interfaces → Devices**, clique **Configure...** no device `wan.10` (ou no device base) → aba **Advanced Settings → "MAC address"**. Cole o MAC clonado da HGU da Vivo se a sua instalação exigir clonagem (a maioria não exige, mas se a autenticação falhar, clone o MAC do roteador Vivo original).
- **Formato:** seis octetos hexadecimais separados por dois-pontos, ex.: `AA:BB:CC:DD:EE:FF`.

**Passo 3 — Interface PPPoE:**
**Network → Interfaces → Add new interface**:
- **Name:** `wan`
- **Protocol:** `PPPoE`
- **Device:** `wan.10`
- **PAP/CHAP username:** `cliente@cliente`
- **PAP/CHAP password:** `cliente`
- Em **Advanced Settings → Use default gateway** = marcado; **MTU = 1492**.
- Firewall zone: **wan**.

**Confirmar WAN ativa:** em **Network → Interfaces**, a interface `wan` mostra status **"Connected"** (RX/TX), um IPv4 público e uptime crescente. Em **Status → System Log** aparece `pppd ... local IP address` / `remote IP address`.

> **Crítico para 600 Mbps:** vá em **Network → Firewall → General Settings** e habilite **Software flow offloading** (e **Hardware flow offloading**, suportado no MT7981B e MT7622). Sem offload, a CPU satura e o PPPoE não passa de ~60–100 Mbps; com offload, atinge a banda contratada. (Relato real: usuário Vivo Fibra travava em 60 Mbps até habilitar Software flow offloading, então atingiu a banda plena.)

### 2C. Segmentação por VLANs (DSA, OpenWrt 24.10)

**Esquema de endereçamento (VLAN ID alinhado ao 3º octeto):**
| VLAN | Nome | Rede | Gateway |
|---|---|---|---|
| 20 | WORK-DEV | 192.168.20.0/24 | 192.168.20.1 |
| 30 | HOME-MAIN | 192.168.30.0/24 | 192.168.30.1 |
| 40 | HOME-IOT | 192.168.40.0/24 | 192.168.40.1 |
| 50 | GUEST-WIFI | 192.168.50.0/24 | 192.168.50.1 |

**Passo 1 — Criar as Bridge VLANs:**
**Network → Interfaces → aba Devices → Configure... no `br-lan`** → aba **Bridge VLAN filtering**:
1. Marque **Enable VLAN filtering**.
2. Clique **Add** para cada VLAN (20, 30, 40, 50) e mantenha a VLAN 1 como nativa de gestão.
3. Para cada coluna de porta física (`lan1..lan4`) e para a porta CPU, defina por VLAN: **untagged** (u) na porta de acesso daquela VLAN, **tagged** (t) no uplink/trunk, ou **not member**. Marque a VLAN de gestão como **Primary VID (PVID) + untagged** na porta pela qual você administra, para não se trancar para fora.
   - Ex.: se quiser a porta `lan4` dedicada a equipamentos WORK-DEV → VLAN 20 untagged em `lan4`, demais VLANs "not member" em `lan4`.

Isso gera automaticamente os devices **`br-lan.20`, `br-lan.30`, `br-lan.40`, `br-lan.50`**.

> Cuidado conhecido do LuCI: ao adicionar a primeira VLAN ao bridge, o `vlan_filtering` é alternado automaticamente; aplique as mudanças com acesso garantido pela porta/VLAN de gestão e, se algo travar, use `uci revert network && /etc/init.d/network restart` por SSH ou o failsafe.

**Passo 2 — Criar as interfaces lógicas:**
Para cada VLAN, **Network → Interfaces → Add new interface**:
- **Name:** `vlan20` (e assim por diante)
- **Protocol:** `Static address`
- **Device:** `br-lan.20`
- **IPv4 address:** `192.168.20.1`, **netmask** `255.255.255.0`
- Aba **DHCP Server → Setup DHCP Server** (Save).
- Aba **Firewall Settings → create/assign zone** (ver 2D).

**Passo 3 — SSIDs Wi-Fi por VLAN:**
**Network → Wireless → Add** (em cada rádio). Para cada SSID:
- **Mode:** Access Point
- **ESSID:** ex. `HOME-MAIN`, `HOME-IOT`, `GUEST-WIFI`
- Aba **Network:** selecione a interface lógica correspondente (`vlan30`, `vlan40`, `vlan50`).
- Cada associação SSID↔interface faz o `wifi-iface` herdar a VLAN via a bridge. (WORK-DEV pode ser só cabeada ou ter SSID próprio em `vlan20`.)
- Para a rede de visitantes, marque **Isolate Clients** no SSID GUEST-WIFI.

**Conteúdo completo de `/etc/config/network`:**
```
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'fdARBITRARY::/48'

# ---- Bridge físico com VLAN filtering (DSA) ----
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
	list ports 'lan4:u*'        # porta de acesso WORK-DEV (untagged + PVID)

config bridge-vlan
	option device 'br-lan'
	option vlan '30'
	list ports 'lan1:u*'        # porta de acesso HOME-MAIN

config bridge-vlan
	option device 'br-lan'
	option vlan '40'
	list ports 'lan2:u*'        # porta de acesso HOME-IOT

config bridge-vlan
	option device 'br-lan'
	option vlan '50'
	list ports 'lan3:u*'        # porta de acesso GUEST-WIFI

# ---- Interfaces lógicas por VLAN ----
config interface 'vlan20'
	option proto 'static'
	option device 'br-lan.20'
	option ipaddr '192.168.20.1'
	option netmask '255.255.255.0'

config interface 'vlan30'
	option proto 'static'
	option device 'br-lan.30'
	option ipaddr '192.168.30.1'
	option netmask '255.255.255.0'

config interface 'vlan40'
	option proto 'static'
	option device 'br-lan.40'
	option ipaddr '192.168.40.1'
	option netmask '255.255.255.0'

config interface 'vlan50'
	option proto 'static'
	option device 'br-lan.50'
	option ipaddr '192.168.50.1'
	option netmask '255.255.255.0'

# ---- WAN: VLAN 10 + PPPoE Vivo ----
config device
	option name 'wan.10'
	option type '8021q'
	option ifname 'wan'
	option vid '10'

config interface 'wan'
	option proto 'pppoe'
	option device 'wan.10'
	option username 'cliente@cliente'
	option password 'cliente'
	option ipv6 'auto'
	option mtu '1492'

config interface 'wan6'
	option proto 'dhcpv6'
	option device 'wan.10'
	option reqaddress 'try'
	option reqprefix 'auto'
```
> Ajuste a atribuição de portas (`lan1..lan4`) conforme seu uso físico. O sufixo `:u*` = untagged + PVID; `:t` = tagged (trunk para um switch/AP gerenciável).

**Bloco `/etc/config/dhcp` (pools por VLAN):**
```
config dhcp 'vlan20'
	option interface 'vlan20'
	option start '100'
	option limit '150'
	option leasetime '12h'

config dhcp 'vlan30'
	option interface 'vlan30'
	option start '100'
	option limit '150'
	option leasetime '12h'

config dhcp 'vlan40'
	option interface 'vlan40'
	option start '100'
	option limit '150'
	option leasetime '12h'

config dhcp 'vlan50'
	option interface 'vlan50'
	option start '100'
	option limit '150'
	option leasetime '4h'
```

### 2D. Regras de Firewall

**Modelo Zero-Trust desejado:**
- **WORK-DEV (20):** sem tráfego lateral (input/forward REJECT entre zonas); só internet.
- **HOME-MAIN (30):** internet livre; pode iniciar conexão para HOME-IOT (30→40), mas IOT não inicia para HOME-MAIN.
- **HOME-IOT (40):** isolada de 20 e 30; internet só nas portas necessárias.
- **GUEST-WIFI (50):** só portas 80/443 para internet; client isolation.

**Via LuCI (Network → Firewall → Zones → Add):** crie zonas `work`, `home`, `iot`, `guest`, cada uma com **Input/Output/Forward = REJECT** por padrão, cobrindo sua rede (`vlan20`...`vlan50`). Em seguida, na seção **Inter-Zone Forwardings** de cada zona, adicione apenas os forwardings permitidos (abaixo). O acesso à internet de cada zona é um forwarding zona→`wan`.

**Conceito da regra stateful 30→40 (sim) mas 40→30 (não):**
No fw3/fw4 do OpenWrt, **`config forwarding` é unidirecional** e o tráfego de **retorno** de uma conexão estabelecida é liberado automaticamente pelo conntrack. Logo:
- Criar `forwarding src=home dest=iot` → permite HOME-MAIN **iniciar** conexões para IOT, e as respostas voltam (ESTABLISHED/RELATED) sem nenhuma regra extra.
- **Não** criar `forwarding src=iot dest=home` → IOT não consegue **iniciar** nada para HOME-MAIN. Isso é exatamente o comportamento direcional stateful pedido.

**Conteúdo completo de `/etc/config/firewall`:**
```
config defaults
	option syn_flood '1'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option flow_offloading '1'
	option flow_offloading_hw '1'

# ---- WAN ----
config zone
	option name 'wan'
	list network 'wan'
	list network 'wan6'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option masq '1'
	option mtu_fix '1'

# ---- WORK-DEV (VLAN 20): só internet, zero lateral ----
config zone
	option name 'work'
	list network 'vlan20'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'

config forwarding
	option src 'work'
	option dest 'wan'

# regras mínimas p/ a própria rede funcionar (DHCP+DNS no router)
config rule
	option name 'work-dhcp-dns'
	option src 'work'
	option dest_port '53 67 68'
	option proto 'tcp udp'
	option target 'ACCEPT'

# ---- HOME-MAIN (VLAN 30): internet + inicia p/ IOT ----
config zone
	option name 'home'
	list network 'vlan30'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'REJECT'

config forwarding
	option src 'home'
	option dest 'wan'

config forwarding
	option src 'home'
	option dest 'iot'          # 30 -> 40 permitido (retorno via conntrack)

# ---- HOME-IOT (VLAN 40): isolada; internet só nas portas necessárias ----
config zone
	option name 'iot'
	list network 'vlan40'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'

# IOT só fala com a internet (sem forwarding p/ home/work)
config forwarding
	option src 'iot'
	option dest 'wan'

# DHCP/DNS do router para IOT
config rule
	option name 'iot-dhcp-dns'
	option src 'iot'
	option dest_port '53 67 68'
	option proto 'tcp udp'
	option target 'ACCEPT'

# Restringir saída IOT às portas necessárias (Tapo C100 / Smart TV):
# 80/443 (HTTP/S), 123 (NTP), 53 (DNS), 8883 (MQTT/cloud Tapo)
config rule
	option name 'iot-internet-limited'
	option src 'iot'
	option dest 'wan'
	option proto 'tcp udp'
	option dest_port '53 80 123 443 8883'
	option target 'ACCEPT'

config rule
	option name 'iot-block-rest'
	option src 'iot'
	option dest 'wan'
	option proto 'all'
	option target 'REJECT'

# ---- GUEST-WIFI (VLAN 50): só 80/443, client isolation ----
config zone
	option name 'guest'
	list network 'vlan50'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'

config rule
	option name 'guest-dhcp-dns'
	option src 'guest'
	option dest_port '53 67 68'
	option proto 'tcp udp'
	option target 'ACCEPT'

config rule
	option name 'guest-web-only'
	option src 'guest'
	option dest 'wan'
	option proto 'tcp'
	option dest_port '80 443'
	option target 'ACCEPT'

config forwarding
	option src 'guest'
	option dest 'wan'
```
> A ordem importa: as regras `ACCEPT` específicas para IOT/GUEST vêm **antes** das `REJECT` genéricas; o forwarding `iot→wan` combinado com a regra `iot-internet-limited` + `iot-block-rest` confina o IOT às portas necessárias. *Client isolation* da rede guest é configurada no SSID (Wireless → Isolate Clients), pois o firewall por zona não isola hosts dentro da mesma VLAN.

### 2E. mDNS Repeater (refletir só entre VLAN 30 e 40)

**Opção 1 — avahi-daemon:**
```
opkg update
opkg install avahi-daemon
```
> Em builds recentes o pacote pode se chamar `avahi-dbus-daemon` ou `avahi-nodbus-daemon` — se `avahi-daemon` não existir, instale `avahi-dbus-daemon` (funciona normalmente em OpenWrt 24.10).

`/etc/avahi/avahi-daemon.conf`:
```
[server]
use-ipv4=yes
use-ipv6=no
allow-interfaces=br-lan.30,br-lan.40
deny-interfaces=br-lan.20,br-lan.50,wan,wan.10
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=no

[publish]
publish-hinfo=no
publish-workstation=no
disable-publishing=yes

[reflector]
enable-reflector=yes
reflect-ipv=no
```
Iniciar/habilitar:
```
/etc/init.d/avahi-daemon enable
/etc/init.d/avahi-daemon start
```
Também é preciso liberar mDNS no firewall **apenas** entre home(30) e iot(40):
```
config rule
	option name 'mDNS-home-to-iot'
	option src 'home'
	option dest 'iot'
	option proto 'udp'
	option dest_port '5353'
	list dest_ip '224.0.0.251'
	option target 'ACCEPT'

config rule
	option name 'mDNS-iot-to-home'
	option src 'iot'
	option dest 'home'
	option proto 'udp'
	option dest_port '5353'
	list dest_ip '224.0.0.251'
	option target 'ACCEPT'

config rule
	option name 'mDNS-input'
	option src '*'
	option dest_port '5353'
	option proto 'udp'
	list dest_ip '224.0.0.251'
	option target 'ACCEPT'
```
> O `allow-interfaces` restrito a `br-lan.30,br-lan.40` garante que o reflector **não** propaga mDNS para WORK-DEV (20) nem GUEST (50). A descoberta funciona nos dois sentidos 30↔40 (necessário para Chromecast/Cast responder), mas o firewall stateful continua bloqueando o tráfego unicast 40→30 não solicitado.

**Opção 2 — umdns (nativo OpenWrt):**
```
opkg update
opkg install umdns
```
`/etc/config/umdns`:
```
config umdns 'config'
	option jail '1'
	list network 'vlan30'
	list network 'vlan40'
```
Reiniciar:
```
/etc/init.d/umdns enable
/etc/init.d/umdns restart
```
> `umdns` só refletirá entre as redes listadas (`vlan30`, `vlan40`); VLAN 20 e 50 ficam fora. O `umdns` é mais leve, mas o `avahi` em modo reflector tem reflexão mais robusta para AirPlay/Chromecast.

**Verificação (VLAN 20 invisível ao mDNS):**
- De um host na VLAN 30: `avahi-browse -art` (ou `avahi-browse -rt _googlecast._tcp`) deve listar dispositivos da VLAN 40, **mas nenhum** da VLAN 20.
- De um host na VLAN 20: `avahi-browse -art` **não** deve enxergar nada das VLANs 30/40.
- No router: `logread | grep avahi` mostra as interfaces que o daemon registrou — deve listar só `br-lan.30` e `br-lan.40`.
- Captura: `tcpdump -ni br-lan.20 udp port 5353` enquanto há tráfego Cast nas outras VLANs → não deve aparecer pacote refletido.

### 2F. Configuração da ONT TP-Link XZ000-G3

- **Acesso:** IP padrão **`192.168.1.1`** (atenção: conflita com o LAN padrão do OpenWrt — configure a ONT antes de plugá-la na rede, ou mude temporariamente o IP do PC para `192.168.1.x`). Credenciais padrão **admin/admin**.
- **Passos GPON SN + SLID (rede Vivo):**
  1. Em **GPON Settings / WAN**, localize os campos **GPON SN** e **Senha GPON (PLOAM password)**.
  2. **GPON SN:** deve ser inserido em **hexadecimal, 16 dígitos**. O SN da HGU Vivo tem o formato 4 letras (fabricante) + 8 hex. Converta as **4 primeiras letras** (ex. "ALCL", "MSTC", "TLCM") para ASCII→HEX e concatene com os 8 dígitos hex restantes. Ex.: "TLCM" → `544C434D` + 8 dígitos = 16 hex. (Dica: o **XZ000-G7** aceita SN em ASCII+HEX sem conversão; se você optar por ele, esse passo fica mais simples.)
  3. **SLID / Senha GPON:** insira o **SLID** (10 dígitos) que aparece no modem Vivo original, no campo de senha GPON (formato ASCII).
  4. **VLAN:** modo **TAG**, **VLAN VID = 10**, prioridade **0** (Vivo separa internet=VLAN10).
  5. Salve e reinicie a ONT. O PPPoE **não** é feito na ONT (ela opera como bridge/media converter) — é feito no OpenWrt (seção 2B).
- **LEDs:**
  - **PON** piscando (verde) = tentando registrar / não autenticado na OLT (estado O1–O4 ou "fake O5").
  - **PON** **fixo/sólido** = registrado na OLT (estado O5, autenticado) — objetivo.
  - **LOS** vermelho/piscando = sem sinal óptico (fibra desconectada/suja ou potência baixa).
  - **LAN** = link Ethernet com o roteador.
- **Problemas comuns e soluções:**
  - *PON pisca eternamente / "fake O5":* SN ou SLID incorretos, ou conversão hex errada. Recolha o SN/SLID corretos pela interface da HGU Vivo (página `/padrao` ou tela de status GPON) e refaça a conversão.
  - *Registra (O5) mas sem internet:* VLAN errada (confirme VID 10 para internet na sua região; em SP é dsl.telesp/VIVO1) ou PPPoE mal configurado no roteador.
  - *Conector não encaixa:* a Vivo usa SC/APC (verde); não force conector SC/UPC (azul).
  - *Potência óptica:* compare o Rx power (dBm) da ONT com o da HGU original; valores muito diferentes indicam problema de conexão/limpeza da fibra.

---

## PARTE 3 — LOJAS FÍSICAS EM BRASÍLIA

> Estratégia recomendada: **roteador e UPS** podem ser comprados presencialmente; a **ONT GPON** é mais facilmente obtida online (Kabum/Amazon) com entrega rápida no DF, pois é item de nicho ISP.

**Lojas de informática / redes:**
- **Kalunga** — SCN Quadra 6, Conj. A, Ed. Venâncio 3000 (Asa Norte) e outras unidades; tem roteadores, alguns itens de rede e às vezes ONTs/terminais GPON.
- **Netshop Informática** — CLN 208 Norte, Bloco B (Asa Norte), com unidades em Águas Claras (Vitrini Shopping) e Arena; loja de informática/PC gamer com seção de redes.
- **Glacon Informática** — loja física em Brasília (desde 2002), com seção de **Redes → Roteadores/Switch**.
- **Shopping da Informática DF / Arroba Informática** — CLN 207, Bloco B, Lojas 16/18 (Asa Norte) — polo de lojas de informática.
- **Tech Masters** — ParkShopping (acessórios e informática).
- **Lojas de equipamentos para provedores (ISP)** — buscar no **SIA** e no comércio de **Taguatinga** lojas de "fibra óptica/CFTV/redes"; são o caminho mais provável para **ONT XZ000-G3/VSOL** e mini-UPS DC em estoque físico.

**Varejo de massa (estoque de produtos de rede — sobretudo roteadores TP-Link/Mercusys/Intelbras; menos provável ter AX3000T ou ONT GPON):**
- **Magazine Luiza, Casas Bahia, Americanas, Carrefour, Fast Shop** — unidades no ParkShopping, Conjunto Nacional, Shopping Brasília, Taguatinga Shopping, JK Shopping. Bom para mini-UPS e roteadores comuns; confira estoque online "retire na loja" antes de ir.

**Shoppings com concentração de lojas de eletrônicos:** ParkShopping (SAI/SMAS), Conjunto Nacional (Asa Norte, primeiro shopping de Brasília), Shopping Brasília, Taguatinga Shopping.

**Fallback online com entrega/retirada rápida no DF:** Kabum, Amazon BR, Mercado Livre (filtro "Distrito Federal" + "Full"/"retirar com vendedor"). É o caminho mais confiável para garantir o **AX3000T (RD23/MT7981B)**, a **ONT XZ000-G3** e o **Marsriva KP3/Knup KP-TC44** com modelo/revisão corretos.

---

## Recommendations

1. **Compre primeiro o roteador certo.** Vá atrás do **Xiaomi AX3000T versão RD23 (MT7981B)**. Confirme o chip MediaTek na embalagem/etiqueta — recuse qualquer "AX3000"/"RD03V2" Qualcomm. Se a loja física não tiver o RD23, use Kabum/Amazon/ML com retirada no DF (~R$ 335–370). Só considere importar RT3200/E8450 se quiser o flash mais simples e tiver paciência com prazo de importação.
2. **ONT + UPS juntos.** Garanta XZ000-G3 (SC/APC, alimentação 9 VDC) e Marsriva KP3; tenha em mãos o **SN GPON e o SLID** da HGU Vivo **antes** de devolver/desligar o equipamento da operadora (anote pela interface da HGU).
3. **Sequência de implantação:** (a) flash OpenWrt e atualização para 24.10 estável; (b) habilitar flow offloading; (c) WAN VLAN10/PPPoE e validar 600 Mbps; (d) criar VLANs/DHCP; (e) zonas de firewall; (f) mDNS reflector; (g) configurar ONT e migrar a fibra.
4. **Teste de aceitação (benchmarks que mudam a decisão):**
   - NAT/PPPoE deve sustentar **≥ 580 Mbps** down em speedtest com offload ligado. Se ficar em ~100 Mbps → offload desabilitado ou MTU errado.
   - `avahi-browse` na VLAN 20 deve retornar **vazio** para serviços das VLANs 30/40.
   - Host na VLAN 40 **não** deve conseguir abrir conexão (ssh/http) a um host na VLAN 30; host na 30 **deve** conseguir na 40.
   - Host na VLAN 50 só navega web (80/443); bloquear ping a gateways de outras VLANs.
5. **Quando reconsiderar o hardware:** se a Vivo migrar você para um plano **> 1 Gbps**, troque a ONT para **VSOL V2802RH (porta 2.5G)** e considere o **GL.iNet Flint 2 (2.5GbE)** — aí o custo de importação se justifica.

## Caveats
- **Disponibilidade e preços (2025/2026)** do varejo brasileiro oscilam muito (câmbio, impostos de importação, Black Friday). As faixas citadas são indicativas; confirme no ato.
- **Risco de flash do AX3000T:** unidades com flash Winbond W25N01KV podem dar softbrick com builds inadequadas; o procedimento via `xmir-patcher` evolui com as versões de firmware Xiaomi (nomes de arquivo, comandos e método do `stok` mudam). Consulte a página do dispositivo no wiki OpenWrt e o repositório `xmir-patcher` imediatamente antes de executar, e tenha o recovery (TFTP/serial) pronto. O risco de brick é real.
- A **VLAN da Vivo** é VID 10 para internet na maioria das regiões (confirmado para SP/telesp e relatos gerais); algumas localidades/OLTs podem divergir. Se o PPPoE não autenticar com tudo correto, verifique a VID real na HGU original e a necessidade de clonar MAC.
- Os **nomes de device** (`wan`, `lan1..lan4`) no AX3000T dependem do build; valide em **Network → Interfaces → Devices** antes de aplicar os blocos de config. Aplicar VLAN filtering errado pode trancar o acesso — tenha acesso por uma porta de gestão e saiba usar o failsafe (`uci revert`).
- A restrição de portas de saída do **IOT** (Tapo C100, Smart TV) é um ponto de partida; alguns dispositivos exigem portas/serviços de nuvem adicionais. Monitore `logread`/contadores de regra REJECT e libere caso um dispositivo legítimo falhe.
- O **Knup KP-TC44** tem saídas DC documentadas como "selecionáveis" 5/9/12V; valide fisicamente a entrega simultânea de 9V **e** 12V antes de depender dele. O **Marsriva KP3** é a opção mais segura para o requisito de duas tensões simultâneas.