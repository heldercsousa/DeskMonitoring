# **Anexo Técnico V17-A — Conteúdo detalhado NOVO \+ correções (complementa, não repete, o Anexo V16-A)**

> **Como usar:** as **Partes 1–3 do Anexo V16-A continuam válidas** e são a referência para a Trilha A. Este anexo traz: (i) correções pontuais àquelas partes; (ii) as partes novas 4–7, que detalham a Trilha B, o Bloco 8.5 (evidências), o Bloco 15 (sensor) e as opções de chave FIDO2. Mantenha os dois anexos juntos.

## **PARTE 0 — CORREÇÕES PONTUAIS AO ANEXO V16-A (verificadas jul/2026)**

1. **\[Key Findings — Winbond\]** O texto V16 dizia "não confie que 24.10 já resolve". **Atualização:** o fix do softbrick rd23/W25N01KV foi **mergeado no ramo oficial do OpenWrt no início de 2025** (issues \#16002 e \#16972 fechadas); builds 24.10 estáveis atuais tratam o chip. **Mantém-se:** recovery TFTP montado e testado antes de gravar; ImmortalWrt como plano B. (Fontes: github.com/openwrt/openwrt \#16002, \#16972; forum.openwrt.org tópico AX3000T.)
2. **\[Parte 1C — Mini UPS\]** Reclassificado: **disponibilidade, não segurança**. Trilha B adia a compra sem perda de proteção.
3. **\[Parte 3 — Compras\]** Preço verificado das YubiKey 5 NFC no BR: **R$ 679 (KriptoBR) a R$ 740 (Amazon BR)** por unidade. Alternativas na Parte 7.
4. **\[Recommendations\]** Acrescentar: o desktop 2016 reaproveitado substitui a compra do N100/Pi como sensor (Parte 6); prioridade de gasto continua sendo MFA/contas \> rede \> sensor.

## **PARTE 4 — TRILHA B: SEGMENTAÇÃO ENXUTA (2 VLANs)**

Mesma lógica DSA/fw4 da V16 (Anexo 2C/2D), com metade da superfície de configuração. Migração futura B → A: apenas **acrescentar** as bridge-vlans 40/50, suas interfaces/zonas e o mDNS — nada do que está abaixo é jogado fora.

### **4A. /etc/config/network (trecho — bridge VLANs)**

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
 list ports 'lan4:u*'            # WORK-DEV (cabo do notebook de trabalho)

config bridge-vlan
 option device 'br-lan'
 option vlan '30'
 list ports 'lan1:u*'            # HOME-MAIN (gestão + resto da casa)
 list ports 'lan2:u*'
 list ports 'lan3:u*'

# Interfaces lógicas vlan20/vlan30 (IP estático + dnsmasq por interface),
# WAN idêntica à V16 (wan.10 + PPPoE). Wi-Fi: 1 SSID -> vlan20, 1 SSID -> vlan30.
```

🔴 **Anti-lockout (igual V16):** esteja conectado numa porta untagged da **vlan30** antes de aplicar.

### **4B. /etc/config/firewall (completo da Trilha B)**

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

# ---------- HOME-MAIN (VLAN 30): casa + gestão ----------
config zone
 option name 'home'
 list network 'vlan30'
 option input 'ACCEPT'          # gestão do roteador vem daqui
 option output 'ACCEPT'
 option forward 'REJECT'

config forwarding
 option src 'home'
 option dest 'wan'

# ---------- DHCP + DNS para a zona com input REJECT (work) ----------
config rule
 option name 'allow-dhcp-work'
 option src 'work'
 option proto 'udp'
 option dest_port '67 68'
 option target 'ACCEPT'

config rule
 option name 'allow-dns-work'
 option src 'work'
 option proto 'tcp udp'
 option dest_port '53'
 option target 'ACCEPT'

# ---------- DNS forçado (redirect 53) — igual 2D-bis da V16, por zona ----------
config redirect
 option name 'force-dns-work'
 option src 'work'
 option proto 'tcp udp'
 option src_dport '53'
 option dest_port '53'
 option target 'DNAT'

config redirect
 option name 'force-dns-home'
 option src 'home'
 option proto 'tcp udp'
 option src_dport '53'
 option dest_port '53'
 option target 'DNAT'

# Opcional: barrar DoT externo
config rule
 option name 'block-dot'
 list src 'work'
 list src 'home'
 option dest 'wan'
 option proto 'tcp udp'
 option dest_port '853'
 option target 'REJECT'
```

* Blindagem do plano de gestão (dropbear/uhttpd na vlan30, WPA3\+PMF, WPS off): **idêntica ao Anexo V16-A 2F** — obrigatória também na Trilha B.
* mDNS/avahi: **não instalar** na Trilha B.
* **Teste mínimo (Bloco 8-B):** da vlan20 → ping/SSH/LuCI em host da vlan30 **FALHA**; da vlan30 → LuCI abre; cliente com DNS fixo 1.1.1.1 continua sendo atendido pelo roteador.

## **PARTE 5 — BLOCO 8.5 EM DETALHE: PRESERVAÇÃO DE EVIDÊNCIAS**

### **5A. Compra (adição ao Bloco 0)**

* **1× HD externo USB 3.0 dedicado**, ≥ soma dos discos dos PCs (2 TB na dúvida; compressão zstd encolhe bastante disco meio vazio). Etiquetar: **"EVIDÊNCIA — NÃO REUTILIZAR"**. Gravado uma vez → offline para sempre; nunca mais em máquina suja.

### **5B. PCs (notebook \+ desktop): imagem completa de disco**

🔴 **Nunca de dentro do Windows em uso** (SO comprometido pode adulterar a cópia; o boot altera timestamps). Sempre do **Live USB Linux limpo**.

1. **BitLocker primeiro (ainda no Windows):** exportar a **chave de recuperação** de cada volume (Gerenciar BitLocker → Backup da chave). Sem ela a imagem é ilegível. Guardar junto da evidência.
2. Boot pelo Live USB (modo "Try"). Conectar o HD de evidências.
3. Identificar discos: `lsblk -o NAME,SIZE,MODEL,SERIAL`
4. Montar **só** o HD externo: `sudo mount /dev/sdX1 /mnt/evid` (não montar o disco interno).
5. Imagem comprimida \+ hash:

   ```bash
   sudo dd if=/dev/nvme0n1 bs=4M status=progress | zstd -T0 > /mnt/evid/notebook_$(date +%Y%m%d).img.zst
   sha256sum /mnt/evid/notebook_*.img.zst > /mnt/evid/notebook.sha256
   ```

6. `nota_notebook.txt` no HD: data/hora, modelo/serial do PC e do disco, quem fez, por quê (cadeia de custódia mínima).
7. Repetir para o desktop. *(Alternativa GUI/forense: FTK Imager gerando E01 com verificação embutida — rodado de ambiente limpo.)*

### **5C. Android (S23 Ultra): coleta lógica**

Sem root **não existe** imagem física (por design). Antes do factory reset, em ordem de valor:

1. **AndroidQF** (coleta) \+ análise com **MVT** — já na stack do projeto.
2. `adb bugreport` → .zip de logs de sistema → HD de evidências.
3. **Samsung:** exportar/fotografar registros do **Auto Blocker** e do **Intrusion Logging** (One UI 8).
4. Screenshots: apps com admin de dispositivo, serviços de acessibilidade ativos, permissões estranhas, apps desconhecidos.
5. `sha256sum * > android.sha256`.

### **5D. Encerramento e limite legal**

* `sha256sum -c *.sha256` **antes** de desconectar → HD offline em local físico seguro, com chaves BitLocker e notas.
* Reabrir o HD só em **máquina limpa** (ex.: o desktop-sensor já reinstalado), idealmente montado **somente leitura** (`mount -o ro`).
* ⚖️ Autocoleta vale para análise própria e registro de integridade. Para peso pleno em juízo no Brasil, o padrão é aquisição por **perito** com cadeia de custódia formal — se houver chance real de judicialização, consultar advogado **antes** do wipe. (Orientação técnica, não jurídica.)

## **PARTE 6 — BLOCO 15 EM DETALHE: DESKTOP 2016 COMO SENSOR \+ SERVIDOR DE IA**

### **6A. Papel e pré-requisitos**

* Substitui a compra do N100/Pi como **sensor fora-de-banda** (economia de ~R$ 1.500–2.500). Requisitos verificados: **Security Onion 2.4 Eval = 4 cores/8–12 GB** (16 GB atuais passam); **Standalone = 24 GB mín.** (só após o upgrade de RAM). Fonte: docs.securityonion.net/en/2.4/hardware.html.
* 🔴 **Wipe primeiro (Bloco 9):** a máquina viveu na rede hostil. Sensor não confiável é pior que nenhum.
* **Hardware adicional:** 2ª NIC PCIe Gigabit (~R$ 100) para captura dedicada.

### **6B. Sistema operacional**

* **Host: Ubuntu 24.04 LTS ou Debian 12** — hardware Skylake tem suporte maduro; evitar rolling release (Arch etc.) por causa do driver NVIDIA legado (6E).
* **Security Onion** é distro própria (instala por ISO, substitui o SO) — se optar por ela, não há "host Ubuntu"; por isso a recomendação solo é a stack leve em 6C.

### **6C. Stack leve recomendada (operável sozinho, 16 GB)**

```bash
sudo apt install suricata zeek   # (zeek via repositório OBS do projeto, se necessário)
# EveBox (UI para alertas do Suricata): pacote .deb do site evebox.org
```

* **Suricata** escutando na NIC de captura; **Zeek** na mesma interface para logs de conexão/DNS/TLS; **EveBox** como interface web dos alertas — escutando **apenas** no IP da VLAN 30.
* Regras: `suricata-update` com fontes ET Open.
* **TinyCheck/SpyGuard** (análise do celular) roda no mesmo host, como já previsto na stack do projeto.

### **6D. Captura fora-de-banda**

* **NIC de captura SEM IP** (modo promíscuo, sem bind de protocolo): receber tráfego espelhado não expõe o sensor.

  ```bash
  # /etc/netplan ou ifupdown: interface sem endereço; subir com:
  sudo ip link set enp3s0 up promisc on
  ```

* **Espelhamento — 2 opções:**
  1. **No OpenWrt (tc/mirred, sem custo):** espelhar a porta de interesse para a porta onde o sensor está ligado:

     ```sh
     opkg update && opkg install tc-full kmod-sched-core kmod-ifb
     tc qdisc add dev lan1 ingress
     tc filter add dev lan1 parent ffff: matchall action mirred egress mirror dev lan3
     # repita para egress (qdisc root prio) se quiser os 2 sentidos
     ```

  2. **Switch TL-SG105E (port mirroring por menu web)** entre a HGU e o roteador ou num segmento específico — mais simples de operar, custo baixo.
* **Gestão do sensor:** a 1ª NIC (com IP) fica na **VLAN 30**; SSH por chave; EveBox/UIs só nessa interface.

### **6E. GPU / IA no mesmo host (limites verificados jul/2026)**

* **Driver NVIDIA:** o ramo **580 é o último** com suporte a Maxwell/Pascal/Volta (GTX 9xx/10xx); o 590\+ removeu (fonte: Phoronix; NVIDIA release notes). Ubuntu LTS/Debian mantêm o 580 empacotado — **fixe nesse ramo** e não atualize para 590+.
* **PyTorch:** wheels **≥2.8 (CUDA 12.8/12.9) removeram sm\_61 (Pascal)** — usar **PyTorch ≤2.7 com cu126** (fonte: dev-discuss.pytorch.org). Alternativas menos sensíveis a CUDA: **llama.cpp** (CPU/Vulkan), **ONNX Runtime**.
* **Capacidade realista:** SD 1.5/imagem leve e LLMs pequenos — ok; nada além disso. **Não investir** em upgrades além da RAM já planejada; dinheiro futuro de IA → GPU nova, não este chassi.
* **Regra do papel duplo:** serviços de IA (web UI/API) escutando **só na VLAN 30**; carga pesada pode derrubar pacotes da captura — não renderizar durante janela de coleta relevante.

### **6F. Windows 11 como VM sob o Linux (opcional)**

* **Sim, é possível e adiciona proteção real:** isolamento do host, **snapshots com rollback** (desconfia de algo? volta o snapshot), firewall do host controlando o que a VM alcança.
* **Como:** KVM/QEMU \+ virt-manager; requisito de TPM 2.0 do Win11 atendido com **swtpm** (TPM emulado); UEFI via OVMF; 8 GB \+ 4 vCPUs para uso confortável.

  ```bash
  sudo apt install qemu-kvm libvirt-daemon-system virt-manager swtpm ovmf
  ```

* **Regras:** só depois do upgrade de RAM (16 GB é apertado p/ sensor+IA+VM); a VM **nunca** enxerga a NIC de captura (rede da VM = NAT/bridge na NIC de gestão apenas); disco da VM em qcow2 com snapshot antes de qualquer instalação arriscada.
* **Sem necessidade concreta de Windows nesta máquina → Linux puro** (menos superfície de ataque).

## **PARTE 7 — CHAVES FIDO2: OPÇÕES POR CUSTO (verificado jul/2026)**

| Opção | Custo | Propriedade anti-phishing | Observações |
| :---- | :---- | :---- | :---- |
| **YubiKey 5 NFC** (Trilha A) | **R$ 679–740/un** (KriptoBR, Amazon BR) | FIDO2 completa | Robustez/ecossistema referência; 2 unidades \= ~R$ 1.400 |
| **Token2** (Trilha B, definitivo) | ~US$ 20–30/un \+ frete (loja europeia) | FIDO2 completa | Mesma imunidade a AiTM/Evilginx; prazo de importação — encomendar cedo |
| **Passkeys de plataforma** (Trilha B, imediato) | **R$ 0** | FIDO2 (mesma base WebAuthn) | No celular/PC **recém-formatados**; a chave física adiciona só independência do aparelho — cadastre a Token2 como 2º fator quando chegar |
| SMS / TOTP por app | — | ❌ Phishável em tempo real (AiTM) | Manter só como fallback onde não houver FIDO2 |

* Regra das duas trilhas: **sempre 2 autenticadores FIDO2 por conta crítica** (um de uso \+ um backup guardado em outro lugar) — na Trilha B, "passkey do celular \+ passkey do PC" já cumpre isso até as Token2 chegarem.

## **Fontes principais desta revisão**

* Security Onion 2.4 — Hardware Requirements: docs.securityonion.net/en/2.4/hardware.html
* OpenWrt — issues \#16002 e \#16972 (AX3000T Winbond, fix mergeado): github.com/openwrt/openwrt
* Phoronix — "NVIDIA Confirms 580 Linux Driver Is The Last For Maxwell/Pascal/Volta"
* PyTorch dev-discuss — remoção de Maxwell/Pascal nos builds CUDA 12.8/12.9
* KriptoBR / Amazon.com.br — preços YubiKey 5 NFC (jul/2026)
