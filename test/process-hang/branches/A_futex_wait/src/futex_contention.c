/*
 * futex_contention.c — 模拟 Branch A: futex 锁等待
 *
 * 创建多个线程竞争同一把 mutex，每个线程持有锁后进行"耗时操作"（usleep），
 * 导致其他线程在 futex 上排队等待。
 *
 * 诊断特征:
 *   - wchan = futex_wait_queue_me
 *   - State = S (sleeping)
 *   - 多个线程 TID wchan 均为 futex_wait_queue_me
 *   - wait_sum 持续增长
 */

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

#define NUM_THREADS 8
#define HOLD_TIME_US 500000  /* 500ms — 足够让其他线程在 futex 上排队 */

pthread_mutex_t global_mutex = PTHREAD_MUTEX_INITIALIZER;
volatile int running = 1;

void *worker(void *arg) {
    int tid = *(int *)arg;
    free(arg);

    printf("[TID %d] 启动\n", tid);
    while (running) {
        pthread_mutex_lock(&global_mutex);
        /* 持锁做"耗时操作" — 其他线程在此处排队 */
        usleep(HOLD_TIME_US);
        pthread_mutex_unlock(&global_mutex);
        /* 短暂释放后再次竞争 */
        usleep(1000);
    }
    printf("[TID %d] 退出\n", tid);
    return NULL;
}

int main() {
    pthread_t threads[NUM_THREADS];
    int i;

    printf("=== Futex 锁等待故障注入 ===\n");
    printf("线程数: %d, 持锁时间: %d us\n", NUM_THREADS, HOLD_TIME_US);
    printf("PID: %d\n", getpid());
    printf("=== 故障已注入，等待诊断... ===\n");
    fflush(stdout);

    /* 启动多个线程竞争同一把锁 */
    for (i = 0; i < NUM_THREADS; i++) {
        int *tid = malloc(sizeof(int));
        *tid = i + 1;
        if (pthread_create(&threads[i], NULL, worker, tid) != 0) {
            fprintf(stderr, "线程创建失败: %s\n", strerror(errno));
            running = 0;
            return 1;
        }
    }

    /* 主线程也参与锁竞争 */
    {
        int tid_main = 0;
        while (running) {
            pthread_mutex_lock(&global_mutex);
            usleep(HOLD_TIME_US);
            pthread_mutex_unlock(&global_mutex);
            usleep(1000);
        }
    }

    /* 等待所有线程结束（实际不会到达此处，除非收到 SIGTERM） */
    for (i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    return 0;
}
