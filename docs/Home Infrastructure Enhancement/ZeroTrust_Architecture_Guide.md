# Plano de Ação: Arquitetura de Rede "Zero Trust" e Remediação Total

**Documento Estratégico de Implementação**
**Objetivo:** Erradicação de comprometimento persistente de rede (incluindo possíveis ameaças a nível de firmware/ISP) e implementação de uma arquitetura segmentada baseada no princípio de *Zero Trust* (Confiança Zero).

---

## 1. Análise Crítica e Avaliação de Riscos (Conforme suas diretrizes estratégicas)

Antes de iniciarmos o passo a passo, é crucial avaliar os riscos e os trade-offs dessa nova arquitetura:

*   **Ponto Forte:** Elimina completamente o hardware da Vivo e protocolos de gerenciamento remoto (TR-069) da sua camada lógica. A segmentação (VLANs) garante que se a sua Câmera Tapo for invadida, o ataque "morre" nela, sem alcançar seu notebook de trabalho.
*   **Ponto Fraco:** Complexidade de gerenciamento. Diferente de um roteador de operadora "Plug and Play", você será o seu próprio SysAdmin. Atualizações do firewall, regras de portas e manutenção do mDNS (para a TV e Câmera) dependerão da sua gestão.
*   **Risco Potencial:** Extração falha do SLID/GPON. Se a Vivo atualizar o firmware do roteador atual antes de você conseguir extrair a senha do GPON, você pode ter dificuldades para autenticar a nova ONT. *Ação mitigadora: Faça a extração das credenciais offline (cabo desconectado da fibra) o quanto antes.*

---

## 2. Lista de Aquisições (Hardware Seguro)

Para montar essa topologia no Brasil, você precisará dos seguintes hardwares:

1.  **ONT Programável (A "Ponte"):** TP-Link XZ000-G3 ou VSOL V2802RH (Aprox. R$ 150). Serve apenas para converter luz em cabo de rede.
2.  **Appliance de Firewall (O "Cérebro"):** Mini PC Fanless com processador Intel N100 e 4x portas de rede Intel i226 2.5GbE. Instale o **pfSense** ou **OPNsense** nele. (Busque no Mercado Livre ou AliExpress, Aprox. R$ 1.500 - R$ 2.000).
3.  **Access Point (AP) com Suporte a VLAN (O "Rádio Wi-Fi"):** TP-Link Omada EAP225/EAP245 ou Ubiquiti UniFi. Roteadores domésticos comuns não suportam múltiplas redes Wi-Fi apontando para VLANs diferentes. O AP fará a transmissão isolada do Work, Guest, e IoT.

---

## 3. Fase 1: Extração e Isolamento (O "Airgap")

*Atenção: Não conecte nenhum hardware novo ainda.*

1.  **Desconecte a Fibra:** Retire o cabo verde (fibra) do seu roteador atual da Vivo. A partir de agora, a casa está offline.
2.  **Desligue o Wi-Fi:** Desative a rede sem fio em todos os celulares, TVs e notebooks afetados.
3.  **Acesse o Roteador da Vivo (Offline):** Conecte seu notebook recém-formatado via cabo de rede ao roteador da Vivo.
4.  **Extraia as Credenciais GPON:**
    *   Acesse `192.168.15.1` (ou o IP padrão do seu modelo).
    *   Navegue até as configurações de WAN/GPON/Óptica.
    *   Copie o **SLID** (Senha do Assinante/GPON Password) e o **GPON SN** (Serial Number, geralmente 4 letras da fabricante e 8 caracteres hexadecimais). *Guarde isso em um arquivo txt seguro.*
5.  **Descarte:** Desligue o roteador da Vivo e guarde-o na caixa. Ele não volta mais para a rede.

---

## 4. Fase 2: Configuração da Fronteira (Edge)

