# **Módulo de Alteração: Arquitetura Zero Trust (Opção Enxuta)**

**Status do Módulo:** Anexo Estrutural  
**Baseline de Referência:** V8 (Congelada)  
**Escopo:** Transição da arquitetura de força bruta (Inspeção Profunda L7) para a arquitetura de sobrevivência (Isolamento L3/L4 e Eficiência Energética DC).

## **1\. Alterações Estruturais e Remoções**

Este módulo revoga as implementações de hardware complexo que conflitam com a resiliência energética do ambiente.

* **Descontinuado:** Servidor de Borda Empresarial / Mini PC (DPI/IPS).  
  * *Motivo:* Alta carga de processamento gera esgotamento rápido de energia (AC) e cria um ponto único de falha estrutural.  
* **Descontinuado:** Nobreak AC (Inversor) para a infraestrutura crítica.  
  * *Motivo:* Perda de eficiência na conversão de energia.

## **2\. A Nova Arquitetura de Borda e Energia (Sobrevivência)**

O núcleo da rede é redesenhado para garantir de 4 a 6 horas de disponibilidade absoluta durante blecautes, operando em circuito fechado de corrente contínua.

* **Mini UPS DC:** Fonte de energia central e ininterrupta.  
* **ONT (TP-Link XZ000-G3):** Substitui o modem de operadora. Alimentada diretamente na saída 9V/12V do Mini UPS.  
* **Roteador Principal (OpenWrt):** Alimentado pela saída 12V do Mini UPS.

## **3\. Configurações de Acesso e Isolamento (VLANs)**

A segurança L7 é substituída pelo rigoroso isolamento de broadcast e regras de acesso lateral. O roteador assume a discagem PPPoE e a clonagem do MAC Address na porta WAN.

* **VLAN 20 (WORK-DEV):** Rede crítica.  
  * *Regra de Firewall:* REJECT absoluto para Inbound/Outbound local. Comunicação bidirecional permitida apenas para a WAN (Internet).  
* **VLAN 30 (HOME-MAIN):** Rede pessoal (smartphones, tablets). Livre navegação.  
* **VLAN 40 (HOME-IOT):** Dispositivos de baixa confiança (Câmeras, Smart TVs).  
  * *Regra de Firewall:* Isolada de outras VLANs.  
* **VLAN 50 (GUEST-WIFI):** Rede efêmera de visitantes.  
  * *Regra de Firewall:* Navegação restrita às portas 80/443. Isolamento de Clientes (Client Isolation) ativado na interface wireless, impedindo que dispositivos na mesma rede se enxerguem.

## **4\. Integração Controlada (mDNS)**

Para permitir a usabilidade sem quebrar o *Zero Trust*:

* Implementação do pacote umdns ou avahi-daemon no OpenWrt.  
* Reflexão de pacotes de descoberta multicast (Chromecast, controle de TV) configurada de forma unilateral: permitida **apenas** entre a VLAN 30 (HOME-MAIN) e a VLAN 40 (HOME-IOT).  
* A VLAN 20 (WORK-DEV) permanece completamente invisível a esse tráfego de descoberta.

## **5\. Auditoria e Manutenção**

* Backup local e exportação (XML/Tarball) das configurações do LuCI a cada alteração de política.  
* Monitoramento passivo pelo *syslog* do OpenWrt, enviando alertas em caso de quedas constantes do túnel PPPoE.