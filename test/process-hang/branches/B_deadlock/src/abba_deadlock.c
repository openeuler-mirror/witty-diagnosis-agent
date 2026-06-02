/*
 * abba_deadlock.c — 模拟 Branch B: ABBA 死锁
 *
 * 经典死锁模式:
 *   Thread 1: 持有 Lock A → 等待 Lock B
 *   Thread 2: 持有 Lock B → 等待 Lock A
 *
 * 诊断特征:
 *   - 多线程 wchan = futex_wait_queue_me
 *   - gdb thread apply all bt 显示锁等待环
 *   - 死锁环: T1(L1→L2) ↔ T2(L2→L1)
 */

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

pthread_mutex_t lock_a = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t lock_b = PTHREAD_MUTEX_INITIALIZER;
volatile int running = 1;

void *thread1(void *arg) {
    printf("[Thread 1] 启动, 等待获取 Lock A ...\n");
    pthread_mutex_lock(&lock_a);
    printf("[Thread 1] 获得 Lock A, sleep 1s 确保 Thread 2 获得 Lock B ...\n");
    sleep(1);

    printf("[Thread 1] 尝试获取 Lock B (持有 Lock A) ...\n");
    pthread_mutex_lock(&lock_b);  /* 死锁: Thread 2 持有 Lock B */
    printf("[Thread 1] 获得 Lock B (这行永远不会执行)\n");

    pthread_mutex_unlock(&lock_b);
    pthread_mutex_unlock(&lock_a);
    return NULL;
}

void *thread2(void *arg) {
    printf("[Thread 2] 启动, 等待获取 Lock B ...\n");
    pthread_mutex_lock(&lock_b);
    printf("[Thread 2] 获得 Lock B, sleep 1s 确保 Thread 1 获得 Lock A ...\n");
    sleep(1);

    printf("[Thread 2] 尝试获取 Lock A (持有 Lock B) ...\n");
    pthread_mutex_lock(&lock_a);  /* 死锁: Thread 1 持有 Lock A */
    printf("[Thread 2] 获得 Lock A (这行永远不会执行)\n");

    pthread_mutex_unlock(&lock_a);
    pthread_mutex_unlock(&lock_b);
    return NULL;
}

void sigterm_handler(int sig) {
    (void)sig;
    running = 0;
}

int main() {
    pthread_t t1, t2;

    signal(SIGTERM, sigterm_handler);

    printf("=== ABBA 死锁故障注入 ===\n");
    printf("PID: %d\n", getpid());
    printf("死锁模式: Thread1(LockA→LockB) ↔ Thread2(LockB→LockA)\n");
    printf("=== 故障已注入，等待诊断... ===\n");
    fflush(stdout);

    if (pthread_create(&t1, NULL, thread1, NULL) != 0) {
        fprintf(stderr, "Thread 1 创建失败: %s\n", strerror(errno));
        return 1;
    }
    if (pthread_create(&t2, NULL, thread2, NULL) != 0) {
        fprintf(stderr, "Thread 2 创建失败: %s\n", strerror(errno));
        return 1;
    }

    /* 等待线程（死锁后永不到达） */
    pthread_join(t1, NULL);
    pthread_join(t2, NULL);
    return 0;
}