1.  **A Nova ONT:** Ligue a TP-Link XZ000-G3 no seu notebook via cabo de rede. Acesse a interface web dela.
2.  **Clonagem:** Insira o **GPON SN** e o **SLID** que você extraiu da Vivo. Salve as configurações.
3.  **Conexão Física:** Agora, plugue o cabo de fibra ótica verde na nova ONT. Ela deve acender a luz "PON" indicando que a Vivo aceitou o equipamento.
4.  **Conexão ao Firewall:** Ligue um cabo de rede da porta LAN da ONT para a porta WAN (eth0) do seu Mini PC rodando pfSense/OPNsense.
5.  **Autenticação PPPoE no pfSense:** Acesse o pfSense. Na interface WAN, configure o tipo para **PPPoE** (Usuário: `cliente@cliente` / Senha: `cliente`). Marque a opção para "VLAN 10" na WAN (a Vivo usa a VLAN 10 para o tráfego de internet).

---

## 5. Fase 3: Segmentação Lógica (VLANs e Wi-Fi)

No pfSense, você criará as interfaces lógicas (VLANs) que serão transmitidas pelo seu Access Point Omada/UniFi.

### Arquitetura de Redes (SSIDs):

#### 1. VLAN 20: DEV-WORK (Rede de Trabalho)
*   **Propósito:** Ambiente restrito e ultrasseguro.
*   **Regras de Firewall:** Pode acessar a internet (Outbound). **Bloqueio total (Drop)** de qualquer conexão vinda da VLAN 30, 40 ou 50 (Inbound). Se a câmera for infectada, o pacote morre no firewall antes de ver esta rede.

#### 2. VLAN 30: HOME-GENERAL (Uso Geral)
*   **Propósito:** Seu celular pessoal, notebook de entretenimento.
*   **Regras de Firewall:** Acesso à internet livre. Tem permissão para *iniciar* conexões com a VLAN 40 (IoT), mas a VLAN 40 não pode iniciar conexões com ela.

#### 3. VLAN 40: HOME-IOT (Tapo Cam & TV)
*   **Propósito:** Isolamento de aparelhos burros/vulneráveis.
*   **Regras de Firewall:** Acesso à internet altamente restrito (liberar apenas as portas necessárias para a nuvem da Tapo ou Netflix da TV). Bloqueio total de acesso local às VLANs 20 e 30.
*   **A Solução para o Controle Remoto (O "Pulo do Gato"):** Aparelhos como Smart TVs e Chromecasts usam "mDNS/Bonjour" para ser descobertos pelo celular. Como o celular (VLAN 30) e a TV (VLAN 40) estão em redes separadas, eles não se enxergam.
    *   **Ação:** No pfSense, instale o pacote **Avahi (mDNS Repeater)**.
    *   **Configuração:** Ative o Avahi para escutar na VLAN 30 e VLAN 40. Isso permite que seu celular na VLAN Geral encontre a TV na VLAN IoT, envie o comando através do firewall, e o firewall encaminhe de forma segura, mantendo as redes isoladas contra malwares invasivos.

#### 4. VLAN 50: GUEST-WIFI (Visitantes)
*   **Propósito:** Amigos e familiares.
*   **Regras de Firewall:** Acesso APENAS à porta 80 e 443 (Internet). "Client Isolation" ativado no Access Point (um visitante não consegue pingar o celular de outro visitante).

---

## 6. Fase 4: O "Sanitize" Final dos Endpoints

Com a fortaleza construída, é hora de limpar os dispositivos contaminados antes de conectá-los.

1.  **Formatando com Segurança (Notebook):**
    *   Crie um pendrive de instalação do Windows usando um PC de um amigo/lan house (um ambiente sabidamente limpo). Não use o seu hardware atual para gerar o pendrive.
    *   Durante a instalação, na tela de partições, **exclua todas as partições existentes** (incluindo as de recuperação "Recovery"). Instale na área não alocada.
2.  **Celular Android:** Hard reset (Wipe Data/Factory Reset) pelo menu de bootloader/recovery do Android.
3.  **Tapo Câmera:** Pressione o botão físico de reset na câmera com um clipe por 10 segundos.

---

## 7. Dia a Dia na Nova Arquitetura

*   Sempre conecte seu ambiente de código/Azure DevOps pela **VLAN 20**.
*   Quando quiser assistir TV ou ver a câmera de dentro de casa, use o celular na **VLAN 30**. O mDNS Repeater (Avahi) garantirá o funcionamento do app da Tapo ou controle da TV sem comprometer a rede.
*   **Manutenção:** O pfSense requer atualizações esporádicas. Configure o backup automático das regras do firewall (XML).

