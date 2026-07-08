# Checklist Único — Remediação Zero-Trust (Rede + Contas + Nuvem)

**Um só documento, em ordem cronológica.** Siga de cima para baixo, sem pular. A ordem foi montada para que cada passo só aconteça quando o anterior tornou seguro fazê-lo.

> ### ⚠️ As 3 regras que evitam refazer tudo
> 1. **Ordem é tudo:** Rede nova → Endpoints formatados → **só então** as contas. Mexer nas contas antes re-vaza as credenciais.
> 2. **Extrair credenciais GPON cedo** (Bloco 2) é o único passo irreversível. Confira duas vezes.
> 3. **Nunca toque nas contas a partir de um aparelho ainda sujo.**

---

# 🛒 BLOCO 0 — Compras e preparação (antes de cortar a internet)

- [ ] **Roteador OpenWrt:**
  - Até 400 Mbps: **TP-Link Archer C6 (V3/V4)** — *recomendado: flash direto pela web.*
  - Acima de 400 Mbps: **Belkin RT3200** ou **Linksys E8450**.
  - ⚠️ Evite o Xiaomi AX3200 como 1º projeto (exige UART/telnet).
- [ ] **ONT standalone:** TP-Link XZ000-G3 (porta SC/APC verde).
- [ ] **Mini UPS DC:** Marsriva KP3 ou Knup KP-TC44 (multi-tensão 9V + 12V).
- [ ] Num dispositivo limpo (ou celular no 4G/5G), baixar:
  - [ ] Imagem **OpenWrt** do modelo exato (firmware-selector.openwrt.org), versão **stable**.
  - [ ] **ISO oficial do Windows**.
- [ ] Conferir o **sha256** dos dois arquivos contra o site oficial.
- [ ] Reserve um fim de semana. A casa fica offline durante o processo.

---

# 🔌 BLOCO 1 — Airgap (cortar e isolar)

- [ ] Desconectar a **fibra** (cabo verde) do roteador da Vivo. Casa offline.
- [ ] Desativar o Wi-Fi de todos os dispositivos.

---

# 🔑 BLOCO 2 — Extração de identidade (PASSO IRREVERSÍVEL — faça cedo)

- [ ] Conectar o notebook ao roteador da Vivo **via cabo** (fibra já desconectada).
- [ ] Acessar o roteador da Vivo (`192.168.15.1`) → seção **WAN / GPON / Óptica**.
- [ ] Anotar num .txt seguro:
  - [ ] **GPON Serial Number (SN)** — 4 letras + 8 hex.
  - [ ] **SLID / GPON Password**.
  - [ ] **MAC da porta WAN** (etiqueta do aparelho).
- [ ] ⚠️ Se a Vivo atualizar o firmware antes disso, você pode perder o acesso. Por isso é cedo.
- [ ] Desligar e guardar o roteador da Vivo. Não volta para a rede.

---

# 🌐 BLOCO 3 — Configurar a ONT

- [ ] Ligar a **ONT** ao notebook via cabo e acessar a interface web.
- [ ] Inserir **GPON SN** + **SLID**. Salvar.
- [ ] **Agora sim** conectar a fibra verde na ONT.
- [ ] Aguardar a luz **"PON"** estabilizar = central reconheceu o equipamento. ✅

---

# ⚙️ BLOCO 4 — Flashing e WAN do OpenWrt

- [ ] **Flash** do OpenWrt com o arquivo do Bloco 0 (no Archer C6, upload na interface stock).
- [ ] Acessar o OpenWrt em `192.168.1.1` (**LuCI**).
- [ ] Conectar a ONT na porta WAN do roteador.
- [ ] Configurar **PPPoE** → usuário `cliente@cliente` / senha `cliente`.
- [ ] Ativar **VLAN ID 10** na WAN.
- [ ] Em **"Override MAC address"**, colar o **MAC da Vivo** (clonagem).
- [ ] Confirmar que há internet antes de seguir.

---

# 🧱 BLOCO 5 — Segmentação (VLANs) — coração do Zero Trust

| VLAN | Nome | Regra de firewall |
| :--- | :--- | :--- |
| **20** | WORK-DEV | **REJECT total** ao tráfego local. Só Internet. (ambiente de código/Azure DevOps) |
| **30** | HOME-MAIN | Pessoal. Livre. Pode iniciar conexão com a 40; a 40 não com ela. |
| **40** | HOME-IOT | Tapo C100 + Smart TV. Internet restrita. Bloqueio local total às 20 e 30. |
| **50** | GUEST-WIFI | Visitantes. Só portas 80/443. **Client Isolation** ativado. |

- [ ] VLAN 20 com REJECT total ao tráfego lateral.
- [ ] VLAN 30 criada.
- [ ] VLAN 40 criada e isolada.
- [ ] VLAN 50 com Client Isolation.

---

# 📡 BLOCO 6 — mDNS Repeater (o "pulo do gato")

- [ ] Instalar pacote **`umdns`** ou **`avahi-daemon`**.
- [ ] Refletir descoberta **estritamente entre VLAN 30 e 40**.
- [ ] Garantir que a **VLAN 20 fique invisível** a esse tráfego.

