/**
 * fault_dirty_storm.c -- inject dirty page writeback storm
 */
#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <time.h>

#define CHUNK_SIZE (4UL * 1024 * 1024)
#define TOTAL_SIZE (512UL * 1024 * 1024)
#define REPORT_EVERY 5

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

int main() {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    char template[] = "/tmp/fault_dirty_XXXXXX";
    int fd = mkstemp(template);
    if (fd < 0) { perror("mkstemp"); return 1; }
    unlink(template);
    printf("[FAULT] PID=%d  Dirty page writeback storm injector\n", getpid());
    char *buf = malloc(CHUNK_SIZE);
    if (!buf) { perror("malloc"); close(fd); return 1; }
    memset(buf, 'A', CHUNK_SIZE);
    size_t total_written = 0;
    int chunk_count = 0;
    while (total_written < TOTAL_SIZE && running) {
        ssize_t ret = write(fd, buf, CHUNK_SIZE);
        if (ret < 0) { printf("[FAULT] write failed at %lu (errno=%d)\n", total_written, errno); break; }
        total_written += ret;
        chunk_count++;
        if (chunk_count % 3 == 0) {
            off_t sync_start = total_written > CHUNK_SIZE * 6 ? total_written - CHUNK_SIZE * 6 : 0;
            sync_file_range(fd, sync_start, total_written - sync_start, SYNC_FILE_RANGE_WRITE);
            printf("[FAULT] Writeback triggered at %lu MB\n", total_written / 1024 / 1024);
        }
        if (chunk_count % REPORT_EVERY == 0)
            printf("[FAULT] Written %lu MB\n", total_written / 1024 / 1024);
        usleep(10000);
    }
    printf("[FAULT] Write phase done: %lu MB\n", total_written / 1024 / 1024);
    struct timespec t1, t2;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("[FAULT] Syncing dirty pages...\n");
    fsync(fd);
    clock_gettime(CLOCK_MONOTONIC, &t2);
    double elapsed = (t2.tv_sec - t1.tv_sec) + (t2.tv_nsec - t1.tv_nsec) / 1e9;
    printf("[FAULT] fsync took %.2f seconds\n", elapsed);
    printf("[FAULT] Pausing 30s for diagnostics...\n");
    sleep(30);
    free(buf);
    close(fd);
    printf("[FAULT] Done\n");
    return 0;
}
