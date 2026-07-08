# **Checklist Único — Remediação Zero-Trust (Rede \+ Contas \+ Nuvem) — V15**

**Um só documento, em ordem cronológica.** Siga de cima para baixo, sem pular. A ordem foi montada para que cada passo só aconteça quando o anterior tornou seguro fazê-lo.

### **⚠️ As 4 regras que evitam refazer tudo**

1. **Ordem é tudo:** Rede nova → Endpoints formatados → **só então** as contas. Mexer nas contas antes re-vaza as credenciais.  
2. **Extrair credenciais GPON cedo** (Bloco 2\) é o único passo irreversível. Confira duas vezes.  
3. **Nunca toque nas contas a partir de um aparelho ainda sujo.**  
4. **Ensaie a parte difícil do OpenWrt ANTES de cortar a fibra** (ver Bloco 0.5). Os Blocos 4–6 são o coração técnico e onde você mais pode travar.

## **🧭 LEIA ISTO PRIMEIRO — Mapa de dificuldade (você disse não conhecer os processos)**

Antes de começar, saiba onde vai gastar tempo e onde corre risco de travar. Estude esses pontos **antes** de chegar neles.

| Bloco | O que é | Nível de atrito | Por quê   |
| :---- | :---- | :---- | :---- |
| **Bloco 4 (Flash)** | Instalar OpenWrt no roteador | 🔴 **ALTO / ARRISCADO** | Flash errado "embrica" o aparelho. Procedimento muda por modelo **e revisão de hardware**. |
| **Bloco 5 (VLANs)** | Criar redes isoladas \+ firewall | 🔴 **ALTO** | Coração técnico. Modelo de VLAN mudou no OpenWrt moderno (DSA); muitos tutoriais antigos estão desatualizados. |
| **Bloco 2 (GPON)** | Extrair SN/SLID da Vivo | 🟠 **MÉDIO** | O campo SLID pode estar oculto/bloqueado no firmware dependendo do modelo. |
| **Bloco 6 (mDNS)** | TV/câmera aparecerem no celular | 🟠 **MÉDIO** | Refletir descoberta só entre 30 e 40 sem vazar pra 20 dá trabalho de ajustar. |
| **Bloco 4 (PPPoE/MAC)** | Autenticar na operadora | 🟢 **BAIXO** | PPPoE direto sobre a VLAN 10\. Clonagem de MAC é **opcional**. |
| **Bloco 3 (ONT)** | Configurar o conversor de fibra | 🟢 **BAIXO** | Inserir SN/SLID é direto; só entender as luzes. |
| **Bloco 9 (Formatar)** | Limpar os aparelhos | 🟢 **BAIXO** mas crítico | Destrutivo e irreversível. Agora engloba UEFI flash obrigatorio. |

## **🛒 BLOCO 0 — Compras e preparação (antes de cortar a internet)**

