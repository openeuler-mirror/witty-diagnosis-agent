/*
 * fault_heap_leak.c — Heap memory leak simulator (Branch A1/C1)
 * Gradually allocates memory without freeing.
 * Usage: ./fault_heap_leak [MB_per_sec] [duration_sec]
 * Default: 10 MB/sec, unlimited duration
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>

volatile int running = 1;
void handle_sigint(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    int mb_per_sec = argc > 1 ? atoi(argv[1]) : 10;
    int duration = argc > 2 ? atoi(argv[2]) : 0;
    signal(SIGINT, handle_sigint);

    printf("[fault_heap_leak] PID=%d leaking at %d MB/s", getpid(), mb_per_sec);
    if (duration > 0) printf(" for %d seconds", duration);
    printf("\n");

    int chunk_size = mb_per_sec * 1024 * 1024;  /* 1 second worth */
    int iter = 0;

    while (running) {
        void *p = malloc(chunk_size);
        if (!p) { fprintf(stderr, "malloc failed at iteration %d\n", iter); break; }
        memset(p, 0xAA, chunk_size);  /* actually touch the pages */
        /* Keep a reference by writing pointer to a global-ish location */
        /* Deliberately do NOT free — this IS the leak */
        iter++;
        printf("[%d] Leaked %d MB (total ~%d MB)\n", iter, mb_per_sec, iter * mb_per_sec);
        sleep(1);
        if (duration > 0 && iter >= duration) break;
    }
    printf("[fault_heap_leak] Done. Leaked %d MB total.\n", iter * mb_per_sec);
    return 0;
}
