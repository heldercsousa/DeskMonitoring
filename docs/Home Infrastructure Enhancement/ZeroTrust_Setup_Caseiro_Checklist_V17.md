# **Checklist Único — Remediação Zero-Trust (Rede \+ Contas \+ Nuvem) — V17**

**Um só documento, em ordem cronológica.** Siga de cima para baixo, sem pular. A novidade da V17: cada bloco agora indica o que muda entre **duas trilhas** — escolha uma antes de começar e mantenha a escolha.

> ### **🧭 As duas trilhas da V17 (escolha ANTES do Bloco 0)**
>
> | | **TRILHA A — Completa** (V16 \+ correções) | **TRILHA B — Enxuta** (mínimo custo/atrito) |
> | :---- | :---- | :---- |
> | **Para quem** | Quem quer a arquitetura final de uma vez | Quem quer proteção forte JÁ, com o mínimo de dinheiro e de pontos de travamento |
> | **VLANs** | 4 (WORK/HOME/IOT/GUEST) \+ mDNS | **2 (WORK \+ HOME)** — IOT/GUEST ficam para depois; mDNS desnecessário |
> | **Chaves FIDO2** | 2× YubiKey 5 NFC (R$ 679–740 cada no BR) | **Passkeys de plataforma (grátis) agora** \+ 2× Token2 (~US$ 25 cada, importação) depois |
> | **Sensor fora-de-banda** | Desktop 2016 reaproveitado (ou N100 se quiser baixo consumo 24/7) | Desktop 2016 reaproveitado, ligado **só em janelas de coleta** |
> | **Mini UPS** | Sim | **Adiar** (é disponibilidade, não segurança) |
> | **ONT standalone** | Nunca (mantido da V16) | Nunca |
> | **Gasto típico** | ~R$ 2.000–2.600 | **~R$ 450–800** |
> | **Proteção real contra o atacante externo** | ~100% do desenho | **~90%** — os 10% que faltam são contenção IOT/GUEST, não o vetor de reentrada |
>
> 🧩 A Trilha B **não é uma versão fraca**: ela concentra 100% dos itens de maior retorno (contas/MFA/endpoints/bridge/blindagem/DNS) e corta só o que é contenção secundária. Você pode migrar B → A depois, sem refazer nada.

