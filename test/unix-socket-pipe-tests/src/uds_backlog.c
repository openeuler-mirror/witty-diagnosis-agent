/*
 * uds_backlog.c — Fault A: UDS Listen Backlog 满
 *
 * 故障注入演示：UDS server 使用很小的 backlog 参数，大量 client 并发 connect，
 * 填满 listen 队列后导致 ECONNREFUSED/EAGAIN。
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/uds_backlog uds_backlog.c
 * 运行: ./uds_backlog [backlog=2] [clients=10]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <errno.h>

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    int backlog  = argc > 1 ? atoi(argv[1]) : 2;
    int nclients = argc > 2 ? atoi(argv[2]) : 10;

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    /* ---- server ---- */
    int srv_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv_fd < 0) { perror("socket"); return 1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/uds_backlog.sock", sizeof(addr.sun_path) - 1);
    unlink(addr.sun_path);

    if (bind(srv_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind"); return 1;
    }

    if (listen(srv_fd, backlog) < 0) {
        perror("listen"); return 1;
    }

    printf("[server] listening on %s, backlog=%d\n", addr.sun_path, backlog);
    printf("[server] PID=%d\n", getpid());

    /* ---- clients: fill backlog without accept ---- */
    int *client_fds = calloc(nclients, sizeof(int));
    int connected = 0, refused = 0;

    for (int i = 0; i < nclients; i++) {
        int cfd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (cfd < 0) { perror("client socket"); continue; }

        if (connect(cfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
            client_fds[connected++] = cfd;
            printf("[client %2d] connected OK  (fd=%d)\n", i, cfd);
        } else {
            printf("[client %2d] connect FAIL: %s\n", i, strerror(errno));
            close(cfd);
            refused++;
        }
        usleep(5000); /* 5ms间隔，避免太快 */
    }

    printf("\n=== 结果 ===\n");
    printf("  连接成功: %d\n", connected);
    printf("  连接拒绝: %d\n", refused);
    printf("  Backlog:  %d\n", backlog);
    printf("  Server PID: %d  (kill 此 PID 释放所有连接)\n", getpid());

    /* 保持运行，便于诊断 */
    while (running) pause();

    /* cleanup */
    close(srv_fd);
    for (int i = 0; i < connected; i++) close(client_fds[i]);
    free(client_fds);
    unlink(addr.sun_path);
    return 0;
}
