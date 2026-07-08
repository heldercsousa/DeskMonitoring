# Plano de Arquitetura Zero-Trust Otimizada (V2)

**Alvo:** Isolamento Crítico de Canais de Trabalho e Resiliência Elétrica Doméstica

---

## 1. Análise Estratégica do Cenário Otimizado

A transição da arquitetura baseada em hardware empresarial para esta abordagem consolidada (OpenWrt) traz impactos significativos na relação custo-benefício.

| Critério | Arquitetura Consolidada (OpenWrt) | Implicação Prática |
| :--- | :--- | :--- |
| **Custo Estimado** | R$ 450 - R$ 650 (Total) | Redução de aprox. 75% em relação ao cenário anterior. |
| **Pegada Física** | Mínima (2 dispositivos no UPS) | Elimina a necessidade de rack ou espaço dedicado. |
| **Resiliência Elétrica** | **Altíssima (4 a 6 horas)** | Bateria DC nativa estende massivamente a autonomia. |
| **Proteção Lateral** | Total via Regras de Firewall e VLANs | Garante isolamento inviolável do canal de trabalho. |
| **Ponto de Atenção** | Capacidade de Processamento (CPU) | Roteadores básicos podem gargalar em planos > 400 Mbps. |

---

## 2. Inventário Técnico de Hardware (Mercado Brasileiro)

*   **Roteador Principal (All-in-One Firewall):** 
    * Planos até 400 Mbps: TP-Link Archer C6 (V3/V4) ou Xiaomi AX3200.
    * Planos Gigabit (>400 Mbps): Belkin RT3200 ou Linksys E8450 (processadores mais potentes).
*   **ONT Standalone (Conversor de Mídia):** TP-Link XZ000-G3 (Porta SC/APC verde).
*   **Nobreak DC (Mini UPS):** Marsriva KP3 ou Knup KP-TC44 (Requisito: multi-tensão com 9V e 12V simultâneas).

---

## 3. Passo a Passo de Execução e Implantação

### Fase 1: Preparação Segura e Isolamento Físico
1.  **Download Seguro (Vetor Limpo):** Antes de desconectar a rede atual, utilize um dispositivo limpo na rede celular 4G/5G para baixar a imagem do OpenWrt correspondente e a ISO limpa do Windows.
2.  **Corte o Link Externo:** Desconecte o cabo de fibra verde do roteador atual da Vivo. Desative os adaptadores Wi-Fi de todos os dispositivos.
3.  **Limpeza de Endpoints:** Refaça a instalação do notebook deletando a tabela de partições, e realize o reset físico (Factory Reset) na câmera Tapo e Smart TV.

### Fase 2: Extração de Identidade e Configuração de Borda
1.  **Extração Completa de Parâmetros:** Acesse o roteador Vivo antigo (offline via cabo). Anote o **GPON Serial Number (SN)**, o **SLID / GPON Password**, e o **Endereço MAC da porta WAN**.
2.  **Mascaramento na ONT:** Remova o roteador da Vivo. Na ONT TP-Link XZ000-G3, insira o GPON SN e SLID. Conecte a fibra ótica e aguarde a luz "PON" estabilizar.

### Fase 3: Segmentação Lógica e Firewall no OpenWrt
1.  **Flashing Seguro:** Instale o OpenWrt no novo roteador utilizando o arquivo limpo baixado na Fase 1.
2.  **Autenticação e Clonagem de MAC (WAN):** Conecte a ONT à porta WAN do roteador OpenWrt. Configure PPPoE (cliente@cliente / cliente), ative a **VLAN ID 10**, e no campo "Override MAC address", insira o MAC Address extraído do roteador da Vivo.
3.  **Estruturação de Zonas Isoladas (VLANs e SSIDs):**
    *   **VLAN 20 (WORK-DEV):** Rede dedicada para desenvolvimento. Política REJECT total para tráfego local. Acesso apenas à Internet.
    *   **VLAN 30 (HOME-MAIN):** Rede para dispositivos móveis pessoais.
    *   **VLAN 40 (HOME-IOT):** Isolamento para câmera Tapo e Smart TV. Acesso restrito à internet.
    *   **VLAN 50 (GUEST-WIFI):** Visitantes. Acesso permitido apenas portas 80/443. Ative a opção "Client Isolation".
4.  **Interconectividade Segura (mDNS Repeater):** Instale o pacote `umdns` ou `avahi-daemon`. Configure para refletir protocolos estritamente entre as VLANs 30 e 40, permitindo controle da TV e Câmera sem expor a VLAN 20.

### Fase 4: Integração Energética Centralizada
1.  Ligue o Mini UPS à rede 220V.
2.  Conecte a saída DC correspondente à nova ONT TP-Link.
3.  Conecte a saída DC de 12V ao roteador OpenWrt.

---

## 4. Operação e Manutenibilidade
Audite periodicamente as tabelas de tráfego do OpenWrt (LuCI). Faça backup em XML das regras de firewall.
