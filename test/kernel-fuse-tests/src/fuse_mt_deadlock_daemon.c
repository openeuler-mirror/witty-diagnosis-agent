/**
 * fuse_mt_deadlock_daemon.c — FUSE daemon with intentional lock inversion
 *
 * Injects Branch E fault (Multi-threaded Deadlock).
 * Two mutexes (lock_a, lock_b) are acquired in opposite order by
 * different threads, creating a classic ABBA deadlock.
 *
 * Build: gcc -o fuse_mt_deadlock_daemon fuse_mt_deadlock_daemon.c \
 *            `pkg-config --cflags --libs fuse3` -lpthread
 * Usage: ./fuse_mt_deadlock_daemon -f <mount_point>
 * Trigger: echo "deadlock" > <mount_point>/ctl_deadlock
 */

#define FUSE_USE_VERSION 31

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>

static pthread_mutex_t lock_a = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t lock_b = PTHREAD_MUTEX_INITIALIZER;
static int deadlock_triggered = 0;
static int threads_ready = 0;
static pthread_mutex_t sync_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t sync_cond = PTHREAD_COND_INITIALIZER;

/* Thread 1: lock_a → lock_b */
static void *thread1_func(void *arg) {
    (void)arg;

    /* Signal ready */
    pthread_mutex_lock(&sync_mutex);
    threads_ready++;
    pthread_cond_signal(&sync_cond);
    pthread_mutex_unlock(&sync_mutex);

    /* Wait for trigger */
    while (!deadlock_triggered) usleep(1000);

    fprintf(stderr, "[Thread 1] Attempting lock_a...\n");
    pthread_mutex_lock(&lock_a);
    fprintf(stderr, "[Thread 1] Got lock_a, attempting lock_b...\n");
    sleep(1); /* Window for thread 2 to grab lock_b */
    pthread_mutex_lock(&lock_b);
    fprintf(stderr, "[Thread 1] Got lock_b (should not happen in deadlock)\n");
    pthread_mutex_unlock(&lock_b);
    pthread_mutex_unlock(&lock_a);

    return NULL;
}

/* Thread 2: lock_b → lock_a */
static void *thread2_func(void *arg) {
    (void)arg;

    /* Signal ready */
    pthread_mutex_lock(&sync_mutex);
    threads_ready++;
    pthread_cond_signal(&sync_cond);
    pthread_mutex_unlock(&sync_mutex);

    /* Wait for trigger */
    while (!deadlock_triggered) usleep(1000);

    fprintf(stderr, "[Thread 2] Attempting lock_b...\n");
    pthread_mutex_lock(&lock_b);
    fprintf(stderr, "[Thread 2] Got lock_b, attempting lock_a...\n");
    sleep(1); /* Ensure window */
    pthread_mutex_lock(&lock_a);
    fprintf(stderr, "[Thread 2] Got lock_a (should not happen in deadlock)\n");
    pthread_mutex_unlock(&lock_a);
    pthread_mutex_unlock(&lock_b);

    return NULL;
}

/* getattr also participates in the deadlock via lock_a ordering */
static int fuse_getattr(const char *path, struct stat *stbuf) {
    memset(stbuf, 0, sizeof(struct stat));

    /* If deadlock triggered, try lock_a → lock_b */
    if (deadlock_triggered) {
        pthread_mutex_lock(&lock_a);
        usleep(50000); /* Window for interleaving */
        pthread_mutex_lock(&lock_b);
        /* Will deadlock here if thread1/thread2 hold opposite locks */
        pthread_mutex_unlock(&lock_b);
        pthread_mutex_unlock(&lock_a);
    }

    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }
    if (strcmp(path, "/ctl_deadlock") == 0) {
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        return 0;
    }
    return -ENOENT;
}

static int fuse_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    (void)offset;
    (void)fi;
    if (strcmp(path, "/") != 0) return -ENOENT;
    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);
    filler(buf, "ctl_deadlock", NULL, 0);
    return 0;
}

static int fuse_open(const char *path, struct fuse_file_info *fi) {
    return strcmp(path, "/ctl_deadlock") == 0 ? 0 : -ENOENT;
}

static int fuse_write(const char *path, const char *buf, size_t size,
                      off_t offset, struct fuse_file_info *fi) {
    if (strcmp(path, "/ctl_deadlock") != 0)
        return -ENOENT;

    char cmd[64];
    size_t len = size < (sizeof(cmd) - 1) ? size : (sizeof(cmd) - 1);
    memcpy(cmd, buf, len);
    cmd[len] = '\0';
    if (len > 0 && cmd[len-1] == '\n') cmd[len-1] = '\0';

    if (strcmp(cmd, "deadlock") == 0) {
        fprintf(stderr, "[Daemon] DEADLOCK triggered!\n");
        deadlock_triggered = 1;
    }
    return size;
}

static int fuse_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    if (strcmp(path, "/ctl_deadlock") != 0)
        return -ENOENT;
    (void)fi;
    char status[128];
    int n = snprintf(status, sizeof(status),
                     "deadlock=%s threads_ready=%d\n",
                     deadlock_triggered ? "triggered" : "idle",
                     threads_ready);
    if (offset >= n) return 0;
    size_t to_copy = size < (size_t)(n - offset) ? size : (size_t)(n - offset);
    memcpy(buf, status + offset, to_copy);
    return to_copy;
}

static int fuse_release(const char *path, struct fuse_file_info *fi) {
    (void)path;
    (void)fi;
    return 0;
}

static struct fuse_operations fuse_ops = {
    .getattr    = fuse_getattr,
    .readdir    = fuse_readdir,
    .open       = fuse_open,
    .read       = fuse_read,
    .write      = fuse_write,
    .release    = fuse_release,
};

int main(int argc, char *argv[]) {
    /* Start deadlock threads (they wait for trigger) */
    pthread_t t1, t2;
    pthread_create(&t1, NULL, thread1_func, NULL);
    pthread_create(&t2, NULL, thread2_func, NULL);
    pthread_detach(t1);
    pthread_detach(t2);

    /* Wait for threads to be ready */
    pthread_mutex_lock(&sync_mutex);
    while (threads_ready < 2)
        pthread_cond_wait(&sync_cond, &sync_mutex);
    pthread_mutex_unlock(&sync_mutex);

    fprintf(stderr, "[Daemon] Both deadlock threads ready. Starting FUSE loop...\n");

    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    int ret = fuse_main(args.argc, args.argv, &fuse_ops, NULL);
    fuse_opt_free_args(&args);
    return ret;
}
