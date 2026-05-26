/*
 * abstract_conflict.c — Fault B: Abstract Socket Namespace 冲突
 *
 * 故障注入演示：两个进程绑定同一个 abstract UDS 地址 @<name>，
 * 第二个进程 bind() 失败返回 EADDRINUSE。
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/abstract_conflict abstract_conflict.c
 * 运行: ./abstract_conflict [@addr_name]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <errno.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <errno.h>
#include <sys/stat.h>

volatile int running = 1;
void handle_signal(int sig) { running = 0; }

int main(int argc, char *argv[]) {
    const char *addr_name = argc > 1 ? argv[1] : "@uds_test";

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    /* 创建 socket */
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return 1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    /*
     * Abstract UDS 地址：sun_path[0] = '\0'，后面跟名字
     * 这样不会创建文件系统中的 socket 文件
     */
    size_t name_len = strlen(addr_name);
    if (name_len > (sizeof(addr.sun_path) - 1)) {
        fprintf(stderr, "地址太长: %s\n", addr_name);
        close(fd);
        return 1;
    }

    /* 构造 abstract 地址：首字节 '\0' + 去掉前导 @ 的剩余字符串 */
    int skip = (addr_name[0] == '@') ? 1 : 0;
    addr.sun_path[0] = '\0';
    memcpy(addr.sun_path + 1, addr_name + skip, name_len - skip);

    /* 整个 sockaddr_un 长度 = offsetof + 1 + name_len - skip */
    socklen_t addr_len = offsetof(struct sockaddr_un, sun_path) + 1 + (name_len - skip);

    /* 尝试 bind —— 如果已经绑定则会失败 */
    if (bind(fd, (struct sockaddr*)&addr, addr_len) < 0) {
        printf("[PID %d] ❌ bind(%s) FAILED: %s\n",
               getpid(), addr_name, strerror(errno));
        printf("[PID %d] 原因: 地址已被占用 (EADDRINUSE)\n", getpid());
        printf("[PID %d] 这是 Abstract Socket 命名空间冲突!\n", getpid());
        close(fd);
        return 1;
    }

    /* bind 成功 */
    printf("[PID %d] ✅ bind(%s) OK\n", getpid(), addr_name);
    printf("[PID %d] 持有 abstract UDS 地址\n", getpid());

    if (listen(fd, 5) < 0) {
        perror("listen");
        close(fd);
        return 1;
    }
    printf("[PID %d] 监听中... (Ctrl+C 退出, 释放地址)\n", getpid());

    /* 保持运行，持有该地址 */
    while (running) pause();

    close(fd);
    printf("[PID %d] 已释放地址 %s\n", getpid(), addr_name);
    return 0;
}
