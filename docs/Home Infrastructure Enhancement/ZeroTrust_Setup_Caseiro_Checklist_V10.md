# Checklist Consolidado — Setup Zero-Trust Caseiro (Opção Enxuta)

**Para fazer sozinho em casa | Baseado nas versões V2 + V9**
**Arquitetura:** 1 roteador OpenWrt (faz firewall + Wi-Fi + VLANs) + ONT standalone + Mini UPS DC

---

## ⓪ Antes de começar — leia isto

Este setup NÃO é plug-and-play. As partes difíceis são duas: (1) extrair as credenciais GPON da Vivo antes de devolver o roteador, e (2) o flashing do OpenWrt. Se você seguir a ordem abaixo, evita os dois maiores perrengues.

**Reserve um fim de semana.** Sua casa fica offline durante boa parte do processo.

---

## 🛒 Lista de compras (3 itens)

- [ ] **Roteador OpenWrt** — escolha conforme a velocidade do seu plano:
  - Até 400 Mbps: **TP-Link Archer C6 (V3 ou V4)** — *recomendado para iniciante: flash direto pela interface web, sem abrir o aparelho.*
  - Acima de 400 Mbps / Gigabit: **Belkin RT3200** ou **Linksys E8450** (CPU mais forte).
  - ⚠️ Evite o Xiaomi AX3200 como primeiro projeto: o flashing exige acesso UART/telnet e abrir o aparelho em modelos recentes. Mais trabalhoso.
- [ ] **ONT standalone** — **TP-Link XZ000-G3** (precisa ter a porta SC/APC verde para a fibra).
- [ ] **Mini UPS DC** — **Marsriva KP3** ou **Knup KP-TC44** (precisa ser multi-tensão, com saídas 9V e 12V simultâneas).

---

## 📥 FASE 1 — Preparação segura (antes de cortar a internet)

- [ ] Pegue um dispositivo limpo (ou o celular no 4G/5G, fora da rede de casa).
- [ ] Baixe a imagem do **OpenWrt** para o seu modelo exato de roteador no site oficial (firmware-selector.openwrt.org). Use sempre a versão **stable** mais recente para o seu chipset.
- [ ] Baixe a **ISO oficial do Windows** (se for reinstalar o notebook).
- [ ] Confira o **sha256** dos arquivos baixados contra o publicado no site. (Garante que o download não foi adulterado.)
- [ ] **Não use a rede atual da casa para nada disso.**

---

## 🔌 FASE 2 — Airgap e extração de identidade (a parte crítica)

- [ ] **Desconecte a fibra** (cabo verde) do roteador da Vivo. A casa está offline agora.
- [ ] Desative o Wi-Fi de todos os dispositivos.
- [ ] Conecte o notebook ao roteador da Vivo **via cabo de rede** (com a fibra já desconectada).
- [ ] Acesse o roteador da Vivo (geralmente `192.168.15.1`) e vá em **WAN / GPON / Óptica**.
- [ ] **Anote os 3 dados** (guarde num arquivo .txt seguro):
  - [ ] **GPON Serial Number (SN)** — geralmente 4 letras + 8 caracteres hexadecimais.
  - [ ] **SLID / GPON Password** (senha do assinante).
  - [ ] **Endereço MAC da porta WAN** (costuma estar na etiqueta do aparelho).
- [ ] ⚠️ Faça isso **o quanto antes**: se a Vivo atualizar o firmware antes, você pode perder acesso a esses dados e não conseguir autenticar a nova ONT.
- [ ] Desligue o roteador da Vivo e guarde-o. Ele não volta para a rede.

---

## 🌐 FASE 3 — Configurar a ONT (borda)

- [ ] Ligue a **ONT TP-Link XZ000-G3** ao notebook via cabo de rede e acesse a interface web dela.
- [ ] Insira o **GPON SN** e o **SLID** extraídos da Vivo. Salve.
- [ ] **Agora sim**, conecte o cabo de fibra verde na ONT.
- [ ] Aguarde a luz **"PON"** estabilizar (parar de piscar) = a central da Vivo reconheceu o equipamento. ✅

---

## ⚙️ FASE 4 — Flashing e configuração do OpenWrt

