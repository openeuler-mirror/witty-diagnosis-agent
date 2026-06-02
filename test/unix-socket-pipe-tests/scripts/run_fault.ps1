# run_fault.ps1 — Windows 端 Unix Socket & Pipe 故障注入管理器
# 使用: .\run_fault.ps1 <action> <fault> [args...]
# 动作: start, status, stop, list, auto
# 故障: A, B, C, D, E, F, G

param(
    [string]$Action = "help",
    [string]$Fault = "",
    [string[]]$Args = @()
)

$Faults = @{
    A = @{ Script = "inject_uds_backlog.sh";       Binary = "uds_backlog";       DefaultArgs = @("2", "10") }
    B = @{ Script = "inject_abstract_conflict.sh"; Binary = "abstract_conflict"; DefaultArgs = @("@uds_test") }
    C = @{ Script = "inject_passcred.sh";          Binary = "passcred_fail";     DefaultArgs = @() }
    D = @{ Script = "inject_socket_perms.sh";      Binary = "socket_perms";      DefaultArgs = @("0000") }
    E = @{ Script = "inject_pipe_buf.sh";          Binary = "pipe_buf_full";     DefaultArgs = @("64", "1024") }
    F = @{ Script = "inject_sigpipe.sh";           Binary = "sigpipe_unhandled"; DefaultArgs = @() }
    G = @{ Script = "inject_socketpair.sh";        Binary = "socketpair_leak";   DefaultArgs = @("10", "100") }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WslPath = $ScriptDir -replace '^([A-Z]):\\', '/mnt/$1/' -replace '\\', '/'

function Run-Wsl {
    param([string]$Cmd)
    wsl bash -c $Cmd 2>&1 | Out-Host
}

function Get-RegKey {
    param([string]$Path, [string]$Name)
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Get-WslDistro {
    # 尝试读取默认 WSL 分发版
    $distro = Get-RegKey "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" "DefaultDistribution"
    if ($distro -and $distro -match 'urn.*?(\S+)$') {
        return $Matches[1]
    }
    # fallback: 取第一个已安装的分发版
    $first = wsl -l -q 2>$null | Select-Object -First 1
    if ($first) { return $first.Trim() }
    return "Ubuntu"
}

if ($Action -eq "help") {
    Write-Host "Unix Socket & Pipe 故障注入管理器"
    Write-Host ""
    Write-Host "用法: .\run_fault.ps1 <action> <fault> [args...]"
    Write-Host ""
    Write-Host "动作:"
    Write-Host "  start  <fault> [args]  启动故障注入"
    Write-Host "  status <fault>         查看故障状态"
    Write-Host "  stop   <fault|all>     停止故障注入"
    Write-Host "  list                   列出所有故障"
    Write-Host "  auto                   顺序执行 A→B→C→D→E→F→G"
    Write-Host ""
    Write-Host "故障类型:"
    $Faults.Keys | Sort-Object | ForEach-Object {
        $f = $Faults[$_]
        $def = if ($f.DefaultArgs.Count -gt 0) { " (默认: $($f.DefaultArgs -join ' '))" } else { "" }
        Write-Host "  $_ : $($f.Binary)$def"
    }
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\run_fault.ps1 start A"
    Write-Host "  .\run_fault.ps1 start A 2 10"
    Write-Host "  .\run_fault.ps1 status A"
    Write-Host "  .\run_fault.ps1 stop A"
    Write-Host "  .\run_fault.ps1 stop all"
    Write-Host "  .\run_fault.ps1 list"
    Write-Host "  .\run_fault.ps1 auto"
    return
}

if ($Action -eq "list") {
    Write-Host "可用故障:"
    $Faults.Keys | Sort-Object | ForEach-Object {
        $f = $Faults[$_]
        $def = if ($f.DefaultArgs.Count -gt 0) { " (默认参数: $($f.DefaultArgs -join ' '))" } else { "" }
        Write-Host "  $_ : $($f.Script) → $($f.Binary)$def"
    }
    return
}

if ($Action -eq "auto") {
    Write-Host "=== 全量回归测试: 顺序执行 A→B→C→D→E→F→G ==="
    $Faults.Keys | Sort-Object | ForEach-Object {
        $f = $Faults[$_]
        $argsStr = if ($f.DefaultArgs.Count -gt 0) { " $($f.DefaultArgs -join ' ')" } else { "" }
        Write-Host ""
        Write-Host ">>> [$_] 注入 $($f.Binary)$argsStr"
        Run-Wsl "cd $WslPath/scripts && bash $($f.Script) run $($f.DefaultArgs -join ' ')"
        Write-Host "<<< [$_] 完成"
    }
    Write-Host ""
    Write-Host "=== 全量回归测试完成, 执行清理 ==="
    Run-Wsl "cd $WslPath/scripts && bash cleanup.sh"
    return
}

if ($Action -eq "stop" -and $Fault -eq "all") {
    Write-Host "=== 停止所有故障注入 ==="
    $Faults.Keys | Sort-Object | ForEach-Object {
        $f = $Faults[$_]
        Run-Wsl "cd $WslPath/scripts && bash $($f.Script) stop"
    }
    Run-Wsl "cd $WslPath/scripts && bash cleanup.sh"
    return
}

if (-not $Faults.ContainsKey($Fault)) {
    Write-Host "未知故障: $Fault"
    Write-Host "可用故障: $($Faults.Keys -join ', ')"
    return
}

$faultInfo = $Faults[$Fault]
$ScriptFile = $faultInfo.Script
$scriptArgs = if ($Args.Count -gt 0) { $Args } else { $faultInfo.DefaultArgs }

switch ($Action) {
    "start" {
        Write-Host ">>> 启动故障 $Fault : $($faultInfo.Binary) $($scriptArgs -join ' ')"
        Run-Wsl "cd $WslPath/scripts && bash $ScriptFile run $($scriptArgs -join ' ')"
    }
    "status" {
        Write-Host ">>> 检查故障 $Fault : $($faultInfo.Binary)"
        Run-Wsl "cd $WslPath/scripts && bash $ScriptFile status"
    }
    "stop" {
        Write-Host ">>> 停止故障 $Fault : $($faultInfo.Binary)"
        Run-Wsl "cd $WslPath/scripts && bash $ScriptFile stop"
    }
    default {
        Write-Host "未知动作: $Action"
        Write-Host "可用动作: start, status, stop, list, auto"
    }
}
