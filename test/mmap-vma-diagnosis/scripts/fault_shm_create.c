/**
 * fault_shm_create.c — 注入共享内存权限拒绝故障
 *
 * 流程:
 * 1. 创建一个共享内存段（IPC_CREAT|0660）
 * 2. 降低权限后重试 shmget，触发 EACCES
 * 3. 模拟容器内 /dev/shm 大小不足场景
 */
#include <sys/shm.h>
#include <sys/ipc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

int main() {
    key_t key = 0x12345678;  // 固定 key 便于诊断
    int shmid;
    char *data;

    printf("[FAULT] PID=%d\n", getpid());
    printf("[FAULT] === 场景1: 创建共享内存段(0666) ===\n");

    shmid = shmget(key, 4096, IPC_CREAT | IPC_EXCL | 0666);
    if (shmid == -1) {
        if (errno == EEXIST) {
            printf("[FAULT] 共享内存已存在，尝试删除后重建\n");
            shmctl(shmid, IPC_RMID, NULL);
            shmid = shmget(key, 4096, IPC_CREAT | IPC_EXCL | 0666);
        }
        if (shmid == -1) {
            perror("shmget failed");
            return 1;
        }
    }
    printf("[FAULT] shmget OK: shmid=%d\n", shmid);

    // 写入数据
    data = shmat(shmid, NULL, 0);
    if (data == (void *)-1) {
        perror("shmat failed");
        goto cleanup;
    }
    strcpy(data, "FAULT_INJECTION_TEST_DATA");
    printf("[FAULT] shmat OK: data=%s\n", data);
    shmdt(data);

    printf("[FAULT] === 场景2: 模拟权限拒绝 (只读attach) ===\n");
    data = shmat(shmid, NULL, SHM_RDONLY);
    if (data == (void *)-1) {
        perror("shmat SHM_RDONLY failed");
    } else {
        printf("[FAULT] shmat(SHM_RDONLY) OK: data=%s\n", data);
        shmdt(data);
    }

    printf("[FAULT] 共享内存段保留，等待诊断脚本检查...\n");
    printf("[FAULT] 可用命令: ipcs -m -i %d\n", shmid);
    printf("[FAULT] 清理: ipcrm -m %d\n", shmid);

    // 保持 30 秒供诊断
    sleep(30);

cleanup:
    shmctl(shmid, IPC_RMID, NULL);
    printf("[FAULT] 共享内存段已清理\n");
    return 0;
}
