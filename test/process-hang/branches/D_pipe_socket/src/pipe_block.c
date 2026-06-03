/*
 * pipe_block.c — 模拟 Branch D: 管道/Socket 阻塞读写
 *
 * 创建管道，写端持续写入直到管道缓冲区满（默认 64KB），
 * 由于没有读端消费数据，write() 调用阻塞在 pipe_write 状态。
 *
 * 可选: 使用 socket pair 产生类似的 socket 阻塞效果。
 *
 * 诊断特征:
 *   - wchan = pipe_write (写阻塞) 或 pipe_read (读阻塞)
 *   - fd 列表显示 pipe:[inode]
 *   - fd 列表显示 pipe:[inode]
 *
 * 模拟两种模式:
 *   mode=write: 写端阻塞（管道缓冲区满，无读者）
 *   mode=read:  读端阻塞（管道空，无写者）
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>

#define PIPE_BUF_SIZE 65536
#define MODE_WRITE "write"
#define MODE_READ "read"

volatile int running = 1;

void sigterm_handler(int sig) {
    (void)sig;
    running = 0;
}

void mode_write_block() {
    int pipefd[2];
    char *buf;
    size_t total = 0;

    if (pipe(pipefd) < 0) {
        fprintf(stderr, "pipe() 失败: %s\n", strerror(errno));
        exit(1);
    }

    /* 分配大数据块 */
    buf = malloc(PIPE_BUF_SIZE);
    if (!buf) {
        fprintf(stderr, "malloc 失败\n");
        exit(1);
    }
    memset(buf, 'X', PIPE_BUF_SIZE);

    printf("[Writer] 管道 fd: read=%d, write=%d\n", pipefd[0], pipefd[1]);
    printf("[Writer] 写端持续写入，直到缓冲区满...\n");
    fflush(stdout);

    /* 关闭读端，使管道缓冲区无法被消费 */
    close(pipefd[0]);

    while (running) {
        ssize_t n = write(pipefd[1], buf, PIPE_BUF_SIZE);
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                printf("[Writer] 管道满，write 返回 EAGAIN (O_NONBLOCK 模式)\n");
                break;
            }
            printf("[Writer] write 失败: %s (累计写入 %zu 字节后)\n",
                   strerror(errno), total);
            break;
        }
        total += n;
        printf("[Writer] 已写入 %zu 字节\n", total);
        fflush(stdout);
    }

    printf("[Writer] 最终写入: %zu 字节\n", total);
    printf("[Writer] 如需测试 pipe_write 阻塞，需去除 O_NONBLOCK\n");
    free(buf);
    close(pipefd[1]);
}

void mode_read_block() {
    int pipefd[2];
    char buf[64];
    pid_t child;

    if (pipe(pipefd) < 0) {
        fprintf(stderr, "pipe() 失败: %s\n", strerror(errno));
        exit(1);
    }

    printf("[Parent] 管道 fd: read=%d, write=%d\n", pipefd[0], pipefd[1]);
    fflush(stdout);

    child = fork();
    if (child == 0) {
        /* 子进程: 关闭写端，从空管道读取（阻塞） */
        close(pipefd[1]);
        printf("[Reader] PID=%d, 从空管道读取 (将阻塞)...\n", getpid());
        fflush(stdout);
        ssize_t n = read(pipefd[0], buf, sizeof(buf));
        printf("[Reader] read 返回 %zd (被信号中断或管道关闭)\n", n);
        close(pipefd[0]);
        exit(0);
    }

    /* 父进程: 关闭读端，不写入数据，让子进程的 read 阻塞 */
    close(pipefd[0]);
    printf("[Parent] 不写入数据，子进程 PID=%d 在空管道上阻塞读\n", child);
    printf("=== 故障已注入: pipe_read 阻塞 ===\n");
    fflush(stdout);

    while (running) {
        sleep(1);
    }

    /* 清理 */
    close(pipefd[1]);
    waitpid(child, NULL, WNOHANG);
}

int main(int argc, char *argv[]) {
    const char *mode = MODE_READ;

    signal(SIGTERM, sigterm_handler);

    if (argc > 1) {
        mode = argv[1];
    }

    printf("=== 管道/Socket 阻塞故障注入 ===\n");
    printf("PID: %d\n", getpid());
    printf("模式: %s\n", mode);
    printf("=== 故障已注入，等待诊断... ===\n");
    fflush(stdout);

    if (strcmp(mode, MODE_WRITE) == 0) {
        mode_write_block();
    } else {
        mode_read_block();
    }
    return 0;
}
