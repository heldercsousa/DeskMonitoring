# **Checklist Único — Remediação Zero-Trust (Rede \+ Contas \+ Nuvem) — V16**

**Um só documento, em ordem cronológica.** Siga de cima para baixo, sem pular. A ordem foi montada para que cada passo só aconteça quando o anterior tornou seguro fazê-lo.

> ### **🆕 O que mudou da V15 → V16 (leia antes de tudo)**
>
> Todas as mudanças abaixo foram verificadas por pesquisa antes de entrar aqui. O foco da V16 é **fechar o plano de controle do roteador e o vetor de phishing** — que, para quem opera sozinho, são por onde um atacante externo realmente volta a entrar. As mudanças mais importantes:
>
> 1. **NOVO no Bloco 0 (compras):** 2× chaves de segurança **FIDO2/passkey** (ex.: YubiKey 5 / Token2). É a maior blindagem anti-atacante de todo o projeto — ver Bloco 10.
> 2. **Trilha da WAN simplificada (Bloco 3):** o **Modo Bridge na HGU da Vivo** passou a ser a **rota PRINCIPAL recomendada**, não o "Plano B". Mesmo efeito Zero-Trust, sem o passo irreversível de extração GPON e sem o risco de incompatibilidade da ONT. A troca por ONT standalone virou **trilha avançada opcional**.
> 3. **NOVO Bloco 5.5 — Blindagem do plano de gestão do roteador:** senha root, SSH só por chave, LuCI/SSH restritos à VLAN de gestão, zero admin pela WAN, WPA3+PMF, WPS desligado, PSK único por SSID. (Faltava por completo na V15.)
> 4. **NOVO Bloco 6.5 — Controle de DNS/saída:** forçar todo DNS para o resolvedor do roteador + filtro de listas. Fecha o canal de C2/phishing por DNS.
> 5. **Correção Bloco 5/Anexo:** a **VLAN 50 (GUEST) não tinha zona de firewall** na V15. Agora tem zona completa + regras de DHCP/DNS para as zonas restritas (sem elas, IOT/GUEST/WORK ficam sem IP).
> 6. **Bloco 9 (UEFI) recalibrado:** o *reflash de BIOS deixou de ser "obrigatório para todos"*. Reinstalação limpa + Secure Boot continuam mandatórios; o reflash de firmware vira **opcional/avançado com aviso de brick**, porque não cobre ME/AMT e raramente é o vetor real numa casa.
> 7. **Bloco 0.5/4:** ambiente de **recovery TFTP pronto e testado** virou **pré-requisito travado** antes de qualquer flash (risco Winbond confirmado ainda presente no ramo oficial).

### **⚠️ As 4 regras que evitam refazer tudo**

1. **Ordem é tudo:** Rede nova → Endpoints formatados → **só então** as contas. Mexer nas contas antes re-vaza as credenciais.
2. **Extrair credenciais GPON só na trilha avançada** (Bloco 3B) — na rota principal (bridge) você **não precisa** desse passo irreversível.
3. **Nunca toque nas contas a partir de um aparelho ainda sujo.**
4. **Ensaie a parte difícil do OpenWrt ANTES de cortar a fibra** (ver Bloco 0.5). Os Blocos 4–6 são o coração técnico e onde você mais pode travar.

## **🧭 LEIA ISTO PRIMEIRO — Mapa de dificuldade e de retorno**

Antes de começar, saiba onde vai gastar tempo, onde corre risco de travar, e **onde está o retorno de segurança de verdade**. Trabalhando sozinho e com apoio do Claude, priorize por retorno.

