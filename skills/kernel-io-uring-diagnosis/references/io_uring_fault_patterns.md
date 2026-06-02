# io_uring Fault Patterns

This reference maps common io_uring symptoms to evidence, likely causes, and
verification steps. Use it to keep diagnosis evidence-driven and to avoid
concluding from one error code alone.

## Resource Limits

| Symptom | Key evidence | Likely cause | Verification |
| --- | --- | --- | --- |
| `io_uring_setup` returns `ENOMEM` | low memory, cgroup memory pressure, large entries | memory pressure or ring allocation failure | check `/proc/meminfo`, cgroup memory limits, requested entries |
| `io_uring_register` returns `ENOMEM` | fixed buffer registration, low `Max locked memory` | `RLIMIT_MEMLOCK` too low | compare registered bytes with `/proc/<pid>/limits` |
| `io_uring_setup` returns `EPERM` | SQPOLL or restricted setup flags | missing privilege or restricted operation | inspect setup flags and process capabilities |
| submission returns `EAGAIN` | high in-flight I/O, transient queue pressure | temporary queue/resource pressure | correlate with queue depth, worker state, retry behavior |

Do not treat every `ENOMEM` as system-wide memory exhaustion. For fixed buffers,
memlock and pinned page accounting are usually more relevant than free memory.

## Ring Capacity and Completion Flow

| Symptom | Key evidence | Likely cause | Verification |
| --- | --- | --- | --- |
| submission queue full | application log, high in-flight requests | SQ depth too small or submitter faster than consumer | compare queue depth, submit rate, completion rate |
| CQ overflow or missing CQE | kernel/app log mentions overflow, delayed completions | CQ not drained fast enough | check consumer thread state and CQ event loop |
| request timeout | app timeout, worker D state, storage latency | backend I/O slow or worker blocked | correlate with `iou-wrk`, block device, filesystem logs |
| repeated short I/O | app log and filesystem behavior | file size, EOF, direct I/O alignment, backend error | check syscall return values and file offset/length |

Ring pressure is often a symptom. The root cause may be a blocked consumer,
slow backing device, worker starvation, or application retry behavior.

## Worker and SQPOLL

| Symptom | Key evidence | Likely cause | Verification |
| --- | --- | --- | --- |
| many `iou-wrk-*` threads | `ps -eLf`, thread states | blocked async workers or high concurrency | inspect thread states, wchan, cgroup CPU/io limits |
| `iou-sqp-*` busy | high CPU, SQPOLL enabled | busy polling, affinity, or scheduling issue | check CPU affinity, scheduler, cgroup CPU quota |
| completions stop while submit continues | worker D state or CQ consumer blocked | backend I/O hang or CQ drain failure | correlate worker stack/wchan and app event loop |
| SQPOLL setup fails | `EPERM` or `EINVAL` | insufficient privilege or unsupported flag combination | inspect flags, kernel version, capabilities |

SQPOLL changes execution context. A failure may be caused by scheduling and
CPU placement even when the syscall arguments are otherwise valid.

## Fixed Buffers and Fixed Files

| Symptom | Key evidence | Likely cause | Verification |
| --- | --- | --- | --- |
| buffer registration fails | `io_uring_register` errno | memlock, invalid address, lifetime issue | compare address/length with maps and limits |
| fixed file operation fails | `IOSQE_FIXED_FILE`, registered file table | stale index or unregister lifecycle bug | inspect register/unregister sequence |
| sporadic `EFAULT` | invalid userspace pointer | buffer unmapped or freed too early | inspect application lifetime and maps |
| `EBUSY` during unregister | in-flight requests still reference resource | unregister racing with active SQEs | check completion drain before unregister |

The diagnosis must separate registration failure from use-after-unregister or
lifetime mistakes. They produce different remediation paths.

## O_DIRECT Alignment

| Symptom | Key evidence | Likely cause | Verification |
| --- | --- | --- | --- |
| `read`/`write` returns `EINVAL` | `O_DIRECT` fd, unaligned buffer/len/offset | direct I/O alignment violation | check address, length, offset, logical block size |
| works without `O_DIRECT` | same workload succeeds in buffered I/O | direct I/O constraints | verify filesystem and block device constraints |
| only some files fail | filesystem or mount option difference | path-specific direct I/O support | compare mount, filesystem, block size |

For direct I/O, alignment constraints may include user buffer address, I/O
length, file offset, filesystem block size, and device logical block size.

## Kernel Compatibility

| Symptom | Key evidence | Likely cause | Verification |
| --- | --- | --- | --- |
| `ENOSYS` | syscall unavailable | kernel lacks io_uring | check kernel version and headers |
| `EINVAL` for setup/register | new flag/opcode on old kernel | unsupported feature or invalid combination | compare feature with running kernel |
| behavior differs across distros | same app, different kernel | backport delta | check distro kernel changelog and runtime probe |

Prefer runtime probing evidence over header version assumptions. Applications
may be built against newer headers than the kernel actually supports.
