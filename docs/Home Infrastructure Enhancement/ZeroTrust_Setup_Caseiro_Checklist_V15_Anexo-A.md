# **Anexo Técnico V15-A — Rede Zero-Trust Residencial OpenWrt (Vivo Fibra 600 Mbps, Brasília/DF)**

## **TL;DR**

* O **Xiaomi AX3000T (MT7981B / Filogic 820, ARM dual-core A53)** é a melhor compra presencial em Brasília: é o único roteador com suporte oficial OpenWrt e CPU ARM forte realmente disponível no varejo físico brasileiro (Kabum, Amazon BR, Mercado Livre Full), por \~R$ 335–370. O Belkin RT3200/Linksys E8450 e o GL.iNet Flint 2, embora superiores para flash, são praticamente só importação (eBay/AliExpress/Ubuy) e não devem ser comprados presencialmente no DF.  
* ONT standalone recomendada: **TP-Link XZ000-G3** (conector **SC/APC**, R$ 100–270, amplamente disponível), com Mini UPS DC **Marsriva KP3** (R$ 200–280, saídas 9V/12V/5V simultâneas, comutação 0 ms). Ambos compráveis online com entrega rápida no DF; presencialmente o XZ000-G3 aparece em redes como Kalunga/Fujioka e lojas de redes/ISP.  
* A arquitetura Zero-Trust se implementa com 4 VLANs (DSA bridge no OpenWrt 24.10) \+ zonas de firewall com forwarding stateful unidirecional 30→40, mDNS reflector restrito a VLANs 30/40, e WAN PPPoE em VLAN 10 (\`cliente@cliente\`/\`cliente\`, MTU 1492; clonagem de MAC só se necessário). **Atenção (corrigido na V14):** zonas com porta restrita (IOT, GUEST) **não** levam \`config forwarding\` para a WAN — a liberação é feita só por \`config rule\` de portas específicas, senão o forwarding abre tudo e anula a restrição.

## **Key Findings**

### **Decisão de hardware (Parte 1\)**

A restrição dominante do projeto não é técnica, é **logística**: comprar presencialmente em Brasília. Isso elimina os dois melhores candidatos de flash (RT3200/E8450 e Flint 2), que no Brasil só existem via importação. O **Xiaomi AX3000T** vence por ser o único cruzamento de (a) suporte OpenWrt oficial, (b) CPU ARM Cortex-A53 com hardware flow offloading capaz de NAT em gigabit, e (c) disponibilidade real no varejo brasileiro.  
Os TP-Link Archer AX55/AX73 foram **rejeitados**: o AX55 V1 e o AX73 usam Qualcomm IPQ5018/IPQ0518, sem suporte OpenWrt estável; o AX55 V2/V4 usa Broadcom (sem OpenWrt). Só o AX55 **Pro V2** usa MT7981B, mas tem suporte incipiente (snapshot/WIP) e é raro no Brasil.

### **Coração técnico (Parte 2\)**

* **Flash do AX3000T** é mais trabalhoso que o do E8450 (requer obter SSH no firmware stock via ferramenta \`xmir-patcher\` antes de gravar o OpenWrt). Documento o procedimento e também o do E8450 como alternativa "plano B" (importado), que usa apenas upload web do instalador \`.itb\`.  
* **WAN Vivo**: VLAN 10, PPPoE \`cliente@cliente\`/\`cliente\`, MTU 1492; habilitar Software/Hardware flow offloading é obrigatório para chegar a 600 Mbps.  
* **VLANs DSA**: criadas em \`br-lan\` via Bridge VLAN filtering; cada VLAN vira device \`br-lan.20\`, \`br-lan.30\`, etc.; cada uma recebe interface lógica \+ zona de firewall.  
* **Regra direcional 30→40**: implementada com \`forwarding\` 30→40 \+ zona IOT com \`forward REJECT\`; o retorno 40→30 é permitido automaticamente por conntrack (stateful), sem precisar de forwarding 40→30.

## **Details**

## **PARTE 1 — HARDWARE: PESQUISA DE CAMPO EM BRASÍLIA**

### **1A. Roteador principal (firewall all-in-one com OpenWrt)**

**Análise dos candidatos:**

| Modelo | SoC | OpenWrt | NAT 600 Mbps | Disponível presencialmente em BSB? | Preço   |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Xiaomi AX3000T** | MediaTek MT7981B (2× ARM A53), Switch MT7531AE, 256 MB RAM, 128 MB NAND | **Oficial, suportado desde 23.05.4** | Sim, com flow offload | **Sim** — Kabum, Amazon BR, ML Full | R$ 335–370 |
| Belkin RT3200 / Linksys E8450 | MediaTek MT7622BV \+ MT7915AN/MT7975AN, 512 MB RAM | Oficial, excelente | Sim — \~850 Mbps medido | **Não** — só importação | \~US$ 70–120 |
| GL.iNet Flint 2 (GL-MT6000) | MediaTek MT7986A, 2.5GbE | Oficial \+ GL | Sim, folgado | **Não** — importação | \~R$ 900–1.300 |
| TP-Link Archer AX55 V1 / AX73 | Qualcomm IPQ5018/IPQ0518 | **Sem suporte estável** | — | Sim, mas inútil p/ OpenWrt | — |

**Nota técnica MIPS:** a premissa do checklist está correta — roteadores MIPS ficam limitados por CPU em \~300–400 Mbps. Todos os recomendados aqui usam ARM Cortex-A53, que com hardware flow offloading habilitado roteia em velocidade de linha gigabit.  
**Veredito — comprar: Xiaomi AX3000T (versão RD23, MT7981B).** Confirme no ato que é o modelo AX3000T (RD03/RD23) e não o "RD03V2"/AX3000 com chip Qualcomm.  
⚠️ **Risco de hardware em unidades recentes:** o AX3000T sai de fábrica com flash NAND ESMT F50L1G41LB ou Winbond W25N01KV; unidades com a variante Winbond W25N01KV podem sofrer softbrick com builds OpenWrt que não tratam esse chip. Use uma build OpenWrt recente (24.10.x ou superior).  
**Plano B:** Belkin RT3200 ou Linksys E8450.

### **1B. ONT Standalone**

**TP-Link XZ000-G3** — terminal GPON de 1 porta Gigabit. Especificações oficiais: compatível com ITU-T G.984 GPON, 1× porta RJ45 10/100/1000 Mbps \+ 1× porta SC/APC. É a ONT mais usada na comunidade brasileira. Preço R$ 100–270.

* **Conector de fibra:** SC/APC (verde).  
* **Alimentação 9 VDC:** casa com o Mini UPS DC.  
* **Alternativa:** VSOL V2802RH (2.5 Gbps).

**Onde comprar fisicamente em Brasília:** lojas de redes/telecom e ISP.

### **1C. Mini UPS DC**

**Marsriva KP3** — mini nobreak DC. Bateria 10.000 mAh. Saídas simultâneas 12V e 9V. Atende requisito de alimentar ONT e roteador. **Knup KP-TC44** — mini nobreak DC bivolt, atentar se as saídas entregam 9V e 12V simultâneos fisicamente.

## **PARTE 2 — PROCEDIMENTOS TÉCNICOS**

Procedimentos documentados para o Xiaomi AX3000T (MT7981B).

### **2A. Flash do OpenWrt**

#### **Procedimento AX3000T (MT7981B)**

1. **Preparação:**  
   * 🔴 **CRÍTICO: Ambiente Isolado.** Use um PC **100% limpo** (ex: rodando um Live USB Linux Ubuntu/Mint inicializável) com Python 3.x e Git instalados. **NÃO use** um sistema operacional da sua rede que possa estar comprometido no nível do Kernel para rodar o script ou transferir o firmware.  
   * Baixe as imagens OpenWrt do target mediatek/filogic (use uma versão estável recente, 24.10.x ou superior, pela correção do chip Winbond):  
     * openwrt-24.10.x-mediatek-filogic-xiaomi\_mi-router-ax3000t-initramfs-factory.ubi  
     * openwrt-24.10.x-mediatek-filogic-xiaomi\_mi-router-ax3000t-squashfs-sysupgrade.bin  
   * Faça **reset de fábrica** no roteador (segure o botão reset \~10 s com o aparelho ligado).  
2. **Acesso ao firmware stock:** IP padrão 192.168.31.1. Conecte o PC numa porta LAN, acesse, complete o wizard e defina senha de administrador.  
3. **Obter SSH com xmir-patcher:** Clone o repositório e rode o run.bat (Windows) ou ./run.sh (Linux). No menu, use a opção de obter token/criar acesso (a ferramenta extrai o stok e habilita SSH).  
4. **Gravar o OpenWrt (initramfs) e fazer sysupgrade:** Copie as imagens via scp para /tmp e grave pela CLI ou pelo patcher. Após gravar o initramfs e reiniciar, acesse o LuCI em 192.168.1.1 e faça upload do sysupgrade.bin.  
5. **Verificar OpenWrt ativo:** Após flash, IP volta para 192.168.1.1. LuCI deve mostrar OpenWrt.

**Recuperação (brick) — TFTP/U-Boot do AX3000T:** O AX3000T tem recovery via U-Boot por TFTP. Configure o PC com IP estático 192.168.31.100/24. Suba um servidor TFTP servindo a imagem de recuperação. Ligue o aparelho segurando o botão reset; o U-Boot busca a imagem por TFTP.

#### **Procedimento alternativo — Linksys E8450 / Belkin RT3200 (MT7622)**

Acesso via 192.168.1.1, firmware stock. Upload web do instalador .itb. Reinicie e aplique sysupgrade.itb.

### **2B. Configuração da WAN (ordem correta)**

🟢 Na Vivo GPON residencial, quem autentica é a ONT somada ao PPPoE. O MAC do roteador não participa na maioria dos casos. Comece sem clonagem.

* **Passo 1 — VLAN 10 na interface WAN (modelo DSA):** Network → Interfaces → Devices → Add device. Type: VLAN (802.1q). Base device: wan. VLAN ID: 10\. Cria o device wan.10.  
* **Passo 2 — Interface PPPoE:** Network → Interfaces → Add interface. Protocol: PPPoE. Device: wan.10. Usuário/Senha: cliente@cliente/cliente. MTU 1492\. Firewall zone: wan.  
* **Passo 3 — Testar.**  
* **Passo 3-B — Override do MAC (SÓ se o PPPoE NÃO autenticar):** No device wan.10 (ou base), aba Advanced, MAC address: cole o MAC da HGU Vivo original.

**Crítico para 600 Mbps:** Habilite Software flow offloading e Hardware flow offloading em Network → Firewall → General Settings.

### **2C. Segmentação por VLANs (DSA, OpenWrt 24.10)**

**Passo 1 — Criar as Bridge VLANs:** Network → Interfaces → Devices → Configure br-lan → Bridge VLAN filtering. Atribua as portas untagged (u\*) para cada VLAN correspondente.  
🔴 **EVITE SE TRANCAR PARA FORA (lockout):** Neste layout as 4 portas LAN viram acesso das 4 VLANs — não sobra porta para uma VLAN 1 de gestão. A administração passa a ser feita pela rede HOME-MAIN (vlan30). Esteja conectado na porta untagged da vlan30 antes de aplicar.  
**Conteúdo completo de /etc/config/network:**

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
 list ports 'lan4:u\*' \# porta de acesso WORK-DEV

config bridge-vlan  
 option device 'br-lan'  
 option vlan '30'  
 list ports 'lan1:u\*' \# porta de acesso HOME-MAIN

config bridge-vlan  
 option device 'br-lan'  
 option vlan '40'  
 list ports 'lan2:u\*' \# porta de acesso HOME-IOT

config bridge-vlan  
 option device 'br-lan'  
 option vlan '50'  
 list ports 'lan3:u\*' \# porta de acesso GUEST-WIFI

\# Interfaces lógicas vlan20, vlan30, vlan40, vlan50 (Static IPs)  
\# WAN: wan.10 e interface pppoe

### **2D. Regras de Firewall**

**Conteúdo completo de /etc/config/firewall:**

\# WORK-DEV (VLAN 20): só internet, zero lateral  
config zone  
 option name 'work'  
 list network 'vlan20'  
 option input 'REJECT'  
 option output 'ACCEPT'  
 option forward 'REJECT'

config forwarding  
 option src 'work'  
 option dest 'wan'

\# HOME-MAIN (VLAN 30): internet \+ inicia p/ IOT  
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
 option dest 'iot' \# 30 \-\> 40 permitido

\# HOME-IOT (VLAN 40): isolada  
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
 option dest\_port '53 80 123 443 8883'  
 option target 'ACCEPT'

### **2E. mDNS Repeater (refletir só entre VLAN 30 e 40\)**

Instalar avahi-daemon e configurar /etc/avahi/avahi-daemon.conf permitindo apenas br-lan.30 e br-lan.40. Configurar firewall para liberar UDP 5353 (dest 224.0.0.251) originado da zona iot.

### **2F. Configuração da ONT TP-Link XZ000-G3**

* **Acesso:** IP padrão 192.168.1.1.  
* **Passos GPON SN \+ SLID (rede Vivo):** Insira o GPON SN em hexadecimal, 16 dígitos (converta as 4 primeiras letras para ASCII→HEX). Insira o SLID. Defina VLAN 10 modo TAG.  
* **Problemas comuns e soluções:**  
  * *PON pisca eternamente / "fake O5" (Falha de SN/SLID):* SN ou SLID incorretos, ou conversão hex errada. Recolha o SN/SLID corretos pela interface da HGU Vivo (página /padrao ou tela de status GPON) e refaça a conversão.  
  * 🟡 *PON pisca eternamente (Bloqueio OMCI \- Plano B):* Se os dados hex/ASCII estiverem perfeitos e a ONT não autenticar (O5), sua central OLT pode estar exigindo a assinatura física do hardware Askey/MitraStar original. **Solução:** Devolva a HGU Vivo para a rede. Acesse-a, **desligue o Wi-Fi** e configure a interface WAN GPON para o **Modo Bridge**. Ela funcionará apenas como conversora de mídia. Conecte um cabo da porta LAN1 dela para a porta WAN do AX3000T, e mantenha a configuração de PPPoE \+ VLAN 10 no OpenWrt normalmente.  
  * *Registra (O5) mas sem internet:* VLAN errada ou PPPoE mal configurado no roteador.

## **PARTE 3 — LOJAS FÍSICAS EM BRASÍLIA**

Estratégia: roteador e UPS presencial, ONT online. Lojas: Kalunga, Netshop Informática, Glacon Informática, Lojas de provedores (SIA/Taguatinga). Varejo de massa no ParkShopping, Conjunto Nacional, etc.

## **Recommendations e Caveats**

* Risco de flash do AX3000T: unidades com flash Winbond podem dar softbrick; tenha recovery pronto.  
* Nomes de device (wan, lan1..lan4) dependem do build. Verifique antes.  
* Restrição de portas do IOT: libere via logread se necessário.