| Bloco | O que é | Atrito | Retorno anti-atacante |
| :---- | :---- | :---- | :---- |
| **Bloco 10–13 (Contas/MFA/Nuvem)** | Chaves FIDO2, matar regras de e-mail, revogar OAuth | 🟢 BAIXO | 🥇 **O MAIOR.** É por aqui que quase todo recontágio doméstico entra (phishing/credencial). |
| **Bloco 9 (Sanitização)** | Reinstalar SO do zero | 🟢 BAIXO/MÉDIO | 🥈 Alto. Remove o malware persistente. |
| **Bloco 5.5 + 6.5 (Blindagem + DNS)** | Fechar o roteador e a saída DNS | 🟠 MÉDIO | 🥉 Alto. Fecha o plano de controle e o C2. |
| **Bloco 5 (VLANs)** | Segmentar a rede | 🔴 ALTO | Médio. Amplifica, contém laterais. |
| **Bloco 4 (Flash)** | Instalar OpenWrt | 🔴 ALTO/ARRISCADO | Médio. Tira o backdoor da HGU. |
| **Bloco 3B (ONT swap)** | Trocar a ONT (opcional) | 🔴 ALTO | ~Zero de segurança. É independência da Vivo, não defesa. **Prefira a rota bridge.** |

> 🧩 **Nota de pragmatismo (você opera sozinho):** a rede é o pedaço mais caro em esforço e o mais fácil de travar. Ela vale a pena porque a HGU da operadora é fraca — mas o **retorno de segurança contra hacker externo está concentrado nas contas/endpoints/MFA**, que são baratos e quase decisivos. Se o tempo apertar, faça as contas/MFA e a reinstalação limpa **primeiro na sua cabeça de prioridade**, mesmo que a rede fique para um segundo fim de semana. E **evite a troca de ONT**: a HGU em modo bridge dá o mesmo resultado com muito menos chance de você ficar preso.

## **🛒 BLOCO 0 — Compras e preparação (antes de cortar a internet)**

* **Roteador OpenWrt:** Xiaomi AX3000T (MT7981B) ou Archer C6/Belkin RT3200 dependendo da banda. 🔴 **CRÍTICO ANTES DE COMPRAR:** confira o modelo \+ revisão de hardware exata na tabela oficial do OpenWrt.
* 🆕 **2× chaves de segurança FIDO2 (hardware):** ex. YubiKey 5 NFC, Token2, ou Nitrokey. **Duas** para ter backup físico. É o item mais importante deste bloco para impedir novos ataques (ver Bloco 10). Compre agora para já estar em mãos na fase de contas.
* **(Opcional — trilha avançada) ONT standalone:** TP-Link XZ000-G3 (porta SC/APC verde). **Só compre se for seguir a trilha 3B.** Na rota principal (bridge) você **não precisa** dela.
* **Mini UPS DC:** Marsriva KP3 ou Knup KP-TC44 (multi-tensão 9V \+ 12V simultâneos).
* Num dispositivo **EXTERNO E 100% LIMPO** (ex: computador do trabalho, equipamento cedido por terceiros ou lan house de confiança — **NENHUM** PC da sua rede atual serve), baixar e preparar em pendrives separados:
  * Imagem **OpenWrt** do modelo exato (`firmware-selector.openwrt.org`), versão **stable**. 🔴 **Confirme na página do dispositivo/changelog que a build trata o chip NAND Winbond** (ver Bloco 0.5).
  * **ISO oficial do Windows** (via Media Creation Tool oficial da Microsoft).
  * **Live USB Linux (Ubuntu/Mint)** — para rodar o flash a partir de um SO comprovadamente limpo.
  * (Opcional) Firmwares de BIOS/UEFI originais mais recentes das placas-mãe — ver Bloco 9, agora **opcional**.
* Conferir o **sha256** dos arquivos contra os sites oficiais (quando disponível).
* Reserve um fim de semana. A casa fica offline durante o processo.

## **🧪 BLOCO 0.5 — ENSAIO A SECO (faça enquanto AINDA tem internet pela Vivo)**

