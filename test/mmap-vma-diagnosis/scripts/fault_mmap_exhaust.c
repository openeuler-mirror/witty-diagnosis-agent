/**
 * fault_mmap_exhaust.c — 注入 vm.max_map_count 耗尽故障
 *
 * 创建大量匿名 mmap 直到 ENOMEM，保留映射以便诊断脚本检查。
 * 设置较低的 max_map_count 以快速触发。
 */
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>

volatile int running = 1;
int map_count = 0;

void handle_signal(int sig) {
    running = 0;
}

int main() {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    int page_size = getpagesize();
    long max_map = 0;

    FILE *f = fopen("/proc/sys/vm/max_map_count", "r");
    if (f) { fscanf(f, "%ld", &max_map); fclose(f); }

    printf("[FAULT] PID=%d  page_size=%d  max_map_count=%ld\n",
           getpid(), page_size, max_map);
    printf("[FAULT] 开始耗尽 mmap (PROT_READ|PROT_WRITE)...\n");

    /* 用 PROT_READ 创建匿名映射，这种方式计入 VMA */
    while (running) {
        void *addr = mmap(NULL, page_size, PROT_READ,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (addr == MAP_FAILED) {
            printf("[FAULT] mmap FAILED at count=%d  errno=%d (%m)\n",
                   map_count, errno);
            break;
        }
        map_count++;
        if (map_count % 500 == 0)
            printf("[FAULT] 已创建 %d 个映射\n", map_count);
    }

    printf("[FAULT] 总共创建 %d 个映射后失败\n", map_count);

    /* 保持所有映射存在，以便诊断脚本收集数据 */
    printf("[FAULT] 保持映射，暂停 60 秒等待诊断...\n");
    sleep(60);

    printf("[FAULT] 退出\n");
    return 0;
}
