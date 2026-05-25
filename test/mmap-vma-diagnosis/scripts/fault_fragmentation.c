/**
 * fault_fragmentation.c — 注入地址空间碎片化故障
 *
 * 流程:
 * 1. 创建大量小 mmap 映射（4KB~64KB 交错分布）
 * 2. 同时创建线程栈来制造更多 VMA 碎片
 * 3. 最后尝试大块 mmap(1GB) 触发 ENOMEM
 */
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>

#define SMALL_MAPS  10000
#define THREADS     50

volatile int running = 1;
void *small_addrs[SMALL_MAPS] = {0};
pthread_t threads[THREADS];

void *thread_func(void *arg) {
    int tid = *(int *)arg;
    // 每个线程在自己的栈周围创建交错映射
    for (int i = 0; i < 50; i++) {
        size_t size = (tid % 5 + 1) * 4096;  // 4K ~ 20K
        void *addr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (addr == MAP_FAILED) break;
        // 用 mlock 让这些映射不可合并
        mlock(addr, 4096);
        // 不保存指针，让这些映射成为"碎片"
    }
    while (running) usleep(100000);
    return NULL;
}

void handle_signal(int sig) {
    running = 0;
}

int main() {
    int page_size = getpagesize();
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    printf("[FAULT] PID=%d  page_size=%d\n", getpid(), page_size);
    printf("[FAULT] 开始创建地址空间碎片...\n");

    // 阶段1: 创建大量大小不一的匿名映射
    for (int i = 0; i < SMALL_MAPS; i++) {
        size_t size = (rand() % 16 + 1) * page_size;  // 4K ~ 64K
        void *addr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (addr == MAP_FAILED) {
            printf("[FAULT] 小映射已创建 %d 个后失败\n", i);
            break;
        }
        small_addrs[i] = addr;
        if (i % 2000 == 0) printf("[FAULT] 已创建 %d 个小映射\n", i);
    }
    printf("[FAULT] 小映射创建完毕，当前 VMA 数量高\n");

    // 阶段2: 启动线程创建交错碎片
    printf("[FAULT] 启动 %d 个线程创建交错碎片...\n", THREADS);
    for (int i = 0; i < THREADS; i++) {
        int *tid = malloc(sizeof(int));
        *tid = i;
        if (pthread_create(&threads[i], NULL, thread_func, tid) != 0) {
            printf("[FAULT] 线程 %d 创建失败\n", i);
            free(tid);
        }
        usleep(10000);  // 交错启动
    }
    sleep(2);

    // 阶段3: 尝试大块映射
    printf("[FAULT] 尝试大块 mmap(1GB)...\n");
    size_t huge_size = 1024UL * 1024 * 1024;
    void *huge = mmap(NULL, huge_size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (huge == MAP_FAILED) {
        printf("[FAULT] 大块 mmap(1GB) 失败 errno=%d (%m) ← 预期碎片化\n", errno);
    } else {
        printf("[FAULT] 大块 mmap(1GB) 成功 (地址空间较充裕)\n");
        munmap(huge, huge_size);
    }

    printf("[FAULT] 暂停 30 秒等待诊断脚本检查碎片状态...\n");
    sleep(30);

    // 清理
    running = 0;
    for (int i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    for (int i = 0; i < SMALL_MAPS; i++) {
        if (small_addrs[i]) {
            munmap(small_addrs[i], (rand() % 16 + 1) * page_size);
        }
    }
    printf("[FAULT] 清理完毕\n");
    return 0;
}