* Com o roteador novo **fora da rede principal**, faça o **flash do OpenWrt**.
* 🔴 **PRÉ-REQUISITO TRAVADO — Recovery pronto e testado ANTES de flashar:** o AX3000T ainda tem casos de **softbrick com o chip NAND Winbond W25N01KV** em builds oficiais. Antes de gravar qualquer coisa: (1) tenha o **recovery TFTP/U-Boot** montado (PC com IP fixo 192.168.31.100/24 + servidor TFTP servindo a imagem); (2) confirme que a build escolhida menciona suporte ao Winbond; (3) se a sua unidade for Winbond e a build oficial falhar, tenha a imagem **ImmortalWrt** (que carregou o patch antes) como alternativa. **Não flashe sem o recovery no lugar.**
* Pratique criar as **VLANs e regras de firewall** (Bloco 5\), o **mDNS** (Bloco 6\), a **blindagem** (Bloco 5.5) e o **DNS forçado** (Bloco 6.5) com calma.
* Para pesquisar dúvidas, use **o celular no 4G/5G** — não dependa da rede da Vivo.
* 🔴 **HIGIENE DO ROTEADOR DE ENSAIO (não pule):** depois do ensaio, faça **re-flash limpo** ou no mínimo **"Reset to defaults"** antes do uso definitivo.
* ✅ Só avance para o Bloco 1 quando flash, VLANs, firewall, blindagem e DNS já forem **familiares**.

## **🔌 BLOCO 1 — Airgap (cortar e isolar)**

* Desconectar a **fibra** (cabo verde) do roteador da Vivo. Casa offline.
* Desativar o Wi-Fi de todos os dispositivos.

## **🔑 BLOCO 2 — Extração de identidade (SÓ SE for trilha avançada 3B)**

> Na **rota principal (bridge)** você **pula este bloco** — a HGU continua autenticando sozinha. Só execute se for trocar por ONT standalone (3B).

🟠 **CUIDADO:** Trate o aparelho usado aqui como descartável ou não confiável.

* Conectar o computador ao roteador da Vivo **via cabo** (fibra já desconectada).
* Acessar o roteador da Vivo (192.168.15.1) → seção **WAN / GPON / Óptica**.
* Anotar num .txt seguro: **GPON SN** (4 letras \+ 8 hex), **SLID / GPON Password**, **MAC da porta WAN**.
* 💡 Anote o SN exatamente como aparece (a ONT TP-Link pede 16 dígitos hex; converta as 4 letras ASCII→HEX).
* 🟠 Se o SLID não aparecer/estiver bloqueado, pesquise pelo seu modelo exato de HGU Vivo.

## **🌐 BLOCO 3 — WAN: ligar a internet (rota principal = HGU em Bridge)**

> ✅ **ROTA PRINCIPAL RECOMENDADA — HGU da Vivo em Modo Bridge.** Menos risco, mesmo efeito de segurança: quem faz roteamento, firewall e Wi-Fi é **só o seu OpenWrt**; a HGU vira um conversor "burro" de fibra sem inteligência exposta.

* Reconecte a fibra na HGU da Vivo e ligue-a ao PC via cabo.
* Acesse a HGU (192.168.15.1) → **desligue o Wi-Fi dela** (2.4 e 5 GHz).
* Configure a interface WAN/GPON em **Modo Bridge** (em algumas HGUs: "Bridge" no perfil de conexão; em outras, habilitar bridge e manter o VLAN 10 do lado da operadora).
* Ligue um cabo da **porta LAN1 da HGU** para a **porta WAN do Xiaomi AX3000T**.
* O PPPoE, a VLAN 10 e todo o firewall ficam no **OpenWrt** (Bloco 4). A HGU não roteia mais nada.
* ✅ Vantagem: **nada de extração GPON irreversível, nada de aposta de compatibilidade de ONT**. Se a Vivo trocar algo na rede, a HGU original continua homologada.

### **🧪 BLOCO 3B — (OPCIONAL / AVANÇADO) Trocar por ONT standalone**

> Só faça isto se quiser eliminar fisicamente a HGU. **Não adiciona segurança contra atacante externo** — é independência de hardware. Tem risco de lockout OMCI.

* Fez o Bloco 2? Ligue a **ONT** ao PC via cabo, insira **GPON SN \+ SLID**, salve, defina **VLAN 10 modo TAG**.
* Conecte a fibra verde na ONT e aguarde a luz **PON** ficar fixa. ✅
* 🟡 **Falha de OMCI (PON pisca eternamente com dados corretos):** a central pode exigir assinatura de hardware Askey/MitraStar. **Solução = voltar para a rota principal (Bloco 3, bridge).** Você não perde nada.

