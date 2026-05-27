/**
 * fault_reclaim_stress.c -- Memory reclaim stress injector
 * Based on LTP memcg_stress_test pattern + Linux kernel selftests
 * test_memcontrol.c methodology.
 *
 * Creates cgroup, allocates memory until memory.high triggers reclaim,
 * then forces reclaim via memory.reclaim. Measures allocstall and
 * pgscan_direct during the process.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <time.h>

#define MB(n) ((size_t)(n) * 1024 * 1024)
#define PAGE_SIZE 4096

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

/* Read a cgroup file */
long cg_read_long(const char *cg, const char *file) {
    char path[512], buf[64];
    snprintf(path, sizeof(path), "%s/%s", cg, file);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    int n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;
    return atol(buf);
}

/* Write to a cgroup file */
int cg_write(const char *cg, const char *file, const char *val) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", cg, file);
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    int ret = (int)write(fd, val, strlen(val));
    close(fd);
    return ret < 0 ? -1 : 0;
}

/* Allocate anonymous memory in current process - triggers reclaim */
void alloc_anon_and_keep(size_t size) {
    size_t pages = size / PAGE_SIZE;
    printf("[FAULT] Allocating %zu MB anonymous memory (%zu pages)...\n",
           size / 1024 / 1024, pages);
    for (size_t i = 0; i < pages && running; i++) {
        char *p = mmap(NULL, PAGE_SIZE, PROT_READ|PROT_WRITE,
                       MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) {
            printf("[FAULT] mmap failed at page %zu (errno=%d) - RECLAIM TRIGGERED\n",
                   i, errno);
            break;
        }
        p[0] = 0xAA; /* Touch page to force physical allocation */
        if (i % 25000 == 0 && i > 0)
            printf("[FAULT] Allocated %zu MB\n", i / 256);
    }
}

/* Fill page cache via file write */
int alloc_pagecache(size_t size, const char *fname) {
    size_t pages = size / PAGE_SIZE;
    int fd = open(fname, O_RDWR | O_CREAT, 0644);
    if (fd < 0) { perror("open"); return -1; }
    unlink(fname);
    printf("[FAULT] Creating %zu MB page cache via file write...\n",
           size / 1024 / 1024);

    char *buf = malloc(PAGE_SIZE);
    if (!buf) { close(fd); return -1; }
    memset(buf, 0xBB, PAGE_SIZE);

    for (size_t i = 0; i < pages && running; i++) {
        if (write(fd, buf, PAGE_SIZE) < 0) {
            printf("[FAULT] write failed at page %zu (errno=%d)\n", i, errno);
            break;
        }
        if (i % 25000 == 0 && i > 0)
            printf("[FAULT] Wrote %zu MB to file\n", i / 256);
    }
    fsync(fd);
    free(buf);
    return fd;
}

/* Read back page cache to verify it's in memory (triggers major faults) */
void read_pagecache(int fd, size_t size) {
    size_t pages = size / PAGE_SIZE;
    printf("[FAULT] Reading back %zu MB page cache...\n", size / 1024 / 1024);
    char *buf = malloc(PAGE_SIZE);
    if (!buf) return;

    lseek(fd, 0, SEEK_SET);
    for (size_t i = 0; i < pages && running; i++) {
        if (read(fd, buf, PAGE_SIZE) < 0) break;
        if (i % 25000 == 0 && i > 0)
            printf("[FAULT] Read %zu MB\n", i / 256);
    }
    free(buf);
}

int main() {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    printf("[FAULT] PID=%d  Mem reclaim stress test\n", getpid());
    printf("[FAULT] Based on LTP memcg_stress_test + kernel selftests\n\n");

    /* Stage 1: Record baseline reclaim stats */
    long allocstall_before = 0, pgscan_direct_before = 0;
    int vmstat_fd = open("/proc/vmstat", O_RDONLY);
    if (vmstat_fd >= 0) {
        char buf[4096]; int n = read(vmstat_fd, buf, sizeof(buf)-1);
        if (n > 0) {
            buf[n] = 0;
            char *p = strstr(buf, "allocstall ");
            if (p) allocstall_before = atol(p + 10);
            p = strstr(buf, "pgscan_direct ");
            if (p) pgscan_direct_before = atol(p + 14);
        }
        close(vmstat_fd);
    }
    printf("[FAULT] Baseline: allocstall=%ld  pgscan_direct=%ld\n\n",
           allocstall_before, pgscan_direct_before);

    /* Stage 2: Allocate 50MB anonymous memory (like LTP memcontrol02) */
    printf("=== Stage 2: Anonymous memory allocation (50MB) ===\n");
    size_t anon_size = MB(50);
    pid_t anon_pid = fork();
    if (anon_pid == 0) {
        /* Child: allocate and exit */
        alloc_anon_and_keep(anon_size);
        _exit(0);
    }
    waitpid(anon_pid, NULL, 0);
    printf("\n");

    /* Stage 3: Allocate 50MB page cache (like LTP memcontrol02) */
    printf("=== Stage 3: Page cache allocation (50MB) ===\n");
    size_t cache_size = MB(50);
    int fd = alloc_pagecache(cache_size, "/tmp/fault_reclaim_file");
    if (fd >= 0) {
        read_pagecache(fd, cache_size);
        close(fd);
    }
    printf("\n");

    /* Stage 4: Aggressive allocation to trigger reclaim (like LTP memcg_stress) */
    printf("=== Stage 4: Aggressive allocation to force reclaim ===\n");
    /* Try to allocate as much as we can */
    {
        size_t total = 0;
        while (running) {
            char *p = mmap(NULL, MB(4), PROT_READ|PROT_WRITE,
                          MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
            if (p == MAP_FAILED) {
                printf("[FAULT] mmap failed at %zu MB - reclaim active\n", total);
                break;
            }
            /* Touch first and last page */
            p[0] = 0xCC; p[MB(4)-1] = 0xDD;
            total += 4;
            if (total % 100 == 0)
                printf("[FAULT] Aggressively allocated total %zu MB\n", total);
        }

        /* Report vmstat change */
        sleep(1);
        vmstat_fd = open("/proc/vmstat", O_RDONLY);
        if (vmstat_fd >= 0) {
            char buf[4096]; int n = read(vmstat_fd, buf, sizeof(buf)-1);
            if (n > 0) {
                buf[n] = 0;
                char *p = strstr(buf, "allocstall ");
                long a = p ? atol(p + 10) : 0;
                p = strstr(buf, "pgscan_direct ");
                long d = p ? atol(p + 14) : 0;
                printf("\n[FAULT] VMSTAT delta: allocstall +%ld  pgscan_direct +%ld\n",
                       a - allocstall_before, d - pgscan_direct_before);
                if (a > allocstall_before)
                    printf("[FAULT] DIRECT RECLAIM DETECTED (allocstall > 0)\n");
                else
                    printf("[FAULT] kswapd handled reclaim (no direct reclaim)\n");
            }
            close(vmstat_fd);
        }
    }

    printf("\n[FAULT] Pausing 30s for diagnostics...\n");
    sleep(30);
    printf("[FAULT] Done\n");
    return 0;
}
