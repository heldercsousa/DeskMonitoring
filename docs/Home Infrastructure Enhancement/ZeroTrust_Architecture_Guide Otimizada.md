# **Documento de Arquitetura de Rede "Zero-Trust" Otimizada**

**Alvo:** Isolamento Crítico de Canais de Trabalho e Resiliência Elétrica Doméstica

## **1\. Análise Estratégica do Cenário Otimizado**

A transição da arquitetura anterior baseada em hardware empresarial dedicado para esta abordagem consolidada baseada em **OpenWrt** traz impactos significativos na relação custo-benefício.

### **Matriz de Avaliação Técnica**

| Critério | Arquitetura Consolidada (OpenWrt) | Implicação Prática |
| :---- | :---- | :---- |
| **Custo Estimado** | R$ 450 \- R$ 650 (Total) | Redução de aproximadamente 75% em relação ao cenário anterior. |
| **Pegada Física** | Mínima (2 dispositivos suspensos por DC UPS) | Elimina a necessidade de um rack ou espaço dedicado para Mini PC. |
| **Resiliência Elétrica** | **Altíssima (4 a 6 horas)** | A eliminação de inversores AC estende massivamente a autonomia da bateria durante quedas de energia. |
| **Proteção Lateral** | Total via Regras de Firewall e VLANs | Garante que o isolamento do canal de trabalho permaneça inviolável, bloqueando ataques de dispositivos IoT comprometidos. |
| **Ponto de Atenção** | Capacidade de Processamento | Não suporta Inspeção Profunda de Pacotes (DPI) em tempo real a nível de assinatura de malware. |

## **2\. Inventário Técnico de Hardware (Mercado Brasileiro)**

Para operacionalizar esta rede de forma autônoma em relação à operadora Vivo, será necessária a aquisição dos seguintes componentes estratégicos:

* **Roteador Principal (All-in-One Firewall):** TP-Link Archer C6 (V3 ou V4) ou Xiaomi AX3200 (homologados e compatíveis com firmware OpenWrt estável).  
* **ONT Standalone (Conversor de Mídia):** TP-Link XZ000-G3 (Requisito: possuir porta SC/APC verde para conexão direta da fibra).  
* **Nobreak DC (Mini UPS):** Marsriva KP3 ou Knup KP-TC44 (Requisito Crítico: modelo multi-tensão com saídas de 9V e 12V simultâneas).

## **3\. Passo a Passo de Execução e Implantação**

### **Fase 1: Isolamento Físico e Sanitização ("Airgap")**

1. **Corte o Link Externo:** Desconecte imediatamente o cabo de fibra ótica verde do roteador atual da Vivo. Desative os adaptadores Wi-Fi de todos os dispositivos.  
2. **Limpeza de Endpoints:** Refaça a instalação do Sistema Operacional do seu notebook de trabalho utilizando uma mídia USB limpa (que deve ser gerada em um equipamento sabidamente não contaminado). É imperativo deletar completamente a tabela de partições antiga durante a instalação do Windows.  
3. **Wipe de Dispositivos Periféricos:** Realize o reset físico (Factory Reset) na câmera Tapo C100 e na Smart TV através das opções de hardware/menus internos de fábrica.

### **Fase 2: Configuração da Borda e Clonagem de Identidade**

1. **Extração de Parâmetros de Autenticação:** Acesse o roteador Vivo antigo (offline via cabo ethernet) e anote o **GPON Serial Number (SN)** e o **SLID / GPON Password** na seção de configurações de WAN óptica.  
2. **Substituição do Hardware Comprometido:** Remova permanentemente o roteador da Vivo. Conecte a nova ONT TP-Link XZ000-G3 diretamente ao seu computador limpo para configuração inicial.  
3. **Mascaramento de Identidade de Borda:** Na interface web da ONT TP-Link, insira o GPON SN e SLID extraídos. Salve as modificações, conecte o cabo de fibra verde nela e aguarde a luz "PON" estabilizar (confirmação visual de que a central da Vivo reconheceu o equipamento).

### **Fase 3: Segmentação Lógica e Firewall no OpenWrt**

1. **Substituição do Firmware (Flashing):** Instale a imagem estável do OpenWrt no novo roteador (TP-Link ou Xiaomi) seguindo o guia oficial do projeto para o chipset específico.  
2. **Autenticação de Provedor (WAN):** Conecte a ONT à porta WAN do roteador OpenWrt. Configure a conexão via PPPoE (cliente@cliente / cliente) e habilite a marcação de rede VLAN ID 10 para estabelecer o tráfego com a operadora.  
3. **Estruturação de Zonas Isoladas (VLANs e SSIDs):**  
   * **VLAN 20 (WORK-DEV):** Rede dedicada para as máquinas de desenvolvimento e DevOps. No firewall (\`/etc/config/firewall\`), configure com política **REJECT** total para tráfego local (Inbound/Outbound de outras zonas), permitindo apenas tráfego para a Internet (WAN).  
   * **VLAN 30 (HOME-MAIN):** Rede designada para dispositivos móveis e entretenimento pessoal.  
   * **VLAN 40 (HOME-IOT):** Rede de isolamento para a câmera Tapo C100 e Smart TV (dispositivos de alto risco).  
4. **Interconectividade Segura (mDNS Repeater):** Para permitir que seu celular (na VLAN 30\) envie comandos para a TV e Câmera (na VLAN 40\) sem quebrar o isolamento da zona de trabalho, instale e configure o pacote umdns ou avahi-daemon no OpenWrt para refletir protocolos de descoberta de rede especificamente e apenas entre as zonas 30 e 40\.

### **Fase 4: Integração Energética Centralizada**

1. Conecte o dispositivo Mini UPS à sua rede elétrica convencional (220V).  
2. Ligue a saída DC de voltagem correspondente (geralmente 9V ou 12V) diretamente na alimentação da nova ONT TP-Link utilizando os cabos fornecidos.  
3. Ligue a saída DC de 12V do Mini UPS diretamente na entrada de alimentação do roteador OpenWrt recém-configurado.

## **4\. Operação e Manutenibilidade**

Nesta arquitetura consolidada, a responsabilidade de manter as barreiras de software passa a ser interna. Realize verificações periódicas nas tabelas de tráfego do OpenWrt (LuCI) para auditar comportamentos anômalos. Faça o backup (exportação XML) das regras de firewall logo após a validação inicial do isolamento, assegurando rápida recuperação em caso de falha de hardware futuro.