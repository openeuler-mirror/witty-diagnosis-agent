/**
 * fault_fragmentation.c -- inject address space fragmentation fault
 * Creates many small mmaps to fragment address space, then tests
 * if a large contiguous mapping is still possible.
 * Uses only MAP_PRIVATE|MAP_ANONYMOUS for reliability.
 */
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <time.h>

#define N 12000

static void *addrs[N];
static volatile int run = 1;
static void hs(int s) { run = 0; }

int main() {
    int ps = getpagesize();
    srand(time(NULL) ^ getpid());
    signal(SIGINT, hs); signal(SIGTERM, hs);

    printf("[FAULT] PID=%d  page_size=%d\n", getpid(), ps);
    printf("[FAULT] Creating %d small mappings...\n", N);

    for (int i = 0; i < N && run; i++) {
        size_t sz = ((size_t)(rand() % 16) + 1) * ps;
        addrs[i] = mmap(NULL, sz, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
        if (addrs[i] == MAP_FAILED) {
            printf("[FAULT] mmap fail at %d (errno=%d)\n", i, errno);
            addrs[i] = NULL;
            break;
        }
        if (i % 2000 == 0) printf("[FAULT] %d mappings\n", i);
    }
    printf("[FAULT] Created %d VMA regions\n", N);

    printf("[FAULT] Attempting 1GB mmap...\n");
    void *h = mmap(NULL, 1024UL*1024*1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (h == MAP_FAILED)
        printf("[FAULT] 1GB mmap FAILED errno=%d - fragmentation confirmed\n", errno);
    else {
        printf("[FAULT] 1GB mmap OK\n");
        munmap(h, 1024UL*1024*1024);
    }

    printf("[FAULT] Pausing 30s for diagnostics...\n");
    sleep(30);

    for (int i = 0; i < N; i++) if (addrs[i]) munmap(addrs[i], 4096);
    printf("[FAULT] Done\n");
    return 0;
}
