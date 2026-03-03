@echo off
:: Local mirror: C:\Users\helde\Repos\Bois -> C:\Sync\Mirror
:: /E    = Copia subdiretórios, incluindo vazios (não deleta no destino)
:: /Z    = Modo restartable (essencial para vídeos se a cópia for interrompida)
:: /R:1  = Apenas 1 tentativa para evitar logs gigantes
:: /W:2  = Espera curta entre tentativas
:: /LOG+ = Append ao log diário rotativo
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set DATE=%%d
robocopy "C:\Users\helde\Repos\Bois" "C:\Sync\Mirror" /E /Z /R:1 /W:2 /LOG+:"C:\Sync\Logs\mirror_%DATE%.log" /NP /NDL /NC /NS