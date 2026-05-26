/**
 * fault_shm_eacces.c -- inject SHM EACCES fault
 * Needs pre-existing SHM with key=0x12345679, perms=000
 * Non-root user attaching to it will get EACCES.
 */
#include <sys/shm.h>
#include <sys/ipc.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
int main() {
    key_t key = 0x12345679;
    int shmid = shmget(key, 4096, 0);
    if (shmid == -1) { perror("shmget"); return 1; }
    printf("[FAULT] shmget OK shmid=%d (uid=%d)\n", shmid, getuid());
    char *data = shmat(shmid, NULL, 0);
    if (data == (void*)-1) {
        printf("[FAULT] shmat FAILED errno=%d - EACCES confirmed!\n", errno);
        return 0;
    }
    printf("[FAULT] shmat OK (unexpected)\n");
    shmdt(data);
    return 0;
}
