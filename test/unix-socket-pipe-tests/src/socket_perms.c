/*
 * socket_perms.c — Fault D: Socket 文件权限错误
 *
 * 故障注入演示：
 * - 进程创建 UDS socket，bind 到文件路径
 * - 使用 chmod() 设置 socket 文件权限为 000（或通过参数指定）
 * - 另一个进程尝试 connect() 时因权限不足返回 EACCES
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/socket_perms socket_perms.c
 * 运行: ./socket_perms [perm=0000]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <signal.h>
#include <errno.h>

#include <sys/wait.h>
#define SOCK_PATH "/tmp/test_uds_perms"

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    mode_t perm = argc > 1 ? strtol(argv[1], NULL, 8) : 0000;

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    /* ---- server: create + bind + chmod ---- */
    int srv_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv_fd < 0) { perror("socket"); return 1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);
    unlink(addr.sun_path);

    if (bind(srv_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind"); return 1;
    }

    /* ★ 设置极限制权限 */
    chmod(addr.sun_path, perm);

    if (listen(srv_fd, 5) < 0) {
        perror("listen"); return 1;
    }

    printf("[server] PID=%d\n", getpid());
    printf("[server] socket=%s\n", addr.sun_path);
    printf("[server] 权限=%04o (octal)\n", perm);

    /* 显示权限信息 */
    struct stat st;
    if (stat(addr.sun_path, &st) == 0) {
        char perm_str[11];
        snprintf(perm_str, sizeof(perm_str), "%c%c%c%c%c%c%c%c%c%c",
                 S_ISSOCK(st.st_mode) ? 's' : '-',
                 (st.st_mode & S_IRUSR) ? 'r' : '-',
                 (st.st_mode & S_IWUSR) ? 'w' : '-',
                 (st.st_mode & S_IXUSR) ? 'x' : '-',
                 (st.st_mode & S_IRGRP) ? 'r' : '-',
                 (st.st_mode & S_IWGRP) ? 'w' : '-',
                 (st.st_mode & S_IXGRP) ? 'x' : '-',
                 (st.st_mode & S_IROTH) ? 'r' : '-',
                 (st.st_mode & S_IWOTH) ? 'w' : '-',
                 (st.st_mode & S_IXOTH) ? 'x' : '-');
        printf("[server] ls -la: %s %s\n", perm_str, addr.sun_path);
    }

    /* ---- fork: child tries to connect ---- */
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }

    if (pid == 0) {
        /* child: client connect test */
        sleep(1);

        printf("\n[client] 尝试 connect() 到 %s ...\n", addr.sun_path);
        int cfd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (cfd < 0) { perror("client socket"); exit(1); }

        if (connect(cfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
            printf("[client] ✅ connect OK\n");
            close(cfd);
        } else {
            printf("[client] ❌ connect FAILED: %s\n", strerror(errno));
            if (errno == EACCES) {
                printf("[client] 原因: Socket 文件权限拒绝 (EACCES)!\n");
                printf("[client] 权限 %04o 不允许客户端连接\n", perm);
            }
            close(cfd);
        }
        exit(0);
    }

    /* parent: keep running, accept connection if possible */
    printf("\n[server] 等待连接 (Ctrl+C 退出)...\n");

    struct sockaddr_un client_addr;
    socklen_t client_len = sizeof(client_addr);

    /* 设置非阻塞 accept 以便在超时后继续检查 */
    struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
    setsockopt(srv_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    while (running) {
        int cfd = accept(srv_fd, (struct sockaddr*)&client_addr, &client_len);
        if (cfd >= 0) {
            printf("[server] ✅ 接受连接 (fd=%d)\n", cfd);
            close(cfd);
        } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
            /* 超时正常，忽略 */
        }
    }

    wait(NULL);
    close(srv_fd);
    unlink(addr.sun_path);
    printf("[server] 退出\n");
    return 0;
}
