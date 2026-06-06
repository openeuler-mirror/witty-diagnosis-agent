# FUSE Fault Injection: 8-Branch Comparative Analysis

> **Experiment**: WSL2 (Kernel 6.6.114.1, FUSE API 7.39) — All faults injected via custom C daemons
> **Date**: 2026-06-04
> **Platform**: Ubuntu 22.04 WSL2, x86_64

---

## 1. Fault Type Classification

| Branch | Fault Class | Subclass | Root Cause |
|--------|-----------|----------|------------|
| **A** | ⚡ Crash | Daemon exits/terminates | `pause()` after INIT — daemon never enters request loop |
| **B** | 🐌 Performance | Slow processing | `usleep(2000000)` before every reply — 2s per operation |
| **C** | 🔧 Protocol | Protocol constraint misconfig | `max_readahead=4096` + empty readdir responses |
| **D** | 💥 Data Integrity | Silent data corruption | Write returns success but data dropped; reads return zeros |
| **E** | 🔒 Deadlock | ABBA lock order | Two threads acquire locks in opposite order |
| **F** | 🚫 Access Control | Device permission | `/dev/fuse` changed from 0666 → 0600 |
| **G** | 📋 Baseline | No fault | Static analysis of kernel FUSE module |
| **H** | 🌀 Compound | Slow + Data loss | 2s delay + writeback cache + silent data drop |

---

## 2. Severity Matrix

```
                    Impact
                    Low ──────────────► High
                    │
                    │    F (Access)   D (Data Loss)
                    │                 H (Mixed)
    Difficulty      │
    of Detection    │    C (Protocol)
                    │
                    ▼    B (Slow)     E (Deadlock)
                    │                 A (Crash)
                    │
                    │    G (Baseline)
                    │
                    Easy              Hard
                    ◄─────────────────►
                    Detection
```

| Branch | Severity | Detection Difficulty | User Visibility |
|--------|----------|---------------------|-----------------|
| **A** (Crash) | P1 | 🔴 Easy | Immediate error message |
| **B** (Slow) | P2 | 🟡 Medium | Operations timeout |
| **C** (Protocol) | P2 | 🟡 Medium | Timeout (looks like crash) |
| **D** (Data Loss) | **P0** | 🔴🔴 **Hard** | **No visible error** |
| **E** (Deadlock) | P2 | 🔴🔴 **Hard** | Process hang (no error msg) |
| **F** (Access) | P3 | 🟢 Easy | Permission denied |
| **G** (Baseline) | Info | N/A | No fault |
| **H** (Mixed) | **P0** | 🔴🔴🔴 **Very Hard** | Performance issue masks data loss |

---

## 3. Detection Indicators by Layer

### /sys/fs/fuse/connections/N/waiting

| Branch | Baseline | During Access | Behavior |
|--------|----------|---------------|----------|
| A (Hang) | 1 | N/A (disconnected) | Mount dies immediately |
| B (Slow) | 1 | 1 | Steady — daemon reads but delays reply |
| C (Proto) | 1 | 1 | Steady — daemon handles reqs but sends empty data |
| D (Writeback) | 1 | 1 | Steady — daemon responds but corrupts data |
| E (Deadlock) | 1 | **2** | **Elevated** — requests pile up on deadlocked threads |
| H (Mixed) | 1 | 1 | Steady — same as B/D individually |

### D-State Processes

| Branch | D-State Detected? | Details |
|--------|-------------------|---------|
| A (Hang) | No | Mount disconnected immediately |
| B (Slow) | No | Timeout catches operations before D state |
| C (Proto) | No | Same as B |
| D (Writeback) | No | Daemon responds normally |
| **E (Deadlock)** | **✅ Yes** | `mkdir` stuck in D state — kernel can't make progress |
| H (Mixed) | No | Timeout catches it |

### Daemon Process State

| Branch | State | Meaning |
|--------|-------|---------|
| A | — | Dead (no process) |
| B | S | Sleeping (normal) |
| C | S | Sleeping (normal) |
| D | S | Sleeping (normal) |
| **E** | **Sl** | **Multi-threaded + sleeping in lock** |
| H | S | Sleeping (normal) |

