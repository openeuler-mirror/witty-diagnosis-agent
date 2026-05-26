/*
 * socketpair_leak.c — Fault G: socketpair 泄漏
 *
 * 故障注入演示：循环创建 socketpair() 但不 close()，
 * 导致 anon_inode 类型的 FD 持续增长。
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/socketpair_leak socketpair_leak.c
 * 运行: ./socketpair_leak [pairs_per_round=5] [rounds=20]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <signal.h>
#include <errno.h>

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    int pairs_per_round = argc > 1 ? atoi(argv[1]) : 5;  /* 每轮创建数 */
    int rounds          = argc > 2 ? atoi(argv[2]) : 20;  /* 轮数 */

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    printf("[leak] PID=%d\n", getpid());
    printf("[leak] 参数: pairs_per_round=%d, rounds=%d\n", pairs_per_round, rounds);
    printf("[leak] 每轮泄漏 %d 个 FD，共 %d 轮 = %d 个 socketpair FD\n",
           pairs_per_round * 2, rounds, pairs_per_round * rounds * 2);
    printf("[leak] 相当于 %d 个 anon_unix FD\n",
           pairs_per_round * rounds * 2);

    /* 存储所有泄漏的 FD，防止被优化 */
    int total_fds = pairs_per_round * rounds * 2;
    int *all_fds = malloc(total_fds * sizeof(int));
    int idx = 0;

    for (int r = 0; r < rounds; r++) {
        if (!running) break;

        for (int p = 0; p < pairs_per_round; p++) {
            int sv[2];
            if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
                printf("[leak] 第 %d 轮, 第 %d 个 socketpair 失败: %s\n",
                       r, p, strerror(errno));
                continue;
            }
            all_fds[idx++] = sv[0];
            all_fds[idx++] = sv[1];
            /* ★ 故意不 close() — FD 泄漏 */
        }

        printf("[leak] 第 %2d 轮: 已泄漏 %4d 个 socketpair FD\n",
               r + 1, pairs_per_round * (r + 1) * 2);

        /* 短暂延时，让诊断可以观察到趋势 */
        usleep(100000); /* 100ms */
    }

    printf("\n=== 泄漏统计 ===\n");
    printf("  预期泄漏: %d 个 socketpair FD\n", total_fds);
    printf("  实际泄漏: %d 个 socketpair FD\n", idx);
    printf("  PID: %d\n", getpid());

    /* 显示当前 FD 列表中的 socketpair 类型 */
    char fdpath[32];
    for (int i = 0; i < 3 && i < idx; i++) {
        char link[256] = {0};
        snprintf(fdpath, sizeof(fdpath), "/proc/self/fd/%d", all_fds[i]);
        ssize_t len = readlink(fdpath, link, sizeof(link) - 1);
        if (len > 0) {
            printf("  fd/%d -> %s\n", all_fds[i], link);
        }
    }
    if (idx > 3) printf("  ... 还有 %d 个 FD (省略)\n", idx - 3);

    printf("\n  诊断: lsof -p %d | grep anon_unix\n", getpid());
    printf("  诊断: ls -la /proc/%d/fd | wc -l\n", getpid());

    printf("\n[leak] 保持运行中 (Ctrl+C 退出, 释放所有 FD)\n");

    /* 保持运行，方便诊断 */
    while (running) pause();

    /* 清理（Exit 时会自动关闭，但显式 close 更干净） */
    for (int i = 0; i < idx; i++) close(all_fds[i]);
    free(all_fds);
    printf("[leak] 退出, 所有 FD 已释放\n");
    return 0;
}
