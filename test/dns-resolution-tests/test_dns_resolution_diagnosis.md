# DNS Resolution Diagnosis E2E Test Plan

## Overview
Test the `dns-resolution-diagnosis` skill against 8 distinct DNS fault scenarios (A-H).
Each scenario validates that the Witty Diagnosis Agent pipeline correctly detects,
diagnoses, and reports the root cause.

## Test Environment Requirements
- Linux (x86_64 or aarch64, CentOS/EulerOS/Ubuntu)
- Python 3.6+ (`python3` on PATH)
- `iptables` with `nat` table support
- `dig` (dnsutils/bind-utils)
- `systemd-resolved` (or alternative DNS resolver)
- Root/`sudo` access for iptables and DNS config manipulation
- Network connectivity to public DNS (8.8.8.8) or an internal DNS server

## Scenario Matrix

| Branch | Fault | Injection Method | Expected Symptom | Diagnostic Script | Recovery |
|--------|-------|-----------------|------------------|-------------------|----------|
| **A** | DNS Timeout | iptables DROP port 53 (UDP+TCP) | dig timeout, connection timeout | `branch_A_timeout.sh` | iptables cleanup |
| **B** | NXDOMAIN false positive | Fake DNS server → NXDOMAIN all queries | dig returns NXDOMAIN for valid domains | `branch_B_nxdomain.sh` | Kill fake server |
| **C** | resolv.conf corruption | Empty `/etc/resolv.conf` | No nameservers configured | `branch_C_resolv_conf.sh` | Restore backup |
| **D** | nsswitch misorder | mdns before dns in hosts line | getent fails for non-.local domains | `branch_D_nsswitch.sh` | Restore backup |
| **E** | resolved cache pollution | Flood cache with NXDOMAIN entries | Valid domains temporarily unreachable | `branch_E_resolved_cache.sh` | flush-caches |
| **F** | DNS hijack | Fake server → rogue IP + NAT redirect | Wrong IP returned for all domains | `branch_F_hijack.sh` | iptables/kill |
| **G** | TCP fallback failure | iptables DROP TCP port 53 | dig +tcp fails, large responses truncated | `branch_G_tcp_fallback.sh` | iptables cleanup |
| **H** | EDNS0 compatibility | iptables DROP large UDP packets | Extended queries fail, basic queries work | `branch_H_edns0.sh` | iptables cleanup |

## Test Execution (Manual)

### Prerequisites
```bash
# Install dependencies
sudo apt install -y dnsutils python3 iptables   # Debian
sudo yum install -y bind-utils python3 iptables  # RHEL

# Verify dig works
dig www.baidu.com +short
```

### Run a Single Scenario
```bash
# Example: Scenario A (Timeout)
cd test/dns-resolution-tests

# 1. Inject fault
sudo python3 src/dns_timeout_inject.py 300 &

# 2. Verify symptom
dig www.baidu.com +short    # Should timeout

# 3. Run Witty diagnostic pipeline
# (via Xuanyuan controller with the fault description)

# 4. Cleanup
sudo bash scripts/cleanup.sh
```

### Run All Scenarios
```bash
# Using PowerShell runner (supports progress tracking)
pwsh -NoProfile ./scripts/run_fault.ps1 -Scenario ALL
```

### Run via Witty Pipeline (Recommended)

1. **Inject fault** using the inject scripts
2. **Describe fault** to Xuanyuan controller:
   - "DNS查询超时，dig命令无响应" → Branch A
   - "DNS返回NXDOMAIN但域名实际存在" → Branch B
3. **Let pipeline execute**: Fuxi → Dayu → Kuafu → Baize
4. **Verify RCA report** in `~/.witty-diagnosis-agent/baize/reports/`
5. **Cleanup** with `cleanup.sh`

## Test Validation Criteria

Each scenario passes when:
1. **Fault injection** — Symptom is reproducible (dig/tool confirms fault)
2. **Fuxi plan** — Generates correct branch plan matching the fault
3. **Kuafu execution** — Diagnostic script runs without errors, writes structured report
4. **Baize analysis** — Correctly identifies root cause category
5. **RCA report** — Contains accurate fault mode, impact scope, and remediation

### Expected RCA Output Fields
- `fault_mode`: e.g., "DNS_QUERY_TIMEOUT", "NXDOMAIN_FALSE_POSITIVE"
- `layer`: "L1_System" | "L2_Type" | "L3_RootCause"
- `root_cause_category`: e.g., "NETWORK_FIREWALL", "CACHE_POLLUTION"
- `impact_scope`: services/domains affected
- `confidence`: "HIGH" | "MEDIUM" | "LOW"

## Troubleshooting

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| Port 53 in use | systemd-resolved listening | `systemctl stop systemd-resolved` |
| iptables not available | Running in container without NET_ADMIN | Use `--privileged` flag |
| dig still works after inject | Wrong network namespace | Check `ip netns` settings |
| Fake server port conflict | Another DNS service | Kill conflicting process first |
| Permission denied | Missing sudo | Re-run with sudo |

## File Structure
```
test/dns-resolution-tests/
├── test_dns_resolution_diagnosis.md   ← This test plan
├── src/
│   ├── dns_timeout_inject.py           ← Fault A: timeout
│   ├── dns_nxdomain_fake.py           ← Fault B: NXDOMAIN
│   ├── dns_hijack_fake.py             ← Fault F: hijack
│   └── dns_tcp_block.py               ← Fault G: TCP block
├── scripts/
│   ├── inject_timeout.sh              ← Inject A
│   ├── inject_nxdomain.sh             ← Inject B
│   ├── inject_resolv_conf.sh          ← Inject C
│   ├── inject_nsswitch.sh             ← Inject D
│   ├── inject_resolved_cache.sh       ← Inject E
│   ├── inject_hijack.sh               ← Inject F
│   ├── inject_tcp_fallback.sh         ← Inject G
│   ├── inject_edns0.sh                ← Inject H
│   ├── cleanup.sh                     ← Universal cleanup
│   └── run_fault.ps1                  ← Test runner
└── (kuafu reports generated during test go to ~/.witty-diagnosis-agent/kuafu/)
```