---

# 🔋 BLOCO 7 — Energia (Mini UPS DC)

- [ ] Ligar o Mini UPS na tomada (220V).
- [ ] Saída DC (9V/12V) → **ONT**.
- [ ] Saída DC 12V → **roteador**.
- [ ] Teste: tirar o UPS da tomada; internet deve continuar (4–6h). ✅

---

# 🧪 BLOCO 8 — Teste de isolamento da rede

- [ ] De um aparelho na VLAN 40, tentar acessar (ping/SSH) um aparelho na VLAN 20.
- [ ] **Tem que FALHAR.** Se falhar, o Zero Trust está funcionando. ✅

> **🚧 PONTO DE VIRADA:** A rede está pronta e validada. Só agora você pode limpar os endpoints e, em seguida, as contas.

---

# 🧹 BLOCO 9 — Sanitização dos endpoints

- [ ] **Notebook:** pendrive de instalação feito num PC limpo. Na tela de partições, **excluir todas** (inclusive Recovery) e instalar na área não alocada.
- [ ] **Celular Android:** Factory Reset pelo recovery/bootloader.
- [ ] **Câmera Tapo:** reset físico ~10s.
- [ ] **Smart TV:** Factory Reset interno.

> A partir daqui, use **somente um dispositivo recém-formatado** para os blocos de contas.

---

# 🥇 BLOCO 10 — E-mail principal (a raiz de tudo)

- [ ] Senha nova, longa e única.
- [ ] **Encerrar todas as sessões ativas** ("sair de todos os dispositivos").
- [ ] **Apagar regras de encaminhamento/filtros** que você não criou. *(vetor mais ignorado)*
- [ ] Revisar "atividade recente / dispositivos" → remover desconhecidos.
- [ ] Ativar **2FA por app autenticador** (não SMS).
- [ ] Revisar e **revogar apps OAuth / terceiros** não reconhecidos.

---

# 🔐 BLOCO 11 — Gerenciador de senhas

- [ ] Instalar Bitwarden/1Password **no dispositivo limpo**.
- [ ] **Senha-mestra nova, forte, única.**
- [ ] Ativar 2FA no gerenciador.
- [ ] Usá-lo para gerar as senhas dos próximos blocos.

---

# 🏦 BLOCO 12 — Demais contas (ordem por dano)

Para CADA conta: **senha nova → encerrar sessões → 2FA → revogar OAuth → checar dispositivos.**

- [ ] **Banco / cartões.**
- [ ] **Microsoft / Azure** (trabalho/DevOps).
- [ ] **GitHub** + revisar/regerar **chaves SSH** e **Personal Access Tokens**.
- [ ] **Nuvem** (Google Drive / OneDrive / Dropbox).
- [ ] **Redes sociais e demais logins.**

---

# ☁️ BLOCO 13 — Arquivos na nuvem (risco silencioso)

**Tratar tudo como sujo até prova em contrário. NÃO ressincronizar a pasta inteira.**

- [ ] Acessar a nuvem pela **interface web** (não reinstalar o cliente de sync ainda).
- [ ] Revisar **compartilhamentos**: remover "qualquer pessoa com link" e contas estranhas.
- [ ] Revisar **permissões de apps** sobre a nuvem.
- [ ] Recuperar arquivos **seletivamente** — priorizar passivos (textos, PDFs, fotos).
- [ ] **Desconfiar de:** .exe/.msi, instaladores, scripts (.js/.bat/.ps1/.vbs), macros (.docm/.xlsm).
- [ ] Críticos e duvidosos → **VirusTotal** antes de abrir.
- [ ] Só religar a sincronização depois da pasta revisada.

---

# 🔁 BLOCO 14 — Rotina e detecção de reincidência

- [ ] **Backup das regras de firewall** (XML/tarball no LuCI) após validar o isolamento — e a cada alteração.
- [ ] Auditar tabelas de tráfego no LuCI periodicamente.
- [ ] Manter pacotes do OpenWrt atualizados.
- [ ] Sempre **VLAN 20 = trabalho**, **VLAN 30 = lazer/casa**.

**Sinais de que algo voltou:**
- [ ] E-mails de novo login / códigos 2FA não solicitados.
- [ ] Regras de encaminhamento apagadas que **reaparecem**.
- [ ] No **syslog do OpenWrt**, dispositivo "telefonando" para destinos estranhos.

**Se reincidir, é uma de 3 causas:** dispositivo não limpo, credencial não rotacionada, ou OAuth/encaminhamento esquecido. → Volte ao bloco correspondente.

---

## ⏱️ Resumo da espinha dorsal (cole na parede)

**Comprar → Cortar fibra → Extrair GPON → ONT → Flash+WAN → VLANs → mDNS → UPS → TESTAR rede → Formatar aparelhos → E-mail → Gerenciador de senhas → Demais contas → Nuvem → Rotina.**

A linha que nunca se cruza: **só mexer nas contas (Bloco 10+) depois da rede validada (Bloco 8) e dos aparelhos limpos (Bloco 9).**
