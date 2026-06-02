# io_uring Kernel Feature Notes

io_uring support is kernel-version sensitive and often affected by distribution
backports. Use these notes as a triage aid, not as the only proof of support.

## Version and Runtime Checks

Always collect:

```bash
uname -r
uname -m
cat /etc/os-release
grep -R "IORING_FEAT_" /usr/include/linux/io_uring.h 2>/dev/null
```

Prefer runtime evidence:

- `io_uring_setup` return value and `features` field when available.
- `io_uring_register` opcode and errno.
- application feature probe output.
- strace around setup/register failures.

## Common Compatibility Signals

| Signal | Interpretation | Next check |
| --- | --- | --- |
| `ENOSYS` on `io_uring_setup` | syscall is unavailable | confirm kernel config/version |
| `EINVAL` on setup | invalid entries, flags, or unsupported flag combination | decode setup flags and entries |
| `EINVAL` on register | unsupported register opcode or invalid argument | identify opcode and kernel support |
| app built with newer headers | compile-time symbols may exceed runtime kernel | run feature probe on target host |
| works on newer distro, fails on older openEuler kernel | feature/backport difference | compare runtime kernel and app required features |

## Feature Categories to Identify

- Setup flags: `IORING_SETUP_SQPOLL`, `IORING_SETUP_IOPOLL`,
  `IORING_SETUP_CLAMP`, `IORING_SETUP_ATTACH_WQ`, `IORING_SETUP_COOP_TASKRUN`,
  `IORING_SETUP_SINGLE_ISSUER`.
- Register operations: buffers, files, eventfd, restrictions, personality,
  ring fd, provided buffers.
- Operation codes: read/write, timeout, poll, fsync, accept/connect, send/recv,
  splice, openat/statx, cancel, cmd passthrough.
- Feature bits returned by setup: single mmap, nodrop, submit stable, rw cur pos,
  fast poll, poll 32bits, sqpoll nonfixed, ext arg, native workers, rsrc tags.

## Diagnosis Rules

- Do not assume a feature is supported because the header defines it.
- Do not assume a failure is compatibility-related until invalid arguments and
  resource limits are checked.
- If evidence only shows `EINVAL`, classify as `compat-or-invalid-argument`
  until setup/register arguments are decoded.
- For community PR reports, state exact kernel version and the collected runtime
  evidence instead of broad claims such as "old kernel does not support it".
