/**
 * fault_mlock_limit.c — 注入 mlock 超限故障
 *
 * 流程:
 * 1. 读取当前 RLIMIT_MEMLOCK
 * 2. 分配大于限制的内存
 * 3. mlock 应返回 ENOMEM
 */
#include <sys/mman.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

int main() {
    struct rlimit lim;
    unsigned long limit_kb;

    getrlimit(RLIMIT_MEMLOCK, &lim);
    printf("[FAULT] PID=%d\n", getpid());
    printf("[FAULT] RLIMIT_MEMLOCK: soft=%ld KB  hard=%ld KB\n",
           (long)lim.rlim_cur / 1024, (long)lim.rlim_max / 1024);

    if (lim.rlim_cur == RLIM_INFINITY) {
        printf("[FAULT] memlock 无限制，尝试锁定 1GB...\n");
        limit_kb = 1024 * 1024;
    } else {
        limit_kb = (lim.rlim_cur / 1024) + 1;  /* 超过限制 1KB */
        printf("[FAULT] 尝试锁定 %lu KB (超过限制)...\n", limit_kb);
    }

    /* 使用 MAP_PRIVATE|MAP_ANONYMOUS 分配并锁定 */
    void *addr = mmap(NULL, limit_kb * 1024, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (addr == MAP_FAILED) { perror("mmap"); return 1; }

    memset(addr, 0, limit_kb * 1024);

    if (mlock(addr, limit_kb * 1024) == -1) {
        printf("[FAULT] mlock FAILED  errno=%d (%m)\n", errno);
        munmap(addr, limit_kb * 1024);
        return 0;
    }

    printf("[FAULT] mlock SUCCESS（尝试锁定 %lu KB）\n", limit_kb);
    /* 读回确认 */
    volatile char c = ((volatile char *)addr)[0];
    printf("[FAULT] 锁定内存内容验证: %c\n", c ? '?' : '0');
    munlock(addr, limit_kb * 1024);
    munmap(addr, limit_kb * 1024);
    return 0;
}
