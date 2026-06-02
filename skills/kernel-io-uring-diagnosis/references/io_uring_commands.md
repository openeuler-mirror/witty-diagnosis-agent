# io_uring Diagnosis Command Reference

All commands in this reference are intended for diagnosis. Commands that trace a
live process can affect performance; get approval before using them in
production.

## Baseline

```bash
uname -a
cat /etc/os-release
ulimit -a
cat /proc/meminfo
cat /proc/sys/kernel/osrelease
```

## Process State

```bash
cat /proc/<pid>/status
cat /proc/<pid>/limits
cat /proc/<pid>/cgroup
ls -la /proc/<pid>/fd | head -100
ps -L -p <pid> -o pid,tid,psr,stat,pcpu,comm,wchan:32
```

## io_uring Syscall Trace

```bash
strace -f -tt -T -e trace=io_uring_setup,io_uring_enter,io_uring_register -p <pid>
strace -f -e trace=%desc,%file,io_uring_setup,io_uring_enter,io_uring_register <command>
```

Fields to record:

- syscall name and errno
- setup entries and flags
- register opcode
- elapsed time (`-T`)
- thread ID and timestamp

## Worker and SQPOLL Threads

```bash
ps -eLf | grep -E 'iou-wrk|iou-sqp|io_uring|<process-name>'
ps -L -p <pid> -o pid,tid,stat,pcpu,pmem,comm,wchan:32
for t in /proc/<pid>/task/*; do
  echo "== $t =="; cat "$t/status" 2>/dev/null | grep -E 'Name|State|voluntary|nonvoluntary';
  cat "$t/wchan" 2>/dev/null;
done
```

If root permissions are available, kernel stacks may help:

```bash
cat /proc/<pid>/task/<tid>/stack
```

## Logs

```bash
dmesg -T | grep -Ei 'io_uring|uring|iou-wrk|iou-sqp|direct I/O|O_DIRECT|EINVAL|ENOMEM|EAGAIN'
journalctl -k --since '2026-06-02 10:00:00' --until '2026-06-02 10:30:00' \
  | grep -Ei 'io_uring|uring|direct I/O|O_DIRECT|ENOMEM|EINVAL|EAGAIN'
```

## O_DIRECT Alignment

```bash
stat -fc 'fs_type=%T block_size=%s' <mount-point>
blockdev --getss /dev/<device>
blockdev --getpbsz /dev/<device>
findmnt -T <file>
```

Application evidence to request:

- buffer address
- I/O length
- file offset
- file open flags
- filesystem and backing block device

## Compatibility Probe

```bash
grep -R "IORING_OP_" /usr/include/linux/io_uring.h 2>/dev/null | tail
grep -R "IORING_FEAT_" /usr/include/linux/io_uring.h 2>/dev/null
```

Header presence is not proof of runtime support. Prefer a small runtime probe
or application strace evidence when possible.
