/*
 * passcred_fail.c — Fault C: SO_PASSCRED/SCM_RIGHTS 凭证传递失败
 *
 * 故障注入演示：
 * - Parent 通过 socketpair() 发送 SCM_CREDENTIALS（进程凭证）
 * - Child recvmsg() 时未设置 SO_PASSCRED，导致收不到辅助数据
 * - 最终凭证丢失，无法验证对端身份
 *
 * 编译: gcc -o ~/unix-pipe-test-lab/bin/passcred_fail passcred_fail.c
 * 运行: ./passcred_fail
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <errno.h>

#include <sys/wait.h>

#define BUF_SIZE 64

int main() {
    int sv[2]; /* socketpair fds */

    /* 创建 UNIX socketpair */
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) < 0) {
        perror("socketpair"); return 1;
    }

    printf("[parent] socketpair created: fd=%d, fd=%d\n", sv[0], sv[1]);

    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }

    if (pid == 0) {
        /* ========== child: receiver ========== */
        close(sv[1]); /* 关闭发送端 */

        printf("[child  ] PID=%d, recvmsg() 准备接收...\n", getpid());
        printf("[child  ] ★ 注意: 未设置 SO_PASSCRED!\n");

        char buf[BUF_SIZE];
        struct iovec iov = { .iov_base = buf, .iov_len = BUF_SIZE };

        /* 准备辅助数据接收缓冲区 */
        union {
            struct cmsghdr cm;
            char control[CMSG_SPACE(sizeof(struct ucred))];
        } control_un;
        struct msghdr msg = { .msg_iov = &iov, .msg_iovlen = 1 };
        msg.msg_control = control_un.control;
        msg.msg_controllen = sizeof(control_un.control);

        ssize_t n = recvmsg(sv[0], &msg, 0);
        if (n < 0) {
            perror("[child  ] recvmsg FAILED");
        } else {
            printf("[child  ] 收到 %zd 字节数据: %s\n", n, buf);

            /* 解析辅助数据 */
            struct cmsghdr *cmsg;
            int found_cred = 0;
            for (cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL;
                 cmsg = CMSG_NXTHDR(&msg, cmsg)) {
                if (cmsg->cmsg_level == SOL_SOCKET &&
                    cmsg->cmsg_type == SCM_CREDENTIALS) {
                    struct ucred *cred = (struct ucred*)CMSG_DATA(cmsg);
                    printf("[child  ] ✅ SCM_CREDENTIALS received!\n");
                    printf("[child  ]   pid=%d, uid=%d, gid=%d\n",
                           cred->pid, cred->uid, cred->gid);
                    found_cred = 1;
                }
            }
            if (!found_cred) {
                printf("[child  ] ❌ 没有收到 SCM_CREDENTIALS!\n");
                printf("[child  ] 原因: SO_PASSCRED 未设置, 内核丢弃了辅助数据\n");
            }
        }

        close(sv[0]);
        printf("[child  ] 结束\n");
        exit(0);

    } else {
        /* ========== parent: sender ========== */
        close(sv[0]); /* 关闭接收端 */

        sleep(1); /* 等 child 就绪 */

        printf("[parent] PID=%d, 准备发送 SCM_CREDENTIALS...\n", getpid());

        char *data = "hello from parent";
        struct iovec iov = { .iov_base = data, .iov_len = strlen(data) + 1 };

        /* 构造辅助数据: SCM_CREDENTIALS */
        union {
            struct cmsghdr cm;
            char control[CMSG_SPACE(sizeof(struct ucred))];
        } control_un;
        memset(&control_un, 0, sizeof(control_un));

        struct msghdr msg = { .msg_iov = &iov, .msg_iovlen = 1 };
        msg.msg_control = control_un.control;
        msg.msg_controllen = sizeof(control_un.control);

        struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
        cmsg->cmsg_len   = CMSG_LEN(sizeof(struct ucred));
        cmsg->cmsg_level = SOL_SOCKET;
        cmsg->cmsg_type  = SCM_CREDENTIALS;

        struct ucred *cred = (struct ucred*)CMSG_DATA(cmsg);
        cred->pid = getpid();
        cred->uid = getuid();
        cred->gid = getgid();

        ssize_t n = sendmsg(sv[1], &msg, 0);
        if (n < 0) {
            perror("[parent] sendmsg FAILED");
        } else {
            printf("[parent] 发送 %zd 字节 + SCM_CREDENTIALS OK\n", n);
        }

        close(sv[1]);
        printf("[parent] 等待 child 结束...\n");
        wait(NULL);
        printf("[parent] 结束\n");
    }

    return 0;
}
