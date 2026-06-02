# kernel-io-uring-diagnosis Test Suite

This directory contains reproducible test materials for the
`kernel-io-uring-diagnosis` skill. The tests are intended for Linux/openEuler
test hosts. Fault injection changes process limits, creates temporary files, and
starts short-lived test programs only inside the selected test directory.

## Layout

```text
test/kernel-io-uring-diagnosis/
├── README.md
├── cleanup.sh
├── run.sh
├── fault-injection/
│   └── src/
│       └── io_uring_fault_probe.c
└── reports/
    └── sample_report.md
```

## Prerequisites

- Linux kernel with io_uring support.
- `gcc`.
- Standard Linux headers providing `linux/io_uring.h`.
- Optional: `strace` for syscall evidence.

No liburing dependency is required. The probe uses raw syscalls and standard
Linux headers.

## Supported Scenarios

| Scenario | Command | Expected signal |
| --- | --- | --- |
| baseline probe | `./run.sh run baseline` | successful setup when kernel supports io_uring |
| memlock/fixed buffer | `./run.sh run memlock` | low `ulimit -l` plus fixed-buffer registration evidence |
| ring pressure | `./run.sh run ring` | queue depth and repeated submit/enter activity |
| SQPOLL | `./run.sh run sqpoll` | setup success/failure and errno for SQPOLL mode |
| O_DIRECT alignment | `./run.sh run odirect` | unaligned O_DIRECT write returns `EINVAL` on supporting filesystems |
| feature compatibility | `./run.sh run compat` | kernel/header/probe evidence for compatibility classification |

## Workflow

```bash
cd test/kernel-io-uring-diagnosis

# Build the raw-syscall probe.
./run.sh build

# Run one scenario and save logs.
./run.sh run memlock

# Inspect generated logs.
./run.sh status

# Run skill branch scripts against the collected log.
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_limits.sh \
  -l ./out/memlock.log
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_compat.sh \
  -l ./out/memlock.log

# Clean generated artifacts.
./run.sh clean
```

## Safety

- The probe creates temporary files under `test/kernel-io-uring-diagnosis/out/`.
- The `memlock` scenario runs the probe under a low `ulimit -l` in a child shell.
- The `odirect` scenario writes to a temporary file and removes it during clean.
- No system configuration, sysctl, service, or cgroup setting is modified.

## Expected Diagnosis Mapping

- `memlock`: the skill should classify the case as `resource-limit` when fixed
  buffer registration fails and the log shows a finite locked-memory limit.
- `ring`: the skill should identify ring capacity/completion-flow evidence and
  request queue depth and consumer evidence if the probe does not reproduce
  actual CQ overflow.
- `sqpoll`: the skill should classify as `worker-or-sqpoll` or
  `compat-or-permission` depending on the setup errno.
- `odirect`: the skill should classify `EINVAL` with O_DIRECT as a direct-I/O
  alignment candidate and request buffer address/length/offset evidence.
- `compat`: the skill should avoid high-confidence compatibility conclusions
  unless runtime syscall errno and feature arguments are present.
