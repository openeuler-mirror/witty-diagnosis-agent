/*
 * fault_mmap_anon_leak.c — Anonymous mmap leak simulator (Branch B2)
 * Maps anonymous pages repeatedly without munmap.
 * Usage: ./fault_mmap_anon_leak [MB_per_sec] [duration_sec]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

volatile int running = 1;
void handle_sigint(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    int mb_per_sec = argc > 1 ? atoi(argv[1]) : 10;
    int duration = argc > 2 ? atoi(argv[2]) : 0;
    signal(SIGINT, handle_sigint);

    printf("[fault_mmap_anon_leak] PID=%d leaking %d MB/s via mmap\n", getpid(), mb_per_sec);
    if (duration > 0) printf("  for %d seconds\n", duration);

    long page_size = sysconf(_SC_PAGESIZE);
    size_t chunk_size = mb_per_sec * 1024UL * 1024UL;
    /* Round up to page boundary */
    chunk_size = ((chunk_size + page_size - 1) / page_size) * page_size;

    /* Store mmap addresses to prevent COW merging (keep them "active") */
    void **maps = malloc(sizeof(void*) * 1024);
    int map_count = 0, cap = 1024;
    int iter = 0;

    while (running) {
        void *p = mmap(NULL, chunk_size, PROT_READ|PROT_WRITE,
                       MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
        if (p == MAP_FAILED) {
            fprintf(stderr, "mmap failed at iteration %d\n", iter);
            break;
        }
        /* Touch pages to ensure physical memory allocation */
        memset(p, 0xBB, chunk_size);

        if (map_count >= cap) {
            cap *= 2;
            maps = realloc(maps, sizeof(void*) * cap);
        }
        maps[map_count++] = p;

        iter++;
        printf("[%d] mmap leaked %d MB (total ~%d MB)\n", iter, mb_per_sec, iter * mb_per_sec);
        sleep(1);
        if (duration > 0 && iter >= duration) break;
    }

    printf("[fault_mmap_anon_leak] Done. %d mmaps, ~%d MB total.\n", map_count, iter * mb_per_sec);
    /* Keep mappings until process exits */
    pause();
    return 0;
}
