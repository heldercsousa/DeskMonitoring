#Requires -RunAsAdministrator
# AutoCleanup.ps1
# Limpa processos suspeitos e entradas de registro de localizacao.
# Chamado automaticamente pelo DailySecurityCheck.ps1 ou manualmente.

Add-Type -AssemblyName System.Windows.Forms

$logPath   = "$env:USERPROFILE\Documents\SecurityCheck_Log.txt"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "  LIMPEZA AUTOMATICA DE SEGURANCA" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # [1] Backup do registro
    Write-Host "[1] Criando backup de seguranca..." -ForegroundColor Yellow
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $backupPath  = Join-Path $desktopPath "AutoCleanup_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    $exportKey   = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
    reg export $exportKey $backupPath /y | Out-Null
    Write-Host "  OK Backup: $backupPath" -ForegroundColor Green

    $cleanedItems = 0

    # [2] Matar processos suspeitos
    Write-Host ""
    Write-Host "[2] Verificando processos suspeitos..." -ForegroundColor Yellow

    $suspiciousPatterns = @("AppMonitor", "VEDetector", "VECrashHandler", "CefViewWing")
    $excludePatterns    = @("Mbam", "OneDrive", "Malware", "Windows", "Microsoft")

    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $name         = $_.ProcessName
        $isSuspicious = $false
        $isExcluded   = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $isSuspicious = $true; break } }
        if ($isSuspicious) {
            foreach ($e in $excludePatterns) { if ($name -like "*$e*") { $isExcluded = $true; break } }
        }
        $isSuspicious -and -not $isExcluded
    }

    if ($procs) {
        foreach ($proc in $procs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Host "  OK Encerrado: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor Green
                Add-Content -Path $logPath -Value "$timestamp - CLEANUP: Killed $($proc.ProcessName) PID $($proc.Id)"
                $cleanedItems++
            } catch {
                Write-Host "  ERRO ao encerrar $($proc.ProcessName): $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  Nenhum processo suspeito encontrado." -ForegroundColor Gray
    }

    # [3] Limpar entradas de registro suspeitas
    Write-Host ""
    Write-Host "[3] Verificando registro de localizacao..." -ForegroundColor Yellow

    $locationPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
    $subApps = Get-ChildItem -Path $locationPath -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.PSChildName
        $hit  = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $hit = $true; break } }
        $hit
    }

    if ($subApps) {
        foreach ($entry in $subApps) {
            try {
                Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction Stop
                Write-Host "  OK Removido: $($entry.PSChildName)" -ForegroundColor Green
                Add-Content -Path $logPath -Value "$timestamp - CLEANUP: Removed registry $($entry.PSChildName)"
                $cleanedItems++
            } catch {
                Write-Host "  ERRO ao remover $($entry.PSChildName): $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  Nenhuma entrada suspeita no registro." -ForegroundColor Gray
    }

    # [4] Reiniciar servicos FolderSync se parados
    Write-Host ""
    Write-Host "[4] Verificando servicos FolderSync..." -ForegroundColor Yellow
    foreach ($svcName in @('FolderSyncAuditor', 'FolderSyncWatchdog')) {
        $svc = Get-Service $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            try {
                Start-Service $svcName -ErrorAction Stop
                Write-Host "  OK Reiniciado: $svcName" -ForegroundColor Green
                Add-Content -Path $logPath -Value "$timestamp - CLEANUP: Restarted service $svcName"
                $cleanedItems++
            } catch {
                Write-Host "  ERRO ao reiniciar $svcName: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  OK $svcName esta rodando" -ForegroundColor Gray
        }
    }

    # Resultado
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Cyan
    if ($cleanedItems -gt 0) {
        Write-Host "  LIMPEZA CONCLUIDA: $cleanedItems item(s) tratado(s)" -ForegroundColor Green
    } else {
        Write-Host "  Nada para limpar - sistema ja estava limpo" -ForegroundColor Green
    }
    Write-Host "===========================================" -ForegroundColor Cyan

    Add-Content -Path $logPath -Value "$timestamp - CLEANUP DONE: $cleanedItems items cleaned"

    [System.Windows.Forms.MessageBox]::Show(
        "Limpeza concluida!`n$cleanedItems item(s) tratado(s).`nBackup do registro salvo em:`n$backupPath",
        "Limpeza de Seguranca",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

} catch {
    Write-Host "ERRO GERAL: $_" -ForegroundColor Red
    Add-Content -Path $logPath -Value "$timestamp - CLEANUP ERROR: $_"
}