## **⚙️ BLOCO 4 — Flashing e WAN do OpenWrt**

### **4.1 — Flash**

* **Flash** do OpenWrt com o arquivo do Bloco 0 (com o **recovery TFTP no lugar** — Bloco 0.5). Rode o processo de um **SO limpo** (Live USB Linux), nunca de um PC da rede possivelmente comprometido.

### **4.2 — Acessar o LuCI e conectar a internet física**

* Acessar o OpenWrt em 192.168.1.1 (LuCI).
* Conectar a **saída da WAN** (LAN1 da HGU em bridge, ou a ONT) na **porta WAN** do roteador.

### **4.3 — WAN na ORDEM CORRETA**

* **1º — Ativar VLAN ID 10** na interface WAN (criar o device wan.10).
* **2º — Configurar o PPPoE** sobre o device wan.10 → usuário `cliente@cliente` / senha `cliente`, **MTU 1492**.
* **3º — Habilitar Software \+ Hardware flow offloading** (Network → Firewall) — obrigatório para chegar a ~600 Mbps.
* **4º — Testar:** confirmar internet. ✅
* **4º-B — (Só se NÃO autenticar):** device WAN → **"Override MAC address"** → cole o **MAC da HGU** (você só tem esse MAC se fez o Bloco 2; na rota bridge, quase nunca é necessário).

## **🧱 BLOCO 5 — Segmentação (VLANs) — coração do Zero Trust**

| VLAN | Nome | Regra de firewall |
| :---- | :---- | :---- |
| **20** | WORK-DEV | **REJECT total** ao tráfego local. Só Internet. |
| **30** | HOME-MAIN | Pessoal + **gestão do roteador**. **Pode iniciar** conexão com a 40; a 40 **não** com ela. |
| **40** | HOME-IOT | Internet restrita (portas específicas). Bloqueio local total às 20 e 30\. |
| **50** | GUEST-WIFI | Visitantes. Só DNS(no roteador)+80/443. **Client Isolation** ativado. **(Zona criada de fato na V16.)** |

* 🔴 **Gestão vem pela VLAN 30.** Esteja conectado na porta untagged da vlan30 antes de aplicar as VLANs, senão você se tranca para fora (não sobra VLAN 1 de gestão).
* ✅ Cada zona restrita (20/40/50) precisa de **regras que liberem DHCP (67/68) e DNS (53) para o próprio roteador** — sem isso os clientes ficam sem IP. Já incluídas no Anexo V16 (2D).

## **📡 BLOCO 6 — mDNS Repeater (o "pulo do gato")**

* Instalar **avahi-daemon** e refletir descoberta **estritamente entre VLAN 30 e 40** (`allow-interfaces=br-lan.30,br-lan.40`).
* 🔴 **VLAN 20 (trabalho) e VLAN 50 (guest) INVISÍVEIS** a esse tráfego. (Validado no Bloco 8.)

## **🛡️ BLOCO 5.5 — BLINDAGEM DO PLANO DE GESTÃO DO ROTEADOR (novo — não pule)**

> Sem isto, todo o resto fica em cima de um roteador de porta aberta. Aplique **antes** de ligar a rede em produção.

* **Senha root nova, longa e única** no OpenWrt (System → Administration).
* **SSH só por chave, senha desabilitada:** suba sua **chave pública** em System → Administration → SSH-Keys e desligue a autenticação por senha do dropbear.
* **SSH e LuCI só na VLAN de gestão (30):** dropbear com `option Interface 'vlan30'`; uHTTPd (LuCI) idem. **Zero administração pela WAN** (nada de LuCI/SSH ouvindo na internet).
* **Wi-Fi:** **WPA3-SAE** (ou WPA2/WPA3-mixed onde houver aparelho antigo) com **PMF (Management Frame Protection) obrigatório/ativado**.
* **WPS desligado.** **SSID por VLAN**, cada um com **PSK forte e único** (gerado no Bitwarden do Bloco 11).
* **GUEST (VLAN 50): "Isolate Clients" ligado** no rádio + zona de firewall só com DNS(roteador)+80/443.
* Desligar serviços que não usa. **uPnP deve ficar OFF.**
* ✅ Só depois desta blindagem a rede entra em produção.

