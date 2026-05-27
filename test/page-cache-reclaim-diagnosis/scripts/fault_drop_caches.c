/**
 * fault_drop_caches.c -- inject drop_caches + IO storm
 */
#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <time.h>

#define FILE_SIZE  (256UL * 1024 * 1024)
#define PAGE_SIZE  4096
#define REPORT_EVERY 10000

volatile int running = 1;
struct timespec t1, t2;
void handle_signal(int sig) { running = 0; }
double es(struct timespec *s, struct timespec *e) {
    return (e->tv_sec - s->tv_sec) + (e->tv_nsec - s->tv_nsec) / 1e9; }

int main() {
    signal(SIGINT, handle_signal); signal(SIGTERM, handle_signal);
    char tmpl[] = "/tmp/fault_drop_XXXXXX";
    int fd = mkstemp(tmpl); if (fd < 0) { perror("mkstemp"); return 1; }
    unlink(tmpl);
    printf("[FAULT] PID=%d  Drop caches + IO storm injector\n", getpid());
    char *buf = malloc(PAGE_SIZE); if (!buf) { close(fd); return 1; }
    memset(buf, 'A', PAGE_SIZE);
    for (size_t w = 0; w < FILE_SIZE && running; w += PAGE_SIZE) {
        if (write(fd, buf, PAGE_SIZE) < 0) break;
        if ((w / PAGE_SIZE) % REPORT_EVERY == 0)
            printf("[FAULT] Wrote %lu MB\n", w / 1024 / 1024);
    }
    fsync(fd);
    printf("[FAULT] File created, mmap-ing...\n");
    char *addr = mmap(NULL, FILE_SIZE, PROT_READ, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED) { close(fd); free(buf); return 1; }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("[FAULT] 1st pass (populate page cache)...\n");
    for (size_t i = 0; i < FILE_SIZE && running; i += PAGE_SIZE) {
        volatile char c = addr[i]; (void)c;
        if ((i / PAGE_SIZE) % REPORT_EVERY == 0) printf("[FAULT] Read %lu MB\n", i/1024/1024);
    }
    clock_gettime(CLOCK_MONOTONIC, &t2);
    printf("[FAULT] 1st pass: %.2fs\n", es(&t1, &t2));
    system("grep -E '^Cached|^MemFree|^Dirty' /proc/meminfo");
    printf("[FAULT] Dropping caches...\n");
    FILE *dc = fopen("/proc/sys/vm/drop_caches", "w");
    if (dc) { fprintf(dc, "3"); fclose(dc); printf("[FAULT] drop_caches OK\n"); }
    else { printf("[FAULT] drop_caches FAILED (errno=%d)\n", errno); }
    system("grep -E '^Cached|^MemFree|^Dirty' /proc/meminfo");
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("[FAULT] 2nd pass (major faults expected)...\n");
    for (size_t i = 0; i < FILE_SIZE && running; i += PAGE_SIZE) {
        volatile char c = addr[i]; (void)c;
        if ((i / PAGE_SIZE) % REPORT_EVERY == 0) printf("[FAULT] Re-read %lu MB\n", i/1024/1024);
    }
    clock_gettime(CLOCK_MONOTONIC, &t2);
    printf("[FAULT] 2nd pass: %.2fs (should be slower due to disk IO)\n", es(&t1, &t2));
    printf("[FAULT] Pausing 30s for diagnostics...\n");
    sleep(30);
    munmap(addr, FILE_SIZE); close(fd); free(buf);
    printf("[FAULT] Done\n");
    return 0;
}