- [ ] **Flash:** instale o OpenWrt no roteador usando o arquivo limpo da Fase 1 (no Archer C6, é upload direto na seção de atualização de firmware da interface stock).
- [ ] Após o reboot, acesse o OpenWrt em `192.168.1.1` (interface **LuCI**).
- [ ] **Conexão WAN (PPPoE):**
  - [ ] Conecte a ONT na porta WAN do roteador.
  - [ ] Configure o protocolo **PPPoE** → usuário `cliente@cliente` / senha `cliente`.
  - [ ] Ative a marcação **VLAN ID 10** na WAN (a Vivo usa a VLAN 10 para internet).
  - [ ] No campo **"Override MAC address"**, cole o **MAC da porta WAN** extraído da Vivo (clonagem).
- [ ] Confirme que ganhou IP e tem internet antes de seguir.

---

## 🧱 FASE 5 — Segmentação (VLANs e Wi-Fi) — o coração do Zero Trust

Crie 4 zonas isoladas. Cada uma vira um SSID Wi-Fi separado apontando para sua VLAN.

| VLAN | Nome | Regra de firewall |
| :--- | :--- | :--- |
| **20** | WORK-DEV | **REJECT total** para tráfego local (entrada/saída de outras zonas). Acesso **apenas à Internet**. É aqui que você liga seu ambiente de código / Azure DevOps. |
| **30** | HOME-MAIN | Celular e dispositivos pessoais. Navegação livre. Pode *iniciar* conexão com a VLAN 40, mas a 40 não inicia com ela. |
| **40** | HOME-IOT | Câmera Tapo C100 e Smart TV. Internet restrita (só portas da nuvem Tapo / streaming). Bloqueio local total às VLANs 20 e 30. |
| **50** | GUEST-WIFI | Visitantes. Só portas **80/443**. Ative **"Client Isolation"** no Wi-Fi (um visitante não enxerga o outro). |

- [ ] VLAN 20 criada com política REJECT total para tráfego lateral.
- [ ] VLAN 30 criada.
- [ ] VLAN 40 criada e isolada.
- [ ] VLAN 50 criada com Client Isolation ativado.

---

## 📡 FASE 6 — mDNS Repeater (o "pulo do gato")

Sem isso, seu celular na VLAN 30 não consegue achar a TV/câmera na VLAN 40.

- [ ] Instale o pacote **`umdns`** ou **`avahi-daemon`** no OpenWrt.
- [ ] Configure para refletir os pacotes de descoberta **estritamente entre a VLAN 30 e a VLAN 40**.
- [ ] Garanta que a **VLAN 20 (WORK-DEV) permaneça invisível** a esse tráfego.

---

## 🔋 FASE 7 — Energia (Mini UPS DC)

- [ ] Ligue o **Mini UPS** na tomada (220V).
- [ ] Conecte a saída DC correspondente (9V ou 12V) na **ONT**.
- [ ] Conecte a saída DC de **12V** no **roteador OpenWrt**.
- [ ] Teste: tire o UPS da tomada e confirme que a internet continua funcionando (autonomia esperada: 4–6h). ✅

---

## 🧹 FASE 8 — Sanitização dos endpoints

- [ ] **Notebook:** crie o pendrive de instalação do Windows num PC sabidamente limpo. Na tela de partições, **exclua todas as partições** (inclusive Recovery) e instale na área não alocada.
- [ ] **Celular Android:** Factory Reset pelo menu de recovery/bootloader.
- [ ] **Câmera Tapo:** botão físico de reset por ~10 segundos.
- [ ] **Smart TV:** Factory Reset pelo menu interno.

---

## 🔁 FASE 9 — Operação e manutenção (rotina)

- [ ] Faça **backup das regras de firewall** (exportação XML/tarball no LuCI) **logo após** validar o isolamento.
- [ ] Repita o backup a cada alteração de política.
- [ ] Audite periodicamente as tabelas de tráfego no LuCI (comportamentos anômalos).
- [ ] Mantenha os pacotes atualizados pelo gerenciador do OpenWrt.
- [ ] Sempre use a **VLAN 20** para trabalho e a **VLAN 30** para lazer/controle da casa.

---

### ✅ Teste final de isolamento
Conecte um dispositivo na VLAN 40 (IoT) e tente acessar (ping/SSH) um dispositivo na VLAN 20 (Work). **Tem que falhar.** Se falhar, seu Zero Trust está funcionando.
