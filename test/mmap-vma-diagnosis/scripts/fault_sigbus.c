/**
 * fault_sigbus.c — 注入 SIGBUS 文件截断故障
 *
 * 流程:
 * 1. 创建临时文件并写入数据
 * 2. mmap 映射整个页面（4096 bytes）
 * 3. ftruncate 截断到 0
 * 4. 访问映射页面（已不存在于文件中）→ SIGBUS
 */
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <errno.h>

void sigbus_handler(int sig) {
    write(STDERR_FILENO, "[FAULT] Caught SIGBUS (expected) — bus error on mmap'd file\n", 60);
    _exit(0);
}

int main() {
    int fd;
    char template[] = "/tmp/fault_sigbus_XXXXXX";
    void *addr;
    int page_size = getpagesize();
    volatile char c;

    signal(SIGBUS, sigbus_handler);

    /* 创建临时文件 */
    fd = mkstemp(template);
    if (fd < 0) { perror("mkstemp"); return 1; }
    unlink(template);  /* 删除目录项，但 fd 仍然有效 */

    /* 写入一个页的数据 */
    char *buf = malloc(page_size);
    memset(buf, 'A', page_size);
    write(fd, buf, page_size);
    fsync(fd);
    free(buf);

    printf("[FAULT] PID=%d  文件已写入 %d bytes\n", getpid(), page_size);

    /* mmap 映射 */
    addr = mmap(NULL, page_size, PROT_READ, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED) { perror("mmap"); close(fd); return 1; }
    printf("[FAULT] mmap 成功: addr=%p  size=%d\n", addr, page_size);

    /* 先读一页让缺页异常填充页表 */
    c = ((volatile char *)addr)[0];
    printf("[FAULT] 读取 addr[0]=%c  OK\n", c);

    /* 截断文件到 0 */
    printf("[FAULT] ftruncate 到 0...\n");
    if (ftruncate(fd, 0) == -1) { perror("ftruncate"); close(fd); return 1; }
    close(fd);

    /* 关键: 用 msync 让内核重新检查文件大小，触发 SIGBUS */
    printf("[FAULT] msync 触发缺页检查...\n");
    if (msync(addr, page_size, MS_SYNC) == -1) {
        printf("[FAULT] msync failed: errno=%d (%m)\n", errno);
    }

    /* 再次访问映射页面 — 文件已被截断，内核应发 SIGBUS */
    printf("[FAULT] 访问映射页面 -> 期待 SIGBUS...\n");
    c = ((volatile char *)addr)[0];
    (void)c;

    /* 不会到达这里 */
    printf("[FAULT] 未触发 SIGBUS（异常）\n");
    munmap(addr, page_size);
    return 0;
}
