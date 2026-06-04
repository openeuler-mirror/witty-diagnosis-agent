/*
 * fault_shm_leak.c — 共享内存泄漏模拟器 (Branch A5)
 * 通过 shmget/shmat 分配共享内存段后不 shmdt/shmctl(IPC_RMID)
 * 导致共享内存段持续累积
 *
 * Usage: ./fault_shm_leak [segments_per_sec] [size_mb] [duration_sec]
 * Default: 2 segments/sec, 1MB each, unlimited
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <time.h>

volatile int running = 1;
void handle_sigint(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    int seg_per_sec = argc > 1 ? atoi(argv[1]) : 2;
    int size_mb = argc > 2 ? atoi(argv[2]) : 1;
    int duration = argc > 3 ? atoi(argv[3]) : 0;
    signal(SIGINT, handle_sigint);

    size_t shm_size = size_mb * 1024 * 1024;
    int iter = 0;
    int leaked_shmids[10000];
    int shm_count = 0;

    printf("[fault_shm_leak] PID=%d leaking %d shm segments/sec (%d MB each)\n",
           getpid(), seg_per_sec, size_mb);
    if (duration > 0) printf("  for %d seconds\n", duration);

    srand(time(NULL));

    while (running) {
        for (int i = 0; i < seg_per_sec; i++) {
            int shmid = shmget(IPC_PRIVATE, shm_size, IPC_CREAT | 0666);
            if (shmid < 0) {
                perror("shmget failed");
                break;
            }
            void *addr = shmat(shmid, NULL, 0);
            if (addr == (void*)-1) {
                perror("shmat failed");
                continue;
            }
            /* Touch pages */
            memset(addr, 0xCC, shm_size);

            if (shm_count < 10000)
                leaked_shmids[shm_count++] = shmid;
            /* Deliberately do NOT shmdt or IPC_RMID — this IS the leak */
        }
        iter++;
        printf("[%d] Leaked %d segments (%d MB total)\n",
               iter, iter * seg_per_sec * size_mb);
        fflush(stdout);
        sleep(1);
        if (duration > 0 && iter >= duration) break;
    }

    printf("[fault_shm_leak] Done. Leaked ~%d MB total.\n",
           iter * seg_per_sec * size_mb);
    /* Keep segments alive until process exits */
    pause();
    return 0;
}