## **🔎 BLOCO 6.5 — CONTROLE DE DNS / SAÍDA (novo — fecha o canal de C2)**

> Malware e páginas de phishing dependem de resolver domínios. Forçar o DNS pelo roteador corta boa parte desse canal e ainda te dá filtro de listas.

* **Resolvedor no roteador:** use o dnsmasq nativo, ou instale **AdGuard Home** (ou `https-dns-proxy`) para filtrar domínios de malware/anúncios e usar **DNS over TLS/HTTPS** upstream (ex.: Quad9 9.9.9.9, que já bloqueia domínios maliciosos).
* **Forçar todo mundo a usar o roteador (redirect da porta 53):** regra de firewall que intercepta e redireciona **todo tráfego destino porta 53** de cada VLAN para o roteador (assim um dispositivo com DNS "chumbado" não escapa). Snippet no Anexo 2D-bis.
* **Bloquear/interceptar DNS-over-TLS externo (porta 853)** e, se possível, apontar navegadores para **DoH do próprio roteador** para não perderem o filtro.
* ⚠️ **Limite honesto:** um dispositivo determinado ainda pode tunelar DNS por porta não-padrão; isso mitiga a maioria dos casos, não 100%.

## **🔋 BLOCO 7 — Energia (Mini UPS DC)**

* Ligar o Mini UPS na tomada (220V). Saída DC 9V/12V → **ONT/HGU**; saída 12V → **roteador**.
* **Teste de autonomia:** tirar da tomada; internet deve continuar (alvo: 4–6h). ✅

## **🧪 BLOCO 8 — Teste de isolamento da rede (validação final \+ 1º backup)**

* Da **VLAN 40**, tentar ping/SSH em aparelho na **VLAN 20**. 🔴 **Tem que FALHAR.** ✅
* Regra **direcional**: **30→40** funciona; **40→30** falha.
* **VLAN 50 → qualquer** falha, exceto DNS(roteador)+80/443 saída.
* 🔴 **Invisibilidade do mDNS:** de um aparelho na **VLAN 20 e na 50**, confirmar que **não** enxergam TV/câmera (na 40).
* 🆕 **Teste do plano de gestão:** de fora da VLAN 30 (ex.: da 40), tentar abrir LuCI/SSH do roteador → **tem que FALHAR**.
* 🆕 **Teste do DNS forçado:** num cliente, fixe um DNS externo (ex.: 1.1.1.1) e confirme que ele **continua sendo atendido pelo roteador** (redirect funcionando).
* 💾 **1º BACKUP AGORA:** exporte a config do OpenWrt (LuCI → System → Backup). ⚠️ **O backup contém segredos (senha PPPoE, chaves Wi-Fi) em texto** — guarde **cifrado** (ex.: dentro do Bitwarden ou num arquivo 7-Zip com AES-256), fora do roteador.

🚧 **PONTO DE VIRADA:** Rede pronta, validada, blindada e com backup. **Só agora** limpe os endpoints e depois as contas.

## **🧹 BLOCO 9 — Sanitização dos endpoints**

* ✅ **MANDATÓRIO — Reinstalação limpa do SO:** dê boot pelo pendrive limpo do Windows; na tela de partições, **exclua TODAS as partições** (inclusive OEM/Recovery) e instale na "Área Não Alocada".
* ✅ **MANDATÓRIO — Secure Boot ligado + senha de firmware (UEFI):** ative o Secure Boot e ponha **senha na BIOS/UEFI**. Isso barra bootkits triviais e impede que alguém reconfigure o boot.
* 🟠 **OPCIONAL / AVANÇADO — Reflash de BIOS/UEFI:** *deixou de ser obrigatório para todos na V16.* Só reflashe se houver **evidência concreta** de implante de firmware. **Avisos:** (1) reflash **não cobre** o Intel ME/AMT nem firmware de NIC/SSD — só um update completo do fabricante toca esses; (2) tem **risco real de brick**, ruim no meio de uma remediação solo; (3) se o SO estava infectado, o ganho é pequeno frente ao risco. Se for fazer, use a utilidade de firmware do próprio fabricante (EZ-Flash/Q-Flash), **a partir do nível de firmware** (não de dentro do Windows), com o firmware oficial mais recente.
* **Celular Android:** Factory Reset pelo recovery/bootloader.
* **Câmera Tapo:** reset físico \~10s. **Smart TV:** Factory Reset interno.

