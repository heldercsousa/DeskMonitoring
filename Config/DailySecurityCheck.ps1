# DailySecurityCheck.ps1 - v8
# Sistema de Deteccao de Seguranca com deteccao de acesso remoto e anomalias de rede
# Scheduled task: "FolderSync-DailyCheck" (daily at 09:00, runs as helde)

$logPath   = "C:\Sync\Logs\security\security_check_$(Get-Date -Format 'yyyy-MM-dd').log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Known devices on your network (update if router assigns different IPs)
$knownDevices = @{
    '192.168.0.1'   = 'Router Humax'
    '192.168.0.106' = 'Samsung TV'
    '192.168.0.109' = 'TP-Link C100 Cam'
    '192.168.0.152' = 'This machine (LAP)'
    '192.168.0.206' = 'Samsung S23 Ultra'
}

try {
    $locationPath      = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
    $suspiciousPatterns = @("VE", "AppMonitor", "CefView")

    $excludePatterns = @(
        "Mbam", "OneDrive", "Malware", "Windows", "Microsoft",
        "msedge", "PackageManager", "svchost", "RuntimeBroker",
        "SearchHost", "StartMenuExperienceHost", "ShellExperienceHost",
        "SystemSettings", "Explorer", "Defender", "SecurityHealth",
        "Update", "Store", "Xbox", "Gaming", "Cortana", "ActionsServer",
        "devenv", "VSCode", "Code", "copilot", "git", "node",
        "dotnet", "msbuild", "ServiceHub", "PerfWatson",
        "WindowsPackageManager"
    )

    $issues          = 0
    $alertLines      = @()
    $processDetails  = @()
    $registryProblems = @()

    # -----------------------------------------------------------------------
    # [1] Suspicious processes
    # -----------------------------------------------------------------------
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $name        = $_.ProcessName
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
            $issues++
            $details = @{
                Name    = $proc.ProcessName
                Path    = if ($proc.Path) { $proc.Path } else { "Desconhecido" }
                Company = if ($proc.Company) { $proc.Company } else { "Desconhecida" }
                Signed  = "Nao"
                Signer  = "N/A"
                Risk    = "ALTO"
                Action  = "Considere encerrar e investigar"
            }
            if ($proc.Path -and (Test-Path $proc.Path)) {
                $sig = Get-AuthenticodeSignature -FilePath $proc.Path -ErrorAction SilentlyContinue
                if ($sig -and $sig.Status -eq "Valid") {
                    $details.Signed = "Sim"
                    $details.Signer = $sig.SignerCertificate.Subject -replace "CN=", "" -replace ",.*", ""
                }
            }
            # Risk classification
            $inProgramFiles = $details.Path -like "*Program Files*"
            $knownCompany   = $details.Company -match "Microsoft|Intel|Google|Adobe|NVIDIA|Acer|Realtek|Samsung"
            if ($details.Signed -eq "Sim" -and $inProgramFiles) {
                $details.Risk   = "BAIXO"
                $details.Action = "Adicionar as excecoes se for legitimo"
            } elseif ($details.Signed -eq "Sim" -and -not $inProgramFiles) {
                $details.Risk   = "MEDIO"
                $details.Action = "Verificar caminho e empresa antes de limpar"
            }
            $processDetails += $details
        }
    }

    # -----------------------------------------------------------------------
    # [2] Registry location entries
    # -----------------------------------------------------------------------
    $subApps = Get-ChildItem -Path $locationPath -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.PSChildName
        $hit  = $false
        foreach ($p in $suspiciousPatterns) { if ($name -like "*$p*") { $hit = $true; break } }
        $hit
    }
    if ($subApps) {
        $registryProblems += $subApps
        $issues++
    }

    # -----------------------------------------------------------------------
    # [3] Remote access tools running
    # -----------------------------------------------------------------------
    $remoteTools = @('AnyDesk', 'VNCViewer', 'vncserver', 'ScreenConnect', 'Ammyy', 'RemoteUtilities', 'Rustdesk')
    $foundRemote = @()
    foreach ($tool in $remoteTools) {
        $p = Get-Process $tool -ErrorAction SilentlyContinue
        if ($p) { $foundRemote += "$tool (PID $($p.Id -join ','))"; $issues++ }
    }

    # -----------------------------------------------------------------------
    # [4] Suspicious listening ports
    # -----------------------------------------------------------------------
    $suspiciousPorts = @(4444, 5900, 5901, 1080, 8443, 31337, 12345, 54321, 9999, 6666)
    $foundPorts = @()
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $listening) {
        if ($conn.LocalPort -in $suspiciousPorts) {
            $procName = (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).Name
            $foundPorts += "Port $($conn.LocalPort) - PID $($conn.OwningProcess) ($procName)"
            $issues++
        }
    }

    # -----------------------------------------------------------------------
    # [5] Unknown devices on network (ARP table)
    # -----------------------------------------------------------------------
    $foundUnknown = @()
    try {
        $arpOutput = arp -a 2>$null
        $arpLines  = $arpOutput | Where-Object { $_ -match '^\s+\d+\.\d+\.\d+\.\d+' }
        foreach ($line in $arpLines) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([\w-]+)\s+(\w+)') {
                $ip   = $Matches[1]
                $type = $Matches[3]
                if ($type -eq 'dinamico' -or $type -eq 'dynamic') {
                    if (-not $knownDevices.ContainsKey($ip)) {
                        $foundUnknown += "IP desconhecido: $ip"
                        $issues++
                    }
                }
            }
        }
    } catch {}

    # -----------------------------------------------------------------------
    # [6] FolderSync services status
    # -----------------------------------------------------------------------
    $watchedSvcs  = @('FolderSyncAuditor', 'FolderSyncWatchdog')
    $stoppedSvcs  = @()
    foreach ($svc in $watchedSvcs) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne 'Running') {
            $stoppedSvcs += "$svc ($($s.Status))"
            $issues++
        }
    }

    # -----------------------------------------------------------------------
    # Log result
    # -----------------------------------------------------------------------
    $logLine = "$timestamp  Issues: $issues"
    if ($processDetails.Count  -gt 0) { $logLine += " | Processos: $($processDetails.Name -join ',')" }
    if ($registryProblems.Count -gt 0) { $logLine += " | Registro: $($registryProblems.PSChildName -join ',')" }
    if ($foundRemote.Count     -gt 0) { $logLine += " | RemoteTools: $($foundRemote -join ',')" }
    if ($foundPorts.Count      -gt 0) { $logLine += " | Portas: $($foundPorts -join ',')" }
    if ($foundUnknown.Count    -gt 0) { $logLine += " | DispositivosNovos: $($foundUnknown -join ',')" }
    if ($stoppedSvcs.Count     -gt 0) { $logLine += " | ServicosParados: $($stoppedSvcs -join ',')" }
    Add-Content -LiteralPath $logPath -Value $logLine

    # -----------------------------------------------------------------------
    # Show result (only when running interactively — skip if headless/service)
    # -----------------------------------------------------------------------
    if (-not [Environment]::UserInteractive) {
        # Running non-interactively (scheduled task with -NonInteractive flag)
        # Dialog cannot be shown. Alert is already in the log above.
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    if ($issues -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Sistema seguro! Nenhuma ameaca detectada.`n`nVerificado em: $timestamp",
            "Verificacao de Seguranca",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } else {
        $msg  = "ATENCAO: $issues problema(s) detectado(s)!`n"
        $msg += "Verificado em: $timestamp`n"
        $msg += "-------------------------------------------`n`n"

        if ($processDetails.Count -gt 0) {
            $msg += "PROCESSOS SUSPEITOS:`n"
            foreach ($d in $processDetails) {
                $msg += "  $($d.Name) | Risco: $($d.Risk) | Assinado: $($d.Signed)`n"
                $msg += "  Caminho: $($d.Path)`n"
                $msg += "  Acao: $($d.Action)`n`n"
            }
        }
        if ($registryProblems.Count -gt 0) {
            $msg += "REGISTRO: $($registryProblems.Count) entrada(s) suspeita(s) de localizacao`n"
            foreach ($r in $registryProblems) {
                $msg += "  - $($r.PSChildName)`n"
            }
            $msg += "`n"
        }
        if ($foundRemote.Count -gt 0) {
            $msg += "FERRAMENTAS ACESSO REMOTO ATIVAS:`n"
            $foundRemote | ForEach-Object { $msg += "  - $_`n" }
            $msg += "`n"
        }
        if ($foundPorts.Count -gt 0) {
            $msg += "PORTAS SUSPEITAS ABERTAS:`n"
            $foundPorts | ForEach-Object { $msg += "  - $_`n" }
            $msg += "`n"
        }
        if ($foundUnknown.Count -gt 0) {
            $msg += "DISPOSITIVOS DESCONHECIDOS NA REDE:`n"
            $foundUnknown | ForEach-Object { $msg += "  - $_`n" }
            $msg += "`n"
        }
        if ($stoppedSvcs.Count -gt 0) {
            $msg += "SERVICOS DE SEGURANCA PARADOS:`n"
            $stoppedSvcs | ForEach-Object { $msg += "  - $_`n" }
            $msg += "`n"
        }

        $msg += "-------------------------------------------`n"
        $msg += "Deseja executar LIMPEZA AUTOMATICA?"

        $result = [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Alerta de Seguranca",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $cleanupScript = "C:\Sync\Config\AutoCleanup.ps1"
            if (Test-Path $cleanupScript) {
                Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$cleanupScript`"" -Verb RunAs
            }
        }
    }

} catch {
    Add-Content -LiteralPath $logPath -Value "$timestamp  ERRO: $_"
}
