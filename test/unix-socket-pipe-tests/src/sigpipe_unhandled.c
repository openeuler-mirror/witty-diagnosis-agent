/*
 * sigpipe_unhandled.c — Fault F: SIGPIPE 信号未处理导致进程意外退出
 *
 * 故障注入演示：
 * 1. 创建 pipe
 * 2. fork: child 立即关闭读端
 * 3. parent 向已无读端的 pipe 写入数据
 * 4. 内核发送 SIGPIPE 给 parent
 * 5. parent 未注册 SIGPIPE handler → 默认行为：终止进程
 * 6. 进程意外退出，无 core dump、dmesg 无异常
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/sigpipe_unhandled sigpipe_unhandled.c
 * 运行: ./sigpipe_unhandled
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/wait.h>

int main() {
    int pipefd[2];

    printf("[main] 创建 pipe...\n");
    if (pipe(pipefd) < 0) { perror("pipe"); return 1; }
    printf("[main] pipe: read_fd=%d, write_fd=%d\n", pipefd[0], pipefd[1]);

    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }

    if (pid == 0) {
        /* ========== CHILD: close read end immediately ========== */
        close(pipefd[0]); /* 关闭读端 */
        close(pipefd[1]); /* 关闭写端（子进程不需要） */

        printf("[child ] PID=%d, 已关闭 pipe 读端!\n", getpid());
        printf("[child ] parent 写入时将被 SIGPIPE 杀死\n");
        sleep(1);
        printf("[child ] 退出\n");
        exit(0);

    } else {
        /* ========== PARENT: write to broken pipe ========== */
        close(pipefd[0]); /* 关闭读端（不需要） */

        /* 给 child 时间关闭读端 */
        usleep(200000);

        printf("[parent] PID=%d, 准备向 pipe 写入...\n", getpid());
        printf("[parent] ★ 未注册 SIGPIPE handler\n");
        printf("[parent] 写入已关闭的 pipe 将触发 SIGPIPE\n");

        char buf[] = "hello, world!";

        /*
         * 尝试写入。内核发现读端已关闭，发送 SIGPIPE 给当前进程。
         * 由于没有注册 handler，默认行为是终止进程 (Term)。
         * 下面这行代码可能永远不会执行完。
         */
        ssize_t n = write(pipefd[1], buf, sizeof(buf));

        /*
         * ★ 正常情况下，write() 永远不会返回
         * 进程在写入时被 SIGPIPE 杀死
         * 如果进程存活到了这里，说明 SIGPIPE 被屏蔽了
         */
        printf("[parent] ⚠️ write 返回了! (n=%zd)\n", n);
        if (n < 0) {
            printf("[parent] write 错误: %s\n", strerror(errno));
            if (errno == EPIPE) {
                printf("[parent] 收到 EPIPE — 但进程还活着?\n");
                printf("[parent] SIGPIPE 可能被屏蔽或忽略了\n");
            }
        }

        /*
         * 第二次写入 — 如果第一次 SIGPIPE 被忽略，
         * 第二次 write 才会返回 EPIPE
         */
        n = write(pipefd[1], buf, sizeof(buf));
        printf("[parent] 第二次 write 返回: n=%zd, errno=%d\n", n, n < 0 ? errno : 0);

        close(pipefd[1]);

        /*
         * 检查 SIGPIPE 处理状态
         */
        sigset_t pending;
        sigpending(&pending);
        if (sigismember(&pending, SIGPIPE)) {
            printf("[parent] ❌ SIGPIPE 已产生但被阻塞!\n");
        }

        printf("[parent] 结束 (存活!\n");

        wait(NULL);
    }

    return 0;
}