> ### **🆕 O que mudou da V16 → V17 (histórico incremental — leia antes de tudo)**
>
> Todas as mudanças verificadas por pesquisa em jul/2026.
>
> 1. **Documento reorganizado em 2 trilhas (A/B)** — ver quadro acima. Blocos sem marcação valem para as duas.
> 2. **NOVO Bloco 8.5 — Preservação de evidências:** imagem forense dos PCs \+ coleta lógica do Android **antes** de qualquer wipe. O Bloco 9 destrói evidência; este bloco a congela. Obrigatório nas duas trilhas. Detalhe no Anexo Parte 5.
> 3. **Sensor fora-de-banda: o desktop 2016 (16 GB) substitui a compra do N100/Pi.** Verificado: Security Onion 2.4 Eval pede 4 cores/8–12 GB (16 GB passa); Standalone pede 24 GB (coberto pelo upgrade de RAM já planejado). Recomendação prática: stack leve Suricata\+Zeek\+EveBox em Debian/Ubuntu, mais fácil de operar sozinho. Novo Bloco 15 \+ Anexo Parte 6.
> 4. **SO do desktop-sensor: Linux como host; Windows 11 opcional como VM (KVM/QEMU \+ swtpm).** A VM adiciona isolamento real (snapshot/rollback, firewall do host). Só com RAM ampliada; VM sem acesso à NIC de captura. Sem necessidade concreta de Windows → Linux puro. Anexo Parte 6.
> 5. **Chaves FIDO2 — custo atualizado e alternativas:** YubiKey 5 NFC está R$ 679–740/unidade no BR (R$ ~1.400 o par). Alternativas com a MESMA propriedade anti-phishing: **Token2** (~US$ 20–30, importação) e **passkeys de plataforma (grátis)** nos aparelhos recém-reconstruídos. Trilha B começa com passkeys.
> 6. **Risco Winbond recalibrado:** o fix do softbrick (rd23/W25N01KV) **foi incorporado ao ramo oficial do OpenWrt no início de 2025** (issues \#16002/\#16972 fechadas); builds 24.10 estáveis atuais tratam o chip. O pré-requisito de **recovery TFTP montado antes do flash é MANTIDO** (custa 1h e elimina o pior cenário).
> 7. **Mini UPS reclassificado como opcional** (Trilha B adia): protege contra queda de energia, não contra o atacante.
> 8. **Faseamento oficializado:** as contas/endpoints (Fases — ver Bloco 0.7) **podem preceder a rede nova**, desde que executadas **de aparelho recém-formatado, via 4G/5G/hotspot** — nunca pela rede antiga. Preserva a intenção da regra de ordem da V16 sem exigir tudo num fim de semana.
> 9. **Nota para o plano de IA no desktop:** NVIDIA encerrou Maxwell/Pascal no driver 590+ (ramo 580 é o último; segue com fixes); PyTorch ≥2.8 (CUDA 12.8) dropou Pascal → fixar PyTorch ≤2.7/cu126 ou usar llama.cpp/ONNX. Não invista além do upgrade de RAM. Anexo Parte 6.5.

### **⚠️ As 4 regras que evitam refazer tudo (V16, com a regra 1 flexibilizada)**

1. **Ordem é tudo — com faseamento permitido:** o ideal segue Rede nova → Endpoints → Contas. Se fasear (Bloco 0.7), a exigência mínima é: **contas só de aparelho limpo \+ conexão confiável (4G/hotspot)**, nunca pela rede antiga.
2. **Extrair credenciais GPON só na trilha avançada** — na rota principal (bridge) você **não precisa**.
3. **Nunca toque nas contas a partir de um aparelho ainda sujo.**
4. **Ensaie a parte difícil do OpenWrt ANTES de cortar a fibra** (Bloco 0.5).

## **🧭 Mapa de dificuldade e de retorno (atualizado V17)**

| Bloco | O que é | Atrito | Retorno anti-atacante | Trilha |
| :---- | :---- | :---- | :---- | :---- |
| **10–13 (Contas/MFA)** | Passkeys/FIDO2, regras de e-mail, OAuth | 🟢 BAIXO | 🥇 **O MAIOR** | A e B |
| **8.5 (Evidências)** 🆕 | Imagens forenses antes do wipe | 🟢 BAIXO | — (é prova, não defesa) | A e B |
| **9 (Sanitização)** | Reinstalar SO do zero | 🟢 BAIXO/MÉDIO | 🥈 Alto | A e B |
| **5.5 \+ 6.5 (Blindagem \+ DNS)** | Fechar roteador e saída DNS | 🟠 MÉDIO | 🥉 Alto | A e B |
| **5 (VLANs)** | Segmentar a rede | 🔴 ALTO (A) / 🟠 MÉDIO (B, 2 VLANs) | Médio | A completo; B enxuto |
| **4 (Flash)** | Instalar OpenWrt | 🔴 ALTO | Médio | A e B |
| **15 (Sensor)** 🆕 | Desktop 2016 como sensor | 🟠 MÉDIO | Médio (detecção) | A e B |
| **3B (ONT swap)** | Trocar a ONT | 🔴 ALTO | ~Zero | Nenhuma (evitar) |

## **📅 BLOCO 0.7 — FASEAMENTO (🆕 leia antes de comprar)**

Se não puder fazer tudo num fim de semana, execute nesta ordem, em fins de semana separados:

* **FASE 1 (custo ~R$ 0–300):** Bloco 8.5 (evidências) → Bloco 9 (formatar notebook \+ desktop \+ celular) → Blocos 10–13 (contas/MFA) **feitos do aparelho limpo via 4G/hotspot**.
* **FASE 2 (custo ~R$ 350–450):** Blocos 0.5–8 (roteador, bridge, VLANs, blindagem, DNS, testes).
* **FASE 3 (custo ~R$ 0):** Bloco 15 (sensor no desktop) \+ Bloco 14 (rotina).
* 🔴 Entre a Fase 1 e a Fase 2, os aparelhos limpos usam a rede antiga **como se fosse pública**: VPN/hotspot para tudo sensível, nada de senhas digitadas em portais pela LAN antiga.

## **🛒 BLOCO 0 — Compras e preparação**

* **Roteador OpenWrt (A e B):** Xiaomi AX3000T (MT7981B). 🔴 Confira modelo \+ revisão na tabela oficial do OpenWrt. Builds 24.10 estáveis atuais já tratam o NAND Winbond — mesmo assim, recovery TFTP antes (Bloco 0.5).
* **Chaves FIDO2:**
  * **Trilha A:** 2× YubiKey 5 NFC (R$ 679–740 cada — KriptoBR/Amazon BR).
  * **Trilha B:** R$ 0 agora — **passkeys de plataforma** nos aparelhos recém-formatados; encomende 2× **Token2** (~US$ 20–30 \+ frete) e cadastre quando chegarem.
* 🆕 **HD externo de evidências (A e B):** USB 3.0, ≥ soma dos discos dos PCs (2 TB na dúvida). Etiquetar **"EVIDÊNCIA — NÃO REUTILIZAR"**. Ver Bloco 8.5.
* 🆕 **2ª placa de rede p/ o desktop-sensor (A e B):** PCIe Gigabit (~R$ 100). Opcional: switch com port mirroring (TP-Link TL-SG105E) se não quiser espelhar pelo roteador.
* **Mini UPS DC:** Trilha A: Marsriva KP3. **Trilha B: adiar.**
* **ONT standalone:** não comprar (as duas trilhas).
* Num dispositivo **EXTERNO E 100% LIMPO**, preparar pendrives: imagem OpenWrt estável do modelo exato (`firmware-selector.openwrt.org`), ISO oficial do Windows, Live USB Linux (Ubuntu/Mint), ISO do Linux do desktop (Ubuntu 24.04 LTS ou Debian 12 — Bloco 15). Conferir **sha256**.

## **🧪 BLOCO 0.5 — ENSAIO A SECO (mantido da V16, com Winbond atualizado)**

* Flash do OpenWrt com o roteador **fora da rede principal**.
* 🔴 **Recovery TFTP pronto e testado ANTES de flashar** (PC 192.168.31.100/24 \+ TFTP). O fix Winbond está no ramo oficial, mas o recovery continua pré-requisito travado. ImmortalWrt segue como plano B.
* Pratique: Trilha A → VLANs (4), firewall, mDNS, blindagem, DNS forçado. Trilha B → VLANs (2), blindagem, DNS forçado (sem mDNS).
* Pesquisas de dúvida pelo **celular no 4G/5G**.
* 🔴 Re-flash limpo (ou reset) do roteador de ensaio antes do uso definitivo.

## **🔌 BLOCO 1 — Airgap** *(inalterado — V16)*

* Desconectar a fibra; desativar Wi-Fi de todos os dispositivos.

## **🔑 BLOCO 2 — Extração de identidade GPON** *(inalterado — só trilha avançada 3B; pular nas trilhas A e B)*

## **🌐 BLOCO 3 — WAN: HGU da Vivo em Modo Bridge** *(inalterado — V16; rota principal nas duas trilhas)*

* Wi-Fi da HGU desligado → WAN/GPON em Bridge → LAN1 da HGU → porta WAN do AX3000T. PPPoE/VLAN 10/firewall ficam no OpenWrt.
* **3B (ONT standalone):** manter como está na V16 — **não fazer**.

## **⚙️ BLOCO 4 — Flashing e WAN do OpenWrt** *(inalterado — V16)*

* Flash de SO limpo (Live USB), recovery no lugar → LuCI 192.168.1.1 → VLAN 10 → PPPoE `cliente@cliente`/`cliente`, MTU 1492 → flow offloading → testar.

## **🧱 BLOCO 5 — Segmentação (VLANs)**

**TRILHA A — 4 VLANs (inalterado da V16):** 20 WORK-DEV / 30 HOME-MAIN (gestão) / 40 HOME-IOT / 50 GUEST-WIFI, com as regras de DHCP/DNS das zonas restritas (Anexo 2D).

**TRILHA B — 2 VLANs (🆕 Anexo Parte 4):**

| VLAN | Nome | Regra |
| :---- | :---- | :---- |
| **20** | WORK-DEV | REJECT total ao tráfego local. Só Internet. |
| **30** | HOME-MAIN | Todo o resto (pessoal, IoT, TV) \+ gestão do roteador. |

* O objetivo nº 1 — **isolar a máquina de trabalho de todo o resto** — fica 100% atendido. IoT junto do pessoal é o tradeoff aceito; migre para a Trilha A quando a base estiver estável.
* 🔴 Gestão pela VLAN 30; esteja na porta untagged dela antes de aplicar (anti-lockout, igual à V16).

## **📡 BLOCO 6 — mDNS Repeater** — *Trilha A: inalterado (refletir só 30↔40). Trilha B: **PULAR** (uma VLAN doméstica só; nada a refletir).*

## **🛡️ BLOCO 5.5 — Blindagem do plano de gestão** *(inalterado — V16; obrigatório nas duas trilhas)*

* Senha root forte; SSH só por chave e só na vlan30; LuCI só na vlan30; zero admin pela WAN; WPA3-SAE\+PMF; WPS off; PSK único por SSID; uPnP off.

## **🔎 BLOCO 6.5 — Controle de DNS/saída** *(inalterado — V16; obrigatório nas duas trilhas)*

* Resolvedor no roteador (dnsmasq ou AdGuard Home \+ DoT/DoH upstream, ex. Quad9), redirect da porta 53 por zona, bloqueio da 853.

## **🔋 BLOCO 7 — Energia** — *Trilha A: inalterado. Trilha B: adiado (comprar depois, se quiser autonomia).*

## **🧪 BLOCO 8 — Teste de isolamento** *(V16, ajustado por trilha)*

* **Trilha A:** todos os testes da V16 (40↛20, 30→40 ok, 50 restrito, mDNS invisível p/ 20/50, LuCI/SSH só da 30, DNS forçado).
* **Trilha B:** da VLAN 20, ping/acesso a aparelho da 30 → **tem que FALHAR**; da 30, LuCI abre; da 20, LuCI/SSH → **FALHA**; teste do DNS forçado (cliente com 1.1.1.1 fixo continua respondido pelo roteador).
* 💾 **1º backup** da config (cifrado, fora do roteador) — igual V16.

## **🧾 BLOCO 8.5 — PRESERVAÇÃO DE EVIDÊNCIAS (🆕 — antes de qualquer wipe; as duas trilhas)**

> O Bloco 9 destrói evidência. Este bloco a congela. Pode ser antecipado (não depende da rede nova). Procedimento completo no **Anexo Parte 5**.

* **PCs:** boot pelo Live USB limpo → imagem completa do disco (`dd | zstd`) para o HD de evidências → `sha256sum` → nota com data/serial. **Nunca** imagear de dentro do Windows. BitLocker: salvar a chave de recuperação junto.
* **Android (S23 Ultra):** sem root não há imagem física — coleta lógica: **AndroidQF \+ MVT**, `adb bugreport`, exports/screenshots do Auto Blocker e Intrusion Logging, prints de admin de dispositivo/acessibilidade/permissões.
* Conferir hashes → HD **offline**, nunca mais em máquina suja.
* ⚖️ Para peso judicial pleno no Brasil o padrão é perícia formal com cadeia de custódia; autocoleta vale para análise própria e registro. Se houver chance de judicialização, fale com advogado **antes** do wipe.

🚧 **PONTO DE VIRADA:** evidências guardadas \+ rede pronta (ou Fase 1 do Bloco 0.7). Só agora endpoints e contas.

## **🧹 BLOCO 9 — Sanitização dos endpoints** *(inalterado — V16)*

* Reinstalação limpa do Windows (excluir TODAS as partições); Secure Boot \+ senha UEFI; reflash de BIOS segue **opcional/avançado**; factory reset do Android via recovery; reset da Tapo e da TV.
* 🆕 **Desktop 2016:** recebe **Linux** (não Windows) — vira o sensor/servidor de IA. Ver Bloco 15.

## **🥇 BLOCO 10 — E-mail principal** *(V16, com alternativa de custo)*

* Senha nova única \+ **2FA resistente a phishing**: Trilha A → 2× YubiKey. **Trilha B → passkeys de plataforma agora \+ Token2 quando chegarem** (mesma propriedade FIDO2 anti-phishing; a chave física adiciona independência do aparelho).
* Encerrar sessões, apagar regras de encaminhamento estranhas 🔴, revogar OAuth desconhecidos, revisar dispositivos. Desativar SMS onde possível.

## **🔐 BLOCO 11 — Gerenciador de senhas** *(inalterado — V16; proteger o cofre com FIDO2/passkey)*

## **🏦 BLOCO 12 — Demais contas (ordem por dano)** *(inalterado — V16: banco → Microsoft/Azure → GitHub \[regerar SSH/PAT\] → nuvem → sociais)*

## **☁️ BLOCO 13 — Arquivos na nuvem** *(inalterado — V16)*

## **🔁 BLOCO 14 — Rotina e reincidência** *(inalterado — V16: backups cifrados, logs de DNS, attended-sysupgrade, acesso remoto só por WireGuard)*

## **🖥️ BLOCO 15 — SENSOR FORA-DE-BANDA no desktop 2016 (🆕 — substitui a compra do N100)**

> Detalhe completo (SO, stack, espelhamento, VM Windows, limites de IA) no **Anexo Parte 6**.

* **Pré-requisito:** o desktop passou pelo wipe (Bloco 9) — um sensor não confiável é pior que nenhum.
* **SO:** **Ubuntu 24.04 LTS ou Debian 12** (host Linux). Windows 11, se necessário, **só como VM** (KVM/QEMU \+ swtpm) — nunca acesso da VM à NIC de captura.
* **Stack recomendada (solo):** Suricata \+ Zeek \+ EveBox em Debian/Ubuntu (roda folgado em 16 GB). Security Onion 2.4: Eval cabe em 16 GB; Standalone só após upgrade p/ ≥24 GB.
* **Captura:** NIC dedicada **sem IP** (promíscua) recebendo espelhamento — via `tc/mirred` no OpenWrt ou porta mirror do TL-SG105E. Gestão só pela VLAN 30.
* **Papel duplo (sensor \+ IA):** aceitável — serviços de IA escutando **só na VLAN 30**; carga pesada de GPU/CPU pode derrubar pacotes da captura (não renderize durante janela de coleta importante).
* **Energia/custo:** ~60–100 W ocioso ≈ R$ 40–70/mês 24/7. Trilha B: ligar só em janelas de coleta. Se um dia virar 24/7 permanente, aí sim o N100 (~10 W) se paga.
* **IA no Pascal (GTX 9xx/10xx):** driver NVIDIA fixado no ramo **580** (último com suporte); **PyTorch ≤2.7/cu126**; alternativas llama.cpp/ONNX. Não investir além da RAM.

> Sempre **VLAN 20 \= trabalho**, **VLAN 30 \= casa/gestão** — nas duas trilhas.
