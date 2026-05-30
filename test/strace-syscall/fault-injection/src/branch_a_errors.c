/**
 * branch_a_errors.c - Syscall Error Code Pattern Injection
 *
 * Modes: eacces | enoent | eagain | enomem | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 *
 * Triggers strace-observable syscall error patterns:
 *   EACCES/EPERM  - Permission denied operations
 *   ENOENT        - File/path not found
 *   EAGAIN        - Resource temporarily unavailable (non-blocking IO)
 *   ENOMEM        - Memory allocation failure
 *
 * Compile: gcc -O2 -o branch_a_errors branch_a_errors.c -lpthread
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/mman.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>

/* ============ EACCES / EPERM ============ */
static void fault_eacces(int cycles) {
    printf("[EACCES] cycles=%d\n", cycles);
    for (int i = 0; i < cycles; i++) {
        int fd = open("/etc/shadow", O_WRONLY);
        if (fd == -1)
            printf("  open(/etc/shadow,O_WRONLY) = -1 %s\n", strerror(errno));
        else close(fd);

        fd = open("/proc/self/mem", O_WRONLY);
        if (fd == -1)
            printf("  open(/proc/self/mem,O_WRONLY) = -1 %s\n", strerror(errno));
        else close(fd);

        struct sched_param sp = { .sched_priority = 99 };
        int ret = sched_setscheduler(0, SCHED_FIFO, &sp);
        if (ret == -1)
            printf("  sched_setscheduler(SCHED_FIFO,99) = -1 %s\n", strerror(errno));
        usleep(10000);
    }
}

/* ============ ENOENT ============ */
static void fault_enoent(int cycles) {
    printf("[ENOENT] cycles=%d\n", cycles);
    for (int i = 0; i < cycles; i++) {
        char path[256];
        snprintf(path, sizeof(path), "/tmp/nonexistent_dir_%d/nonexistent_file_%d.conf", getpid(), i);
        int fd = open(path, O_RDONLY);
        if (fd == -1)
            printf("  open(%s,O_RDONLY) = -1 %s\n", path, strerror(errno));
        else close(fd);

        struct stat st;
        int ret = stat("/tmp/definitely_not_a_file_that_exists.xzy", &st);
        if (ret == -1) printf("  stat(...) = -1 %s\n", strerror(errno));

        ret = access("/nonexistent_path/test_file.txt", F_OK);
        if (ret == -1) printf("  access(...) = -1 %s\n", strerror(errno));
        usleep(50000);
    }
}

/* ============ EAGAIN / EWOULDBLOCK ============ */
static void fault_eagain(int cycles) {
    printf("[EAGAIN] cycles=%d\n", cycles);
    int pipefd[2];
    if (pipe(pipefd) == -1) { perror("pipe"); return; }

    int flags = fcntl(pipefd[0], F_GETFL, 0);
    fcntl(pipefd[0], F_SETFL, flags | O_NONBLOCK);
    printf("  pipe(read=%d,write=%d) O_NONBLOCK\n", pipefd[0], pipefd[1]);

    for (int i = 0; i < cycles; i++) {
        char buf[64];
        ssize_t n = read(pipefd[0], buf, sizeof(buf));
        if (n == -1 && errno == EAGAIN)
            printf("  read(pipe,O_NONBLOCK) = -1 EAGAIN (cycle %d)\n", i);
        else if (n > 0)
            printf("  read(pipe,O_NONBLOCK) = %zd (data)\n", n);

        if (i % 5 == 0) {
            char msg[32];
            snprintf(msg, sizeof(msg), "data-%d\n", i);
            write(pipefd[1], msg, strlen(msg));
        }
        usleep(20000);
    }
    close(pipefd[0]); close(pipefd[1]);
}

/* ============ ENOMEM ============ */
static void fault_enomem(int cycles) {
    printf("[ENOMEM] cycles=%d\n", cycles);
    struct rlimit old_limit;
    getrlimit(RLIMIT_AS, &old_limit);
    printf("  RLIMIT_AS: soft=%lu hard=%lu\n",
           (unsigned long)old_limit.rlim_cur, (unsigned long)old_limit.rlim_max);

    struct rlimit new_limit;
    new_limit.rlim_cur = 32 * 1024 * 1024;
    new_limit.rlim_max = 64 * 1024 * 1024;
    if (setrlimit(RLIMIT_AS, &new_limit) == -1) { perror("setrlimit"); return; }
    printf("  RLIMIT_AS set to 32MB/64MB\n");

    for (int i = 0; i < cycles && i < 50; i++) {
        size_t alloc_size = (size_t)(i + 1) * 4 * 1024 * 1024;
        void *p = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) {
            printf("  mmap(%zu MB) = MAP_FAILED %s\n",
                   alloc_size / (1024*1024), strerror(errno));
            break;
        }
        printf("  mmap(%zu MB) = OK\n", alloc_size / (1024*1024));
        memset(p, 0xAA, alloc_size > 4096 ? 4096 : alloc_size);
    }
    setrlimit(RLIMIT_AS, &old_limit);
}

/* ============ ALL (finite) ============ */
static void run_all(int cycles) {
    int c = cycles > 4 ? cycles / 4 : 3;
    fault_eacces(c); printf("\n---\n");
    fault_enoent(c); printf("\n---\n");
    fault_eagain(c); printf("\n---\n");
    fault_enomem(c);
}

int main(int argc, char *argv[]) {
    const char *mode = "all";
    int cycles = 20;
    int loop_mode = 0;

    if (argc > 1 && strcmp(argv[1], "--loop") == 0) {
        loop_mode = 1;
        if (argc > 2) mode = argv[2];
    } else if (argc > 1) {
        mode = argv[1];
        if (argc > 2) cycles = atoi(argv[2]);
    }
    if (cycles < 1) cycles = 1;
    if (cycles > 100000) cycles = 100000;

    printf("=== Branch A === mode=%s loop=%d cycles=%d\n", mode, loop_mode, cycles);

    if (loop_mode) {
        signal(SIGTERM, SIG_DFL);
        while (1) {
            if (strcmp(mode, "eacces") == 0 || strcmp(mode, "eperm") == 0) fault_eacces(5);
            else if (strcmp(mode, "enoent") == 0) fault_enoent(5);
            else if (strcmp(mode, "eagain") == 0)  fault_eagain(5);
            else if (strcmp(mode, "enomem") == 0)  fault_enomem(5);
            else run_all(20);
            sleep(1);
        }
    }

    if (strcmp(mode, "eacces") == 0 || strcmp(mode, "eperm") == 0) fault_eacces(cycles);
    else if (strcmp(mode, "enoent") == 0) fault_enoent(cycles);
    else if (strcmp(mode, "eagain") == 0)  fault_eagain(cycles);
    else if (strcmp(mode, "enomem") == 0)  fault_enomem(cycles);
    else if (strcmp(mode, "all") == 0)     run_all(cycles);
    else {
        fprintf(stderr, "Usage: %s [--loop] <mode> [cycles]\n", argv[0]);
        fprintf(stderr, "Modes: eacces | enoent | eagain | enomem | all\n");
        return 1;
    }

    printf("=== Branch A completed ===\n");
    return 0;
}
