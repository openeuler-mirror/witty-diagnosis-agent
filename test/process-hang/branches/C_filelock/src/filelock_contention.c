/*
 * filelock_contention.c — 模拟 Branch C: 文件锁竞争
 *
 * 父进程持有文件的独占写锁（F_WRLCK），子进程尝试获取读锁（F_RDLCK），
 * 由于写锁与读锁互斥，子进程阻塞在锁等待中。
 *
 * 诊断特征:
 *   - /proc/locks 显示锁等待条目
 *   - 子进程 wchan 为 posix_lock_inode 或类似
 *   - lslocks 可看到锁竞争关系
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

#define LOCK_FILE "/tmp/test_lockfile.lock"

volatile int running = 1;

void sigterm_handler(int sig) {
    (void)sig;
    running = 0;
}

int main() {
    int fd;
    struct flock fl;
    pid_t child;

    signal(SIGTERM, sigterm_handler);

    /* 打开（或创建）锁文件 */
    fd = open(LOCK_FILE, O_RDWR | O_CREAT, 0644);
    if (fd < 0) {
        fprintf(stderr, "无法打开锁文件 %s: %s\n", LOCK_FILE, strerror(errno));
        return 1;
    }
    unlink(LOCK_FILE); /* 文件链接解除，但 fd 仍然有效 */

    printf("=== 文件锁竞争故障注入 ===\n");
    printf("PID: %d\n", getpid());
    printf("锁文件: %s\n", LOCK_FILE);

    /* 父进程获取独占写锁 */
    memset(&fl, 0, sizeof(fl));
    fl.l_type = F_WRLCK;
    fl.l_whence = SEEK_SET;
    fl.l_start = 0;
    fl.l_len = 0; /* 锁定整个文件 */

    if (fcntl(fd, F_SETLK, &fl) < 0) {
        fprintf(stderr, "父进程获取写锁失败: %s\n", strerror(errno));
        close(fd);
        return 1;
    }
    printf("[Parent] 持有独占写锁\n");

    /* 创建子进程 */
    child = fork();
    if (child < 0) {
        fprintf(stderr, "fork 失败: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    if (child == 0) {
        /* 子进程: 尝试获取读锁（与写锁互斥 → 阻塞） */
        struct flock rl;
        memset(&rl, 0, sizeof(rl));
        rl.l_type = F_RDLCK;
        rl.l_whence = SEEK_SET;
        rl.l_start = 0;
        rl.l_len = 0;

        printf("[Child] PID=%d, 尝试获取读锁 (将阻塞)...\n", getpid());
        fflush(stdout);

        /* 这里 F_SETLKW 会阻塞直到锁可用 */
        if (fcntl(fd, F_SETLKW, &rl) < 0) {
            /* 被信号中断也会返回 */
            if (errno != EINTR) {
                fprintf(stderr, "[Child] 获取读锁失败: %s\n", strerror(errno));
            }
        }
        printf("[Child] 获得读锁 (或已被中断)\n");
        close(fd);
        exit(0);
    }

    /* 父进程: 持有写锁不释放 */
    printf("[Parent] 持有写锁，子进程 PID=%d 在等待读锁\n", child);
    printf("=== 故障已注入，等待诊断... ===\n");
    fflush(stdout);

    /* 父进程保持运行，持有写锁 */
    while (running) {
        sleep(1);
    }

    /* 清理 */
    fl.l_type = F_UNLCK;
    fcntl(fd, F_SETLK, &fl);
    close(fd);

    /* 等待子进程结束 */
    waitpid(child, NULL, WNOHANG);
    return 0;
}
