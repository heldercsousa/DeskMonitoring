# **Documento de Arquitetura de Rede "Zero-Trust" Otimizada (V2)**

**Alvo:** Isolamento Crítico de Canais de Trabalho e Resiliência Elétrica Doméstica

## **1\. Análise Estratégica do Cenário Otimizado**

A transição da arquitetura baseada em hardware empresarial para esta abordagem consolidada (OpenWrt) traz impactos significativos na relação custo-benefício.

| Critério | Arquitetura Consolidada (OpenWrt) | Implicação Prática |
| :---- | :---- | :---- |
| Custo Estimado | R$ 450 \- R$ 650 (Total) | Redução de aproximadamente 75% em relação ao cenário anterior. |
| Pegada Física | Mínima (2 dispositivos suspensos por DC UPS) | Elimina a necessidade de um rack ou espaço dedicado. |
| Resiliência Elétrica | Altíssima (4 a 6 horas) | A eliminação de inversores AC estende massivamente a autonomia da bateria durante quedas de energia. |
| Proteção Lateral | Total via Regras de Firewall e VLANs | Garante que o isolamento do canal de trabalho permaneça inviolável. |
| Ponto de Atenção | Capacidade de Processamento (CPU) | Não suporta DPI em tempo real. Roteadores básicos podem limitar conexões superiores a 400 Mbps. |

## **2\. Inventário Técnico de Hardware (Mercado Brasileiro)**

* **Roteador Principal (All-in-One Firewall):** Para planos até 400 Mbps: TP-Link Archer C6 (V3/V4) ou Xiaomi AX3200. Para planos Gigabit (\>400 Mbps): Belkin RT3200 ou Linksys E8450 (processadores dual-core mais potentes). Requer suporte oficial ao OpenWrt.  
* **ONT Standalone (Conversor de Mídia):** TP-Link XZ000-G3 (Requisito: possuir porta SC/APC verde para fibra).  
* **Nobreak DC (Mini UPS):** Marsriva KP3 ou Knup KP-TC44 (Requisito Crítico: modelo multi-tensão com saídas de 9V e 12V simultâneas).

## **3\. Passo a Passo de Execução e Implantação**

### **Fase 1: Preparação Segura e Isolamento Físico**

1. **Download Seguro (Vetor Limpo):** Antes de desconectar a rede atual, utilize um dispositivo sabidamente limpo (ou seu celular na rede celular 4G/5G) para baixar a imagem do OpenWrt correspondente ao seu roteador e a ISO oficial do Windows. Não use a rede comprometida para isso.  
2. **Corte o Link Externo:** Desconecte imediatamente o cabo de fibra ótica verde do roteador atual da Vivo. Desative os adaptadores Wi-Fi de todos os dispositivos.  
3. **Limpeza de Endpoints:** Refaça a instalação do Sistema Operacional do seu notebook deletando a tabela de partições, e realize o reset físico (Factory Reset) na câmera Tapo C100 e na Smart TV.

### **Fase 2: Extração de Identidade e Configuração de Borda**

1. **Extração Completa de Parâmetros:** Acesse o roteador Vivo antigo (offline via cabo ethernet). Na seção de WAN/GPON, anote 3 itens cruciais: **GPON Serial Number (SN)**, o **SLID / GPON Password**, e o **Endereço MAC da porta WAN** (geralmente impresso na etiqueta).  
2. **Mascaramento na ONT:** Remova permanentemente o roteador da Vivo. Na interface da ONT TP-Link XZ000-G3, insira o GPON SN e SLID. Conecte a fibra ótica e aguarde a luz "PON" estabilizar.

### **Fase 3: Segmentação Lógica e Firewall no OpenWrt**

1. **Flashing Seguro:** Instale o OpenWrt no novo roteador utilizando o arquivo limpo baixado na Fase 1\.  
2. **Autenticação e Clonagem de MAC (WAN):** Conecte a ONT à porta WAN do roteador OpenWrt. Configure a conexão PPPoE (cliente@cliente / cliente), ative a **VLAN ID 10**, e no campo "Override MAC address", insira o MAC Address extraído do roteador da Vivo.  
3. **Estruturação de Zonas Isoladas (VLANs e SSIDs):**  
   * **VLAN 20 (WORK-DEV):** Rede dedicada para desenvolvimento. Política REJECT total para tráfego local (Inbound/Outbound de outras zonas). Acesso apenas à Internet.  
   * **VLAN 30 (HOME-MAIN):** Rede para dispositivos móveis pessoais e entretenimento seguro.  
   * **VLAN 40 (HOME-IOT):** Rede de isolamento para a câmera Tapo C100 e Smart TV. Acesso restrito à internet.  
   * **VLAN 50 (GUEST-WIFI):** Rede para visitantes. Acesso permitido apenas portas 80/443 (Internet). Habilite obrigatoriamente a opção "Client Isolation" no Wi-Fi.  
4. **Interconectividade Segura (mDNS Repeater):** Instale o pacote umdns ou avahi-daemon. Configure para refletir protocolos de descoberta estritamente entre as VLANs 30 e 40, permitindo que seu celular controle a TV e Câmera sem expor a zona de trabalho (VLAN 20).

### **Fase 4: Integração Energética Centralizada**

1. Ligue o Mini UPS à rede 220V.  
2. Conecte a saída DC correspondente (9V/12V) à nova ONT TP-Link.  
3. Conecte a saída DC de 12V ao roteador OpenWrt.

## **4\. Operação e Manutenibilidade**

Audite periodicamente as tabelas de tráfego do OpenWrt (LuCI). Realize o backup (exportação XML) das regras de firewall logo após a validação do isolamento. Mantenha os pacotes atualizados via gerenciador interno.