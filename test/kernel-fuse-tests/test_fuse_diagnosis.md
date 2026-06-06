# FUSE Kernel Fault Diagnosis E2E Test Plan

## Overview
Test the `kernel-fuse-diagnosis` skill against 8 distinct FUSE fault scenarios (A-H).
Each scenario validates that the Witty Diagnosis Agent pipeline correctly detects,
diagnoses, and reports the root cause.

## Test Environment Requirements
- Linux (x86_64 or aarch64, kernel 3.10+, CentOS/EulerOS/Ubuntu)
- Python 3.6+ (`python3` on PATH)
- FUSE kernel module loaded (`modprobe fuse`; `lsmod | grep fuse`)
- Custom FUSE daemon for test injection (provided under `src/`)
- `libfuse` and `libfuse-dev` installed for compiling test daemon
- Build tools: `gcc`, `make`, `pkg-config`
- Root/`sudo` access for sysfs manipulation and mount operations
- `gdb` (recommended for deadlock branch tests)
- `strace`, `lsof`, `dd`

## Scenario Matrix

| Branch | Fault | Injection Method | Expected Symptom | Diagnostic Script | Recovery |
|--------|-------|-----------------|------------------|-------------------|----------|
| **A** | Daemon Crash | Kill FUSE daemon (SIGKILL) | stat → EIO, connection destroyed | `branch_A_daemon_crash.sh` | Restart daemon |
| **B** | Req Queue Block | Daemon sleep before processing | waiting > 0, D-state processes | `branch_B_req_queue.sh` | Resume daemon |
| **C** | Max Read/Write Misconfig | Mount with small max_read=4096 | Read throughput < 20 MB/s | `branch_C_max_read_write.sh` | Remount with proper size |
| **D** | Writeback Cache | Enable + no ->write callback | Written data inconsistency | `branch_D_writeback_cache.sh` | Implement ->write() |
| **E** | MT Deadlock | Two mutex lock inversion | All threads stuck on mutex | `branch_E_mt_deadlock.sh` | Fix lock ordering |
| **F** | /dev/fuse Permission | Change /dev/fuse to 0600 root:root | Daemon cannot open device | `branch_F_dev_fuse_perm.sh` | Restore permissions |
| **G** | Kernel Bug | Trigger known FUSE race | dmesg Oops/BUG in fuse | `branch_G_kernel_bug.sh` | Kernel upgrade |
| **H** | Mixed | Combine A + C + D | Multiple symptoms | `branch_H_mixed.sh` | Fix each component |

## Test Execution (Manual)

### Prerequisites
```bash
# Install dependencies
sudo apt install -y build-essential libfuse-dev pkg-config strace lsof gdb  # Debian
sudo yum install -y gcc fuse-devel pkgconfig strace lsof gdb               # RHEL

# Build test FUSE daemon
cd test/kernel-fuse-tests/src
make

# Load FUSE module
sudo modprobe fuse

# Verify FUSE works
mkdir -p /tmp/fuse_test_mount
./bin/fuse_test_daemon -f /tmp/fuse_test_mount &
sleep 2
ls -la /tmp/fuse_test_mount
```

### Run a Single Scenario
```bash
# Example: Scenario A (Daemon Crash)
cd test/kernel-fuse-tests

# 1. Mount test FUSE filesystem
mkdir -p /tmp/fuse_test
sudo ./scripts/inject_daemon_crash.sh setup

# 2. Verify symptom
stat /tmp/fuse_test    # Should show "Transport endpoint is not connected"

# 3. Run Witty diagnostic pipeline
# (via Xuanyuan controller with fault description)

# 4. Cleanup
sudo bash scripts/cleanup.sh
```

### Run All Scenarios
```bash
# Sequential test runner
sudo bash scripts/run_all.sh
```

### Run via Witty Pipeline (Recommended)

1. **Inject fault** using the inject scripts
2. **Describe fault** to Xuanyuan controller:
   - "FUSE文件系统访问报Input/output error" → Branch A
   - "FUSE挂载点ls命令卡死无响应" → Branch B
3. **Let pipeline execute**: Fuxi → Dayu → Kuafu → Baize
4. **Verify RCA report** in `~/.witty-diagnosis-agent/baize/reports/`
5. **Cleanup** with `cleanup.sh`

## Test Validation Criteria

Each scenario passes when:
1. **Fault injection** — Symptom is reproducible (stat/ls/dmesg confirms fault)
2. **Fuxi plan** — Generates correct branch plan matching the fault
3. **Kuafu execution** — Diagnostic script runs without errors, writes structured report
4. **Baize analysis** — Correctly identifies root cause category
5. **RCA report** — Contains accurate fault mode, impact scope, and remediation

### Expected RCA Output Fields
- `fault_mode`: e.g., "FUSE_DAEMON_CRASH", "FUSE_REQ_QUEUE_BLOCK"
- `layer`: "L1_System" | "L2_Type" | "L3_RootCause"
- `root_cause_category`: e.g., "DAEMON_CRASH_SIGKILL", "QUEUE_BLOCK_THREAD_POOL"
- `impact_scope`: mount points affected
- `confidence`: "HIGH" | "MEDIUM" | "LOW"

## Troubleshooting

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| /dev/fuse not found | FUSE module not loaded | `sudo modprobe fuse` |
| Permission denied | Non-root user | `sudo` or add user to fuse group |
| Test daemon won't compile | Missing libfuse-dev | Install libfuse-dev package |
| Port/channel conflict | Another FUSE daemon running | Check `mount -t fuse` and `ps aux` |
| Daemon already mounted | Previous test not cleaned | `sudo umount /tmp/fuse_test` |
| FUSE not supported | Kernel < 2.6.14 | Upgrade kernel or check CONFIG_FUSE |
| Container missing capabilities | No --privileged | Add `--device /dev/fuse --cap-add SYS_ADMIN` |

## File Structure
```
test/kernel-fuse-tests/
├── test_fuse_diagnosis.md          ← This test plan
├── src/
│   ├── fuse_test_daemon.c          ← Minimal FUSE daemon for test injection
│   ├── fuse_crash_daemon.c         ← Daemon that crashes on command
│   ├── fuse_slow_daemon.c          ← Daemon that artificially delays requests
│   ├── fuse_mt_deadlock_daemon.c   ← Daemon with intentional lock inversion
│   └── Makefile                    ← Build all test daemons
├── scripts/
│   ├── inject_daemon_crash.sh      ← Inject A: kill daemon
│   ├── inject_req_queue.sh         ← Inject B: make daemon stall
│   ├── inject_max_read_write.sh    ← Inject C: remount with small max_read
│   ├── inject_writeback_cache.sh   ← Inject D: enable writeback without ->write()
│   ├── inject_mt_deadlock.sh       ← Inject E: trigger deadlock in test daemon
│   ├── inject_dev_fuse_perm.sh     ← Inject F: restrict /dev/fuse permissions
│   ├── inject_mixed.sh             ← Inject H: combine multiple faults
│   ├── setup.sh                    ← Setup base FUSE environment
│   ├── cleanup.sh                  ← Universal cleanup
│   └── run_all.sh                  ← Sequential test runner
└── (kuafu reports generated during test go to ~/.witty-diagnosis-agent/kuafu/)
```
