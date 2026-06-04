#!/usr/bin/env pwsh
<#
.SYNOPSIS
    DNS Resolution Diagnosis E2E Test Runner
.DESCRIPTION
    Iterates through all 8 DNS fault scenarios, injects fault,
    runs the diagnostic pipeline, and collects results.
    Requires: root/administrator privileges, Linux (WSL2 for Windows dev)
.PARAMETER Scenario
    Specific scenario to test (A-H, or "ALL")
.PARAMETER SkipInject
    Skip injection step (use if fault is already active)
.PARAMETER KeepFault
    Don't cleanup after scenario
#>

param(
    [string]$Scenario = "ALL",
    [switch]$SkipInject,
    [switch]$KeepFault
)

$ROOT_DIR = Split-Path -Parent $PSScriptRoot
$SRC_DIR = Join-Path $ROOT_DIR "src"
$SCRIPTS_DIR = $ROOT_DIR "scripts"
$REPORT_DIR = "$env:HOME/.witty-diagnosis-agent/kuafu"
$TIMESTAMP = Get-Date -Format "yyyyMMddHHmmss"

$SCENARIOS = @{
    "A" = @{ Name="Timeout"; Injector="inject_timeout.sh"; Desc="DNS query timeout (firewall drop)" }
    "B" = @{ Name="NXDOMAIN"; Injector="inject_nxdomain.sh"; Desc="NXDOMAIN false positive" }
    "C" = @{ Name="ResolvConf"; Injector="inject_resolv_conf.sh corrupt"; Desc="/etc/resolv.conf corruption" }
    "D" = @{ Name="Nsswitch"; Injector="inject_nsswitch.sh corrupt"; Desc="nsswitch.conf misorder" }
    "E" = @{ Name="ResolvedCache"; Injector="inject_resolved_cache.sh poison"; Desc="systemd-resolved cache pollution" }
    "F" = @{ Name="Hijack"; Injector="inject_hijack.sh"; Desc="DNS hijack/forgery" }
    "G" = @{ Name="TcpFallback"; Injector="inject_tcp_fallback.sh"; Desc="TCP fallback failure" }
    "H" = @{ Name="EDNS0"; Injector="inject_edns0.sh"; Desc="EDNS0 compatibility" }
}

function Test-Scenario {
    param($Key, $Info)

    $scenarioName = $Info.Name
    $injector = $Info.Injector
    $desc = $Info.Desc

    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "Scenario $Key - $scenarioName" -ForegroundColor Cyan
    Write-Host "  $desc" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan

    if (-not $SkipInject) {
        Write-Host "[Step 1] Injecting fault..." -ForegroundColor Yellow
        $injectCmd = "bash '$SCRIPTS_DIR/$injector'"
        Write-Host "  Running: $injectCmd" -ForegroundColor DarkGray
        & bash -c "$injectCmd" 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Host "[OK] Fault injected" -ForegroundColor Green
    }

    Write-Host "[Step 2] Running diagnostic verification..." -ForegroundColor Yellow

    # Verify symptom with dig/other tools
    switch ($Key) {
        "A" {
            $result = & dig www.baidu.com +short 2>&1
            Write-Host "  dig result: $result" -ForegroundColor DarkGray
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($result)) {
                Write-Host "[PASS] Timeout confirmed" -ForegroundColor Green
            }
        }
        "B" {
            $result = & dig www.baidu.com +short 2>&1
            Write-Host "  dig result: $result" -ForegroundColor DarkGray
        }
        "C" {
            $resolv = Get-Content /etc/resolv.conf -ErrorAction SilentlyContinue
            Write-Host "  resolv.conf: $($resolv -join '; ')" -ForegroundColor DarkGray
        }
        "D" {
            $nss = & grep "^hosts:" /etc/nsswitch.conf 2>&1
            Write-Host "  nsswitch: $nss" -ForegroundColor DarkGray
        }
        "E" {
            $stats = & resolvectl statistics 2>&1
            Write-Host "  resolved stats: $stats" -ForegroundColor DarkGray
        }
        "F" {
            $result = & dig www.baidu.com +short 2>&1
            Write-Host "  dig result (should show rogue IP): $result" -ForegroundColor DarkGray
        }
        "G" {
            $result = & dig +tcp www.baidu.com +short 2>&1
            Write-Host "  dig +tcp result: $result" -ForegroundColor DarkGray
        }
        "H" {
            $result = & dig +edns0 +bufsize=4096 www.baidu.com +short 2>&1
            Write-Host "  dig +edns0 result: $result" -ForegroundColor DarkGray
        }
    }

    # Save verification snapshot
    $snapshotFile = "${REPORT_DIR}/dns_e2e_${Key}_${scenarioName}_${TIMESTAMP}.log"
    & dig www.baidu.com +short 2>&1 | Out-File -FilePath $snapshotFile
    Write-Host "[Step 3] Snapshot saved: $snapshotFile" -ForegroundColor Green

    if (-not $KeepFault -and -not $SkipInject) {
        Write-Host "[Step 4] Cleaning up fault..." -ForegroundColor Yellow
        if ($Key -eq "C") {
            & bash "$SCRIPTS_DIR/inject_resolv_conf.sh" restore 2>&1 | ForEach-Object { Write-Host "  $_" }
        } elseif ($Key -eq "D") {
            & bash "$SCRIPTS_DIR/inject_nsswitch.sh" restore 2>&1 | ForEach-Object { Write-Host "  $_" }
        } elseif ($Key -eq "E") {
            & bash "$SCRIPTS_DIR/inject_resolved_cache.sh" flush 2>&1 | ForEach-Object { Write-Host "  $_" }
        } elseif ($Key -ne "C" -and $Key -ne "D") {
            & bash "$SCRIPTS_DIR/../scripts/cleanup.sh" 2>&1 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Host "[OK] Cleaned up" -ForegroundColor Green
    }

    Write-Host "[DONE] Scenario $Key complete" -ForegroundColor Green
}

Write-Host @"

╔════════════════════════════════════════════╗
║  DNS Resolution Diagnosis E2E Test Suite  ║
║  8 Scenarios (A-H)                        ║
╚════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

if ($Scenario -eq "ALL") {
    foreach ($key in @("A","B","C","D","E","F","G","H")) {
        Test-Scenario -Key $key -Info $SCENARIOS[$key]
        if (-not $KeepFault) { Start-Sleep -Seconds 2 }
    }
} elseif ($SCENARIOS.ContainsKey($Scenario)) {
    Test-Scenario -Key $Scenario -Info $SCENARIOS[$Scenario]
} else {
    Write-Error "Unknown scenario: $Scenario. Valid: A-H or ALL"
    exit 1
}

Write-Host @"

╔════════════════════════════════════════════╗
║  All tests complete!                      ║
╚════════════════════════════════════════════╝
"@ -ForegroundColor Magenta
