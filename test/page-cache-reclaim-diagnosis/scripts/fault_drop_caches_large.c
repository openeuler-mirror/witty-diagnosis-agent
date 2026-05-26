/**
 * fault_drop_caches_large.c -- Simulate drop_caches + major fault storm
 * Based on real-world scenarios where echo 3 > drop_caches causes
 * massive page cache refill I/O.
 *
 * Creates 1GB test file, fills page cache via mmap+read, drops caches,
 * then re-reads to trigger major faults. Measures timing differences.
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

#define FILE_SIZE  (1024UL * 1024 * 1024)  /* 1GB */
#define PAGE_SIZE  4096
#define REPORT_EVERY 32000

volatile int running = 1;
struct timespec t1, t2;
void handle_signal(int sig) { running = 0; }
double es(struct timespec *s, struct timespec *e) {
    return (e->tv_sec - s->tv_sec) + (e->tv_nsec - s->tv_nsec) / 1e9; }

int main() {
    signal(SIGINT, handle_signal); signal(SIGTERM, handle_signal);
    char tmpl[] = "/tmp/fault_drop_large_XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) { perror("mkstemp"); return 1; }
    unlink(tmpl);

    printf("[FAULT] PID=%d  drop_caches + I/O storm (1GB)\n", getpid());

    /* Write 1GB file */
    printf("[FAULT] Creating 1GB file...\n");
    fallocate(fd, 0, 0, FILE_SIZE);
    char *buf = malloc(PAGE_SIZE);
    memset(buf, 'A', PAGE_SIZE);
    for (size_t w = 0; w < FILE_SIZE; w += PAGE_SIZE)
        write(fd, buf, PAGE_SIZE);
    fsync(fd);
    printf("[FAULT] File created.\n");

    /* mmap the file */
    char *addr = mmap(NULL, FILE_SIZE, PROT_READ, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED) { perror("mmap"); close(fd); free(buf); return 1; }

    /* Phase 1: Populate page cache */
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("[FAULT] Phase 1: Reading 1GB (populate page cache)...\n");
    for (size_t i = 0; i < FILE_SIZE && running; i += PAGE_SIZE) {
        volatile char c = addr[i]; (void)c;
        if ((i / PAGE_SIZE) % REPORT_EVERY == 0)
            printf("[FAULT] Read %lu MB\n", i / 1024 / 1024);
    }
    clock_gettime(CLOCK_MONOTONIC, &t2);
    printf("[FAULT] Phase 1 (with page cache): %.3f sec\n", es(&t1, &t2));
    printf("[FAULT] meminfo before:\n");
    system("grep -E '^Cached|^MemFree|^MemAvailable|^Dirty|^Writeback' /proc/meminfo");

    /* Phase 2: Drop caches */
    printf("[FAULT] Phase 2: Dropping caches...\n");
    FILE *dc = fopen("/proc/sys/vm/drop_caches", "w");
    if (dc) { fprintf(dc, "3"); fclose(dc); printf("[FAULT] drop_caches done\n"); }
    else { printf("[FAULT] drop_caches FAILED (errno=%d)\n", errno); }
    printf("[FAULT] meminfo after:\n");
    system("grep -E '^Cached|^MemFree|^MemAvailable|^Dirty|^Writeback' /proc/meminfo");

    /* Phase 3: Re-read – triggers major page faults, should be slower */
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("[FAULT] Phase 3: Re-reading 1GB (should trigger major faults)...\n");
    for (size_t i = 0; i < FILE_SIZE && running; i += PAGE_SIZE) {
        volatile char c = addr[i]; (void)c;
        if ((i / PAGE_SIZE) % REPORT_EVERY == 0)
            printf("[FAULT] Re-read %lu MB\n", i / 1024 / 1024);
    }
    clock_gettime(CLOCK_MONOTONIC, &t2);
    double p2 = es(&t1, &t2);
    printf("[FAULT] Phase 3 (after drop_caches): %.3f sec\n", p2);

    /* Report major fault delta */
    printf("[FAULT] Major fault check:\n");
    system("grep -E 'pgmajfault|pgfault' /proc/vmstat | head -4");

    printf("[FAULT] Pausing 30s for diagnostics...\n");
    sleep(30);
    munmap(addr, FILE_SIZE); close(fd); free(buf);
    printf("[FAULT] Done\n");
    return 0;
}