* **Roteador OpenWrt:** Xiaomi AX3000T (MT7981B) ou Archer C6/Belkin RT3200 dependendo da banda. 🔴 **CRÍTICO ANTES DE COMPRAR:** confira o modelo \+ revisão de hardware exata na tabela oficial do OpenWrt.  
* **ONT standalone:** TP-Link XZ000-G3 (porta SC/APC verde).  
* **Mini UPS DC:** Marsriva KP3 ou Knup KP-TC44 (multi-tensão 9V \+ 12V simultâneos).  
* Num dispositivo **EXTERNO E 100% LIMPO** (ex: computador do trabalho, equipamento cedido por terceiros ou lan house de confiança — **NENHUM** PC da sua rede atual serve), baixar e preparar em pendrives separados:  
  * Imagem **OpenWrt** do modelo exato (\`firmware-selector.openwrt.org\`), versão **stable**.  
  * **ISO oficial do Windows** (via Media Creation Tool oficial da Microsoft).  
  * 🔴 **Firmwares de BIOS/UEFI originais e mais recentes** para as placas-mãe de todos os seus computadores.  
* Conferir o **sha256** dos arquivos contra os sites oficiais (quando disponível).  
* Reserve um fim de semana. A casa fica offline durante o processo.

## **🧪 BLOCO 0.5 — ENSAIO A SECO (faça enquanto AINDA tem internet pela Vivo)**

* Com o roteador novo **fora da rede principal**, faça o **flash do OpenWrt**.  
* Pratique criar as **VLANs e regras de firewall** (Bloco 5\) e o **mDNS** (Bloco 6\) com calma.  
* Para pesquisar dúvidas, use **o celular no 4G/5G** — não dependa da rede da Vivo.  
* 🔴 **HIGIENE DO ROTEADOR DE ENSAIO (não pule):** Durante o ensaio o roteador novo encostou na sua rede atual e recebeu configs de teste. **Antes do uso definitivo no Bloco 4**, faça uma de duas coisas: **Re-flash limpo** ou no mínimo, **"Reset to defaults"**.  
* ✅ Só avance para o Bloco 1 (cortar a fibra) quando o flash, as VLANs e o firewall já forem **familiares** para você.

## **🔌 BLOCO 1 — Airgap (cortar e isolar)**

* Desconectar a **fibra** (cabo verde) do roteador da Vivo. Casa offline.  
* Desativar o Wi-Fi de todos os dispositivos.

## **🔑 BLOCO 2 — Extração de identidade (PASSO IRREVERSÍVEL — faça cedo)**

🟠 **CUIDADO:** Trate o aparelho usado aqui como descartável ou não confiável.

* Conectar o computador ao roteador da Vivo **via cabo** (fibra já desconectada).  
* Acessar o roteador da Vivo (192.168.15.1) → seção **WAN / GPON / Óptica**.  
* Anotar num .txt seguro:  
  * **GPON Serial Number (SN)** — 4 letras \+ 8 hex.  
  * **SLID / GPON Password**.  
  * **MAC da porta WAN**.  
* 💡 **Anote o SN exatamente como aparece.** Na ONT TP-Link XZ000-G3 ele terá de ser inserido em 16 dígitos hexadecimais (convertendo as 4 letras para ASCII→HEX).  
* 🟠 **Se o SLID não aparecer / estiver bloqueado:** pesquise pelo seu modelo exato de roteador Vivo. Em algumas regiões a autenticação é só por SN, sem SLID.  
* Desligar e guardar o roteador da Vivo. Não volta para a rede.

## **🌐 BLOCO 3 — Configurar a ONT**

* Ligar a **ONT** ao computador via cabo e acessar a interface web.  
* Inserir **GPON SN** \+ **SLID**. Salvar.  
* **Agora sim** conectar a fibra verde na ONT.  
* Aguardar a luz **"PON"** estabilizar (parar de piscar e ficar fixa) \= central reconheceu o equipamento. ✅  
* 🟡 **PLANO B (Falha de OMCI):** Se a luz PON piscar eternamente mesmo com o SN e SLID perfeitamente corretos, a central da Vivo na sua rua exige a assinatura de hardware original (Askey/MitraStar/etc). Caso isso ocorra: descarte a ONT TP-Link, devolva o roteador da Vivo à rede, acesse-o, **desligue o Wi-Fi dele** e configure-o em **Modo Bridge**. Ele fará apenas a conversão óptica, atuando de forma "burra". Ligue um cabo de rede da porta LAN1 dele para a porta WAN do seu Xiaomi AX3000T (que assumirá todo o PPPoE, VLAN 10 e firewall).

## **⚙️ BLOCO 4 — Flashing e WAN do OpenWrt**

### **4.1 — Flash**

* **Flash** do OpenWrt com o arquivo do Bloco 0\.

### **4.2 — Acessar o LuCI e conectar a internet física**

* Acessar o OpenWrt em 192.168.1.1 (LuCI).  
* Conectar a ONT na **porta WAN** do roteador.

### **4.3 — WAN na ORDEM CORRETA**

* **1º — Ativar VLAN ID 10** na interface WAN (criar o device wan.10).  
* **2º — Configurar o PPPoE** sobre o device wan.10 → usuário cliente@cliente / senha cliente, **MTU 1492**.  
* **3º — Testar:** confirmar que há internet. ✅  
* **3º-B — (Só se NÃO autenticar):** vá ao device WAN → **"Override MAC address"** e cole o **MAC da Vivo** anotado no Bloco 2\. Reaplique e teste.

## **🧱 BLOCO 5 — Segmentação (VLANs) — coração do Zero Trust**

| VLAN | Nome | Regra de firewall   |
| :---- | :---- | :---- |
| **20** | WORK-DEV | **REJECT total** ao tráfego local. Só Internet. |
| **30** | HOME-MAIN | Pessoal. Livre. **Pode iniciar** conexão com a 40; a 40 **não** com ela. |
| **40** | HOME-IOT | Internet restrita. Bloqueio local total às 20 e 30\. |
| **50** | GUEST-WIFI | Visitantes. Só portas 80/443. **Client Isolation** ativado. |

## **📡 BLOCO 6 — mDNS Repeater (o "pulo do gato")**

* Instalar pacote **umdns** ou **avahi-daemon**.  
* Refletir descoberta **estritamente entre VLAN 30 e 40**.  
* 🔴 **Garantir que a VLAN 20 (trabalho) fique INVISÍVEL** a esse tráfego de descoberta. (Este ponto é validado no Bloco 8.)

## **🔋 BLOCO 7 — Energia (Mini UPS DC)**

* Ligar o Mini UPS na tomada (220V).  
* Saída DC (9V/12V) → **ONT**.  
* Saída DC 12V → **roteador**.  
* **Teste de autonomia:** tirar o UPS da tomada; a internet deve continuar (alvo: 4–6h). ✅

## **🧪 BLOCO 8 — Teste de isolamento da rede (validação final \+ 1º backup)**

* De um aparelho na **VLAN 40**, tentar acessar (ping/SSH) um aparelho na **VLAN 20**. 🔴 **Tem que FALHAR.** Se falhar, o Zero Trust está funcionando. ✅  
* Testar a regra **direcional**: de um aparelho na **VLAN 30**, alcançar a **VLAN 40** (deve **funcionar**); o contrário, 40→30 (deve **falhar**).  
* Testar **VLAN 50 → qualquer** (deve **falhar**, exceto saída para a internet nas portas 80/443).  
* 🔴 **Validar a invisibilidade do mDNS (Bloco 6):** com um aparelho na **VLAN 20**, confirmar que ele **não** descobre/enxerga a TV nem a câmera (que estão na 40).  
* 💾 **1º BACKUP AGORA:** com o isolamento validado, exporte a configuração do OpenWrt (LuCI → System → Backup) e guarde-a fora do roteador.

🚧 **PONTO DE VIRADA:** A rede está pronta, validada e com backup. **Só agora** você pode limpar os endpoints e, em seguida, as contas.

## **🧹 BLOCO 9 — Sanitização dos endpoints**

* 🔴 **CRÍTICO: Regravar BIOS/UEFI.** Antes de formatar ou dar boot pelo disco de instalação, use o pendrive com o firmware de placa-mãe (criado no PC externo no Bloco 0\) para realizar o flash/update da BIOS/UEFI de todos os computadores. Isso elimina malwares de nível Kernel (Ring 0\) que sobrevivem a formatações limpas.  
* **Notebook/Computadores:** após flashear a BIOS, dê boot pelo pendrive de instalação limpo do Windows. Na tela de partições, **excluir TODAS as partições** (inclusive OEM e Recovery) e instalar o sistema diretamente na "Área Não Alocada".  
* **Celular Android:** Factory Reset pelo recovery/bootloader.  
* **Câmera Tapo:** reset físico \~10s.  
* **Smart TV:** Factory Reset interno.

## **🥇 BLOCO 10 — E-mail principal (a raiz de tudo)**

* Senha nova, longa e única.  
* **Encerrar todas as sessões ativas** ("sair de todos os dispositivos").  
* **Apagar regras de encaminhamento/filtros** que você não criou. 🔴 (vetor mais ignorado de todos)  
* Revisar "atividade recente / dispositivos" → remover desconhecidos.  
* Ativar **2FA por app autenticador** (não SMS).  
* Revisar e **revogar apps OAuth / terceiros** não reconhecidos.

## **🔐 BLOCO 11 — Gerenciador de senhas**

* Instalar Bitwarden/1Password **no dispositivo limpo**.  
* **Senha-mestra nova, forte, única.**  
* Ativar 2FA no gerenciador.  
* Usá-lo para gerar as senhas dos próximos blocos.

## **🏦 BLOCO 12 — Demais contas (ordem por dano)**

* **Banco / cartões.**  
* **Microsoft / Azure** (trabalho/DevOps).  
* **GitHub** → além da senha, **regerar chaves SSH e Personal Access Tokens**.  
* **Nuvem** (Google Drive / OneDrive / Dropbox).  
* **Redes sociais e demais logins.**

## **☁️ BLOCO 13 — Arquivos na nuvem (risco silencioso)**

* Acessar a nuvem pela **interface web**.  
* Revisar **compartilhamentos**: remover "qualquer pessoa com link" e contas estranhas.  
* Revisar **permissões de apps** sobre a nuvem.  
* Recuperar arquivos **seletivamente**. Desconfiar de scripts, instaladores e macros.  
* Só religar a sincronização depois da pasta revisada.

## **🔁 BLOCO 14 — Rotina e detecção de reincidência**

* **Backup das regras de firewall** (arquivo .tar.gz) a cada alteração.  
* Auditar tabelas de tráfego no LuCI periodicamente.  
* Manter pacotes do OpenWrt atualizados.  
* Sempre **VLAN 20 \= trabalho**, **VLAN 30 \= lazer/casa**.