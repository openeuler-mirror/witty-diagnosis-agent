/*
 * pipe_buf_full.c — Fault E: 管道缓冲区满导致写阻塞 (D 状态)
 *
 * 故障注入演示：
 * - 创建 pipe，设置较小 buffer（通过 F_SETPIPE_SZ）
 * - fork 双进程：parent 为 slow reader，child 为 fast writer
 * - child 写入速度远超 parent 读取，pipe buffer 填满
 * - writer 的 write() 调用阻塞 → 进程进入 D（不可中断睡眠）状态
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/pipe_buf_full pipe_buf_full.c
 * 运行: ./pipe_buf_full [buffer_size_kb=64] [write_speed_kbps=10240]
 *       默认 64KB buffer, writer 以 10MB/s 写入
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <sys/wait.h>

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    long buf_size_kb = argc > 1 ? atol(argv[1]) : 64;
    long write_kbps  = argc > 2 ? atol(argv[2]) : 10240;

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    int pipefd[2];
    if (pipe(pipefd) < 0) { perror("pipe"); return 1; }

    printf("[main] pipe created: read_fd=%d, write_fd=%d\n", pipefd[0], pipefd[1]);

    /* 设置 pipe buffer 大小 */
    long buf_size_bytes = buf_size_kb * 1024;
    long actual = fcntl(pipefd[1], F_SETPIPE_SZ, (int)buf_size_bytes);
    if (actual < 0) {
        perror("F_SETPIPE_SZ");
        printf("[main] 使用默认 pipe buffer 大小\n");
    } else {
        buf_size_bytes = actual;
        buf_size_kb = actual / 1024;
        printf("[main] pipe buffer size set to %ld bytes (%ld KB)\n",
               actual, actual / 1024);
    }

    /* 检查系统上限 */
    FILE *fp = fopen("/proc/sys/fs/pipe-max-size", "r");
    if (fp) {
        long max;
        if (fscanf(fp, "%ld", &max) == 1) {
            printf("[main] /proc/sys/fs/pipe-max-size = %ld\n", max);
            if (buf_size_bytes > max) {
                printf("[main] ⚠️ 请求大小超过系统上限，已被内核限制为 %ld\n", max);
            }
        }
        fclose(fp);
    }

    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }

    if (pid == 0) {
        /* ========== CHILD: Fast Writer ========== */
        close(pipefd[0]);  /* 关闭读端 */

        printf("[writer] PID=%d, 开始向 pipe 快速写入...\n", getpid());
        printf("[writer] buffer=%ld KB, 目标速率=%ld KB/s\n", buf_size_kb, write_kbps);

        /* 每个 write 块大小 4KB */
        char buf[4096];
        memset(buf, 'W', sizeof(buf));
        long total_written = 0;

        while (running) {
            ssize_t n = write(pipefd[1], buf, sizeof(buf));
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                printf("[writer] write FAILED: %s\n", strerror(errno));
                break;
            }
            total_written += n;

            /* 写入一定量后暂停以控制总速率 */
            if (total_written % (write_kbps * 2) == 0) {
                usleep(1000); /* 1ms 微暂停 */
            }
        }

        printf("[writer] 共写入 %ld bytes，结束\n", total_written);
        close(pipefd[1]);
        exit(0);

    } else {
        /* ========== PARENT: Slow Reader ========== */
        close(pipefd[1]); /* 关闭写端 */

        printf("[reader] PID=%d, 开始慢速读取 pipe (模拟阻塞场景)...\n", getpid());

        char buf[64]; /* 每次只读 64 字节 */
        long total_read = 0;
        int timeout = 0;

        while (running && timeout < 300) {
            ssize_t n = read(pipefd[0], buf, sizeof(buf));
            if (n < 0) {
                if (errno == EAGAIN) break;
                printf("[reader] read FAILED: %s\n", strerror(errno));
                break;
            }
            if (n == 0) break; /* EOF */

            total_read += n;

            /* ★ 故意缓慢读取：每次读取后等待 100ms */
            usleep(100000); /* 100ms */

            if (total_read % 65536 == 0) {
                printf("[reader] 已读取 %ld bytes (管道中可能已满)\n", total_read);
            }
            timeout++;
        }

        printf("[reader] 共读取 %ld bytes\n", total_read);

        /* 检查 writer 进程是否阻塞在写端 */
        int wstatus;
        if (waitpid(pid, &wstatus, WNOHANG) == 0) {
            printf("\n⚠️  writer 进程(PID=%d)可能仍阻塞在 write()\n", pid);
            printf("   检查 D 状态进程: ps -eo pid,stat,wchan:32,comm | grep %d\n", pid);
        } else {
            printf("\n[reader] writer 已结束\n");
        }

        close(pipefd[0]);
        wait(NULL);
        printf("[reader] 结束\n");
    }

    return 0;
}