## **🥇 BLOCO 10 — E-mail principal (a raiz de tudo) — agora com chave física**

* Senha nova, longa e única (gerada no Bitwarden).
* 🆕 **Cadastre as 2 chaves FIDO2 como 2FA primário** (segurança física / passkey). **Motivo verificado:** TOTP por app é **phishável em tempo real** por proxies do tipo AiTM (Evilginx) — o site falso captura o código e usa na hora. A chave FIDO2 é **imune a phishing**: ela se recusa a responder a um domínio falso. Para quem opera sozinho, é a diferença entre "difícil" e "praticamente impossível" de retomar a conta.
  * Cadastre **as duas** chaves (uma de uso, uma de backup guardada em outro lugar).
  * Onde a conta permitir, ative **"exigir chave de segurança"** e **desative SMS**. Mantenha TOTP só como fallback onde não houver suporte a FIDO2.
* **Encerrar todas as sessões ativas** ("sair de todos os dispositivos").
* **Apagar regras de encaminhamento/filtros** que você não criou. 🔴 (vetor mais ignorado de todos)
* Revisar "atividade recente / dispositivos" → remover desconhecidos.
* Revisar e **revogar apps OAuth / terceiros** não reconhecidos.

## **🔐 BLOCO 11 — Gerenciador de senhas**

* Instalar Bitwarden/1Password **no dispositivo limpo**.
* **Senha-mestra nova, forte, única.**
* 🆕 **Proteger o cofre com as chaves FIDO2** (2FA de hardware no próprio gerenciador). O cofre é a nova raiz — trate-o como o e-mail.
* Usá-lo para gerar as senhas e os PSKs de Wi-Fi dos blocos anteriores/seguintes.

## **🏦 BLOCO 12 — Demais contas (ordem por dano) — chave física onde der**

* **Banco / cartões.**
* **Microsoft / Azure** (trabalho/DevOps) → 🆕 **cadastre a chave FIDO2/passkey** (Entra ID suporta) e reduza métodos fracos.
* **GitHub** → chave FIDO2 como 2FA, **regerar chaves SSH e Personal Access Tokens**.
* **Nuvem** (Google Drive / OneDrive / Dropbox) → passkey/chave onde houver.
* **Redes sociais e demais logins.**

## **☁️ BLOCO 13 — Arquivos na nuvem (risco silencioso)**

* Acessar a nuvem pela **interface web**.
* Revisar **compartilhamentos**: remover "qualquer pessoa com link" e contas estranhas.
* Revisar **permissões de apps** sobre a nuvem.
* Recuperar arquivos **seletivamente**. Desconfiar de scripts, instaladores e macros.
* Só religar a sincronização depois da pasta revisada.

## **🔁 BLOCO 14 — Rotina e detecção de reincidência**

* **Backup das regras de firewall** (.tar.gz cifrado) a cada alteração.
* Auditar tabelas de tráfego no LuCI periodicamente; olhar logs do resolvedor DNS (domínios estranhos = alerta).
* Manter pacotes do OpenWrt atualizados (considere **attended-sysupgrade**); acompanhar avisos de segurança do modelo.
* 🆕 **Acesso remoto só por WireGuard** — **nunca** exponha LuCI/SSH na WAN. Se precisar administrar de fora, suba um túnel WireGuard e administre por dentro dele.
* Sempre **VLAN 20 \= trabalho**, **VLAN 30 \= lazer/casa/gestão**.
