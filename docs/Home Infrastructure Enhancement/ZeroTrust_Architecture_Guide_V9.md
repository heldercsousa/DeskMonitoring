# **Guia de Arquitetura Zero Trust \- Opção Enxuta (Versão 9\)**

Este documento consolida a arquitetura de rede residencial baseada nos princípios de Zero Trust, focando na resiliência operacional através da segmentação estrita e eficiência energética, consolidando a opção "enxuta".

## **1\. Objetivo**

Implementar uma rede altamente disponível, isolando dispositivos IoT e visitantes do ambiente de desenvolvimento, utilizando hardware otimizado e alimentação contínua garantida por Mini UPS.

## **2\. Arquitetura Física e Energética Centralizada**

Para garantir a disponibilidade ("survivability") do núcleo da rede durante quedas de energia:

* **Mini UPS DC:** Conectado à rede 220V, atuando como fonte ininterrupta.  
* **ONT (TP-Link XZ000-G3):** Conectada à saída DC correspondente (9V/12V) do Mini UPS.  
* **Roteador de Borda (OpenWrt):** Conectado à saída DC de 12V do Mini UPS.

## **3\. Configuração Base do Roteador**

1. **Flashing Seguro:** Instale o OpenWrt no roteador utilizando um arquivo de firmware limpo e validado.  
2. **Autenticação e Clonagem de MAC (WAN):** Conecte a ONT à porta WAN. Configure a conexão PPPoE (cliente@cliente / cliente), ative a VLAN ID 10, e insira o MAC Address extraído do equipamento da operadora no campo "Override MAC address".

## **4\. Estruturação de Zonas Isoladas (VLANs e SSIDs)**

A segmentação de rede na camada L3/L4 é o núcleo da proteção desta arquitetura, isolando os vetores de ataque laterais.

| VLAN ID | Nome da Zona | Políticas de Acesso e Restrições |
| :---- | :---- | :---- |
| VLAN 20 | WORK-DEV | Rede crítica para desenvolvimento. Política **REJECT total** para tráfego local (Inbound/Outbound de outras zonas). Acesso restrito apenas à Internet. |
| VLAN 30 | HOME-MAIN | Rede para dispositivos móveis pessoais e entretenimento seguro. |
| VLAN 40 | HOME-IOT | Rede de isolamento para dispositivos vulneráveis (ex: câmera Tapo C100 e Smart TV). Acesso altamente restrito à internet. |
| VLAN 50 | GUEST-WIFI | Rede para visitantes. Acesso permitido apenas portas 80/443 (Internet). Opção **"Client Isolation"** habilitada obrigatoriamente. |

## **5\. Interconectividade e Integração**

* **mDNS Repeater:** Instale o pacote umdns ou avahi-daemon. Configure para refletir protocolos de descoberta estritamente entre as VLANs 30 e 40\. Isso permite que smartphones na rede HOME-MAIN controlem a TV e Câmera na rede HOME-IOT sem expor de forma alguma a zona de trabalho (WORK-DEV).  
* **Filtragem Local:** Uso do roteador OpenWrt na borda fazendo o roteamento primário e bloqueios de DNS (sinkholing) básicos.

## **6\. Operação e Manutenibilidade**

* Audite periodicamente as tabelas de tráfego através da interface do OpenWrt (LuCI).  
* Realize o backup (exportação XML) das regras de firewall imediatamente após a validação do isolamento.  
* Mantenha os pacotes atualizados via gerenciador interno do firmware.