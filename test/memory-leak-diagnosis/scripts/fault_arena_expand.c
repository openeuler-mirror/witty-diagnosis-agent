/*
 * fault_arena_expand.c — malloc arena 膨胀模拟器 (Branch B3)
 * 多线程反复 malloc/free 不同大小内存块，触发 glibc arena 扩展
 * 模拟 glibc BZ#33886：free chunk 不归还 OS，驻留 RSS
 *
 * Usage: ./fault_arena_expand [threads] [alloc_mb_per_thread] [duration_sec]
 * Default: 4 threads, 50MB each, 30 seconds
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <sys/mman.h>

volatile int running = 1;
int alloc_size;
int thread_mb;

void handle_sigint(int sig) { running = 0; }

void *thread_worker(void *arg) {
    long tid = (long)arg;
    int total_alloc = 0;

    /* Allocate many small chunks to fill arenas */
    while (running && total_alloc < thread_mb * 1024 * 1024) {
        size_t sizes[] = {16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192};
        int num_allocs = 100;
        void *ptrs[100];

        for (int i = 0; i < num_allocs && running; i++) {
            size_t sz = sizes[rand() % 10];
            ptrs[i] = malloc(sz);
            if (ptrs[i]) memset(ptrs[i], tid & 0xFF, sz);
        }

        /* Free half to create fragmented free chunks */
        for (int i = 0; i < num_allocs; i += 2) {
            if (ptrs[i]) free(ptrs[i]);
        }
        /* Keep the other half to pin the arena */

        total_alloc += num_allocs * 512; /* avg */
        usleep(10000); /* 10ms */
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    int num_threads = argc > 1 ? atoi(argv[1]) : 4;
    thread_mb = argc > 2 ? atoi(argv[2]) : 50;
    int duration = argc > 3 ? atoi(argv[3]) : 30;
    signal(SIGINT, handle_sigint);

    printf("[fault_arena_expand] PID=%d %d threads, %d MB each\n",
           getpid(), num_threads, thread_mb);
    printf("  Simulating glibc malloc arena hoarding (BZ#33886)\n");

    pthread_t threads[64];
    for (long i = 0; i < num_threads && i < 64; i++) {
        pthread_create(&threads[i], NULL, thread_worker, (void*)i);
    }

    /* Phase 1: Allocate */
    for (int i = 0; i < duration && running; i++) {
        printf("[%d] %d threads active, RSS in /proc/self/status:\n", i+1, num_threads);
        fflush(stdout);
        /* Read RSS */
        FILE *f = fopen("/proc/self/status", "r");
        if (f) {
            char line[256];
            while (fgets(line, sizeof(line), f) && running) {
                if (strncmp(line, "VmRSS:", 6) == 0)
                    printf("  %s", line);
            }
            fclose(f);
        }
        sleep(1);
    }

    /* Phase 2: Free everything — but glibc may hold the memory */
    running = 0;
    printf("\n[Phase 2] Freeing all...\n");
    sleep(2);

    /* Check RSS after free — should be high if arena hoarding */
    printf("\n[fault_arena_expand] RSS after free:\n");
    FILE *f = fopen("/proc/self/status", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "VmRSS:", 6) == 0)
                printf("  %s", line);
        }
        fclose(f);
    }
    printf("\n  Try: malloc_trim(0) to recover hoarded memory\n");
    pause();
    return 0;
}
