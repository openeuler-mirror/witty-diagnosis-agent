/**
 * fault_frag_simple.c -- simplified address space fragmentation test
 * Creates many small mmaps then attempts a large one
 */
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#define N 5000
int main() {
    void *a[N] = {0};
    printf("[FAULT] PID=%d\n", getpid());
    printf("[FAULT] Creating %d small mappings...\n", N);
    for (int i = 0; i < N; i++) {
        a[i] = mmap(0, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
        if (a[i] == MAP_FAILED) {
            printf("[FAULT] Fail at %d (errno=%d)\n", i, errno); break;
        }
        if (i % 1000 == 0) printf("[FAULT] Created %d mappings\n", i);
    }
    printf("[FAULT] Attempting large mmap(256MB)...\n");
    void *h = mmap(0, 256*1024*1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (h == MAP_FAILED)
        printf("[FAULT] Large mmap FAILED errno=%d - fragmentation confirmed\n", errno);
    else {
        printf("[FAULT] Large mmap OK (still has room)\n");
        munmap(h, 256*1024*1024);
    }
    for (int i = 0; i < N; i++) if (a[i]) munmap(a[i], 4096);
    printf("[FAULT] Done\n");
    return 0;
}