---

## 4. Key Diagnostic Insights

### Most Dangerous: Branch D & H (Silent Data Corruption)

Unlike crash or hang scenarios where something visibly breaks, **data corruption faults produce no error signals**. The daemon reports success for every write, but the data is never persisted. Key characteristics:

- **No kernel messages** (dmesg is clean)
- **No D-state processes**
- **Daemon appears healthy** (S state)
- **waiting count normal** (1)
- **Application sees success** — writes return OK

**Detection requires**: Checksum verification, read-after-write comparison, or data integrity checks at the application layer.

### Most Difficult to Diagnose: Branch E (Deadlock)

The ABBA deadlock keeps the daemon alive but completely stops processing. Unlike a crash (which gives an immediate error), deadlock manifests as a **silent hang**:

- `sysfs waiting` **elevated to 2+** (unique indicator)
- Daemon shows **`Sl` state** (not just `S`)
- **D-state processes** accumulate over time
- No error messages anywhere in the system

### Most Deceptive: Branch H (Compound)

Combining slow processing with data corruption creates a **diagnostic trap** — operators observing slow performance will focus on the latency issue, never suspecting that data is also being silently corrupted. The two symptoms create a "smoke screen" effect.

---

## 5. Recovery Complexity

| Branch | Recovery Steps | Complexity |
|--------|---------------|-----------|
| **A** | `kill daemon` → `umount` → restart | 🟢 Easy |
| **B** | Fix daemon logic (remove delay) | 🟢 Easy (code fix) |
| **C** | Fix INIT response (increase max_read) + add readdir data | 🟢 Easy (code fix) |
| **D** | Fix write handler to actually store data | 🟢 Easy (code fix) |
| **E** | `kill -9` → `umount` → fix lock order | 🟡 Medium (kill + code fix) |
| **F** | `chmod 0666 /dev/fuse` | 🟢 Trivial |
| **G** | N/A (baseline) | — |
| **H** | Fix both delay AND write handler | 🟡 Medium (compound fix) |

---

## 6. WSL2-Specific Observations

1. **Buffer size sensitivity**: `read(/dev/fuse)` requires ≥8192 byte buffer on WSL2 — this is NOT true on standard Linux kernel deployments
2. **"Transport endpoint" vs "EIO"**: WSL2 returns `ENOTCONN` on dead mounts; standard Linux returns `EIO` — different error semantics
3. **FUSE compiled in**: `CONFIG_FUSE_FS=y` — cannot unload/reload the module (would be `m` in modular kernels)
4. **`/dev/fuse` world-writable** (0666) by default — same as standard Linux, but notable for WSL2 where container isolation is different
5. **Mount persistence**: Dead FUSE mounts persist in the mount table even after daemon death — `umount -l` required for cleanup

---

## Generated Reports Summary

| # | Branch | Markdown | HTML |
|---|--------|----------|------|
| 1 | A — Daemon Hang | `FUSE文件系统daemon挂起_20260604_064549_report.md` | `.html` |
| 2 | B — Slow Processing | `RCA-FUSE-BranchB-SlowProcessing.md` | `.html` |
| 3 | C — MaxRead Constraint | `RCA-FUSE-BranchC-MaxReadConstraint.md` | `.html` |
| 4 | D — Writeback Data Loss | `RCA-FUSE-BranchD-WritebackDataLoss.md` | `.html` |
| 5 | E — ABBA Deadlock | `RCA-FUSE-BranchE-Deadlock.md` | `.html` |
| 6 | F — Permission Denied | `RCA-FUSE-BranchF-Permission.md` | `.html` |
| 7 | G — Kernel Baseline | `RCA-FUSE-BranchG-KernelBaseline.md` | `.html` |
| 8 | H — Mixed Compound | `RCA-FUSE-BranchH-MixedCompound.md` | `.html` |
| — | **This Comparison** | `FUSE-8Branch-Comparison-Report.md` | — |

All reports: `C:\Users\86135\.witty-diagnosis-agent\baize\reports\`
