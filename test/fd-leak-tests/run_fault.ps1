# run_fault.ps1 — Windows 端统一 FD 故障注入管理器
# 使用: .\run_fault.ps1 <fault_type> <action>
# 故障类型: system_fd, process_fd, close_wait, epoll, inotify, deleted_file, mixed
# 动作: run, status, stop, cleanup

param(
    [string]$FaultType = "help",
    [string]$Action = "run"
)

$Scripts = @{
    system_fd    = "inject_system_fd.sh"
    process_fd   = "inject_process_fd.sh"
    close_wait   = "inject_close_wait.sh"
    epoll        = "inject_epoll.sh"
    inotify      = "inject_inotify.sh"
    deleted_file = "inject_deleted_file.sh"
    mixed        = "inject_mixed.sh"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WslPath = "/mnt/e/桌面/AiOps/witty-diagnosis-agent/test/fd-leak-tests"

function Run-Wsl {
    param([string]$Cmd)
    wsl bash -c $Cmd 2>&1 | Out-Host
}

if ($FaultType -eq "help") {
    Write-Host "FD 故障注入管理器"
    Write-Host "用法: .\run_fault.ps1 <fault_type> <action>"
    Write-Host ""
    Write-Host "故障类型:"
    $Scripts.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "动作: run (默认), status, stop, cleanup"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\run_fault.ps1 system_fd run"
    Write-Host "  .\run_fault.ps1 epoll status"
    Write-Host "  .\run_fault.ps1 cleanup"
    return
}

if ($FaultType -eq "cleanup") {
    Run-Wsl "bash $WslPath/cleanup.sh"
    return
}

if (-not $Scripts.ContainsKey($FaultType)) {
    Write-Host "未知故障类型: $FaultType"
    Write-Host "可用类型: $($Scripts.Keys -join ', ')"
    return
}

$ScriptFile = $Scripts[$FaultType]
Run-Wsl "bash $WslPath/$ScriptFile $Action"
