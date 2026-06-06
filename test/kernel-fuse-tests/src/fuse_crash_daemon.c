/**
 * fuse_crash_daemon.c — FUSE daemon that crashes on command
 *
 * Injects Branch A fault (Daemon Crash → EIO).
 * Writes to a special control file causes the daemon to:
 *   - SIGSEGV (crash)
 *   - abort()  (SIGABRT)
 *   - exit(1)  (graceful exit)
 *   - fuse_exit() (clean shutdown)
 *
 * Build: gcc -o fuse_crash_daemon fuse_crash_daemon.c `pkg-config --cflags --libs fuse3`
 * Usage: ./fuse_crash_daemon -f <mount_point>
 * Trigger: echo "crash" > <mount_point>/ctl_crash
 *          echo "abort" > <mount_point>/ctl_crash
 *          echo "exit"  > <mount_point>/ctl_crash
 */

#define FUSE_USE_VERSION 31

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>

/* Thread synchronization for delayed crash */
static pthread_mutex_t crash_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t crash_cond = PTHREAD_COND_INITIALIZER;
static int crash_pending = 0;
static int crash_type = 0; /* 1=SIGSEGV, 2=abort, 3=exit, 4=fuse_exit */

/* Control file content buffer */
static char ctl_response[256] = "ok\n";
static int response_pending = 0;

static int fuse_getattr(const char *path, struct stat *stbuf) {
    memset(stbuf, 0, sizeof(struct stat));
    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }
    if (strcmp(path, "/ctl_crash") == 0) {
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        stbuf->st_size = 0;
        stbuf->st_uid = getuid();
        stbuf->st_gid = getgid();
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
    filler(buf, "ctl_crash", NULL, 0);
    return 0;
}

static int fuse_open(const char *path, struct fuse_file_info *fi) {
    if (strcmp(path, "/ctl_crash") == 0) {
        if ((fi->flags & 3) == O_RDONLY) return 0;
        if ((fi->flags & 3) == O_WRONLY) return 0;
        if ((fi->flags & 3) == O_RDWR) return 0;
    }
    return -ENOENT;
}

/* Thread that executes the crash after write completes */
static void *crash_thread_func(void *arg) {
    (void)arg;
    pthread_mutex_lock(&crash_mutex);
    while (!crash_pending)
        pthread_cond_wait(&crash_cond, &crash_mutex);
    crash_pending = 0;
    int type = crash_type;
    pthread_mutex_unlock(&crash_mutex);

    /* Small delay to let the FUSE write reply go through */
    usleep(50000);

    switch (type) {
    case 1: /* SIGSEGV */
        {
            int *p = NULL;
            *p = 42;
        }
        break;
    case 2: /* abort */
        abort();
        break;
    case 3: /* exit */
        exit(1);
        break;
    case 4: /* fuse_exit */
        fuse_exit(fuse_get_context()->fuse);
        break;
    default:
        break;
    }
    return NULL;
}

static int fuse_write(const char *path, const char *buf, size_t size,
                      off_t offset, struct fuse_file_info *fi) {
    if (strcmp(path, "/ctl_crash") != 0)
        return -ENOENT;

    char cmd[64];
    size_t len = size < (sizeof(cmd) - 1) ? size : (sizeof(cmd) - 1);
    memcpy(cmd, buf, len);
    cmd[len] = '\0';

    /* Strip newline */
    if (len > 0 && cmd[len-1] == '\n') cmd[len-1] = '\0';

    if (strcmp(cmd, "crash") == 0) {
        pthread_mutex_lock(&crash_mutex);
        crash_type = 1;
        crash_pending = 1;
        pthread_cond_signal(&crash_cond);
        pthread_mutex_unlock(&crash_mutex);
        return size;
    } else if (strcmp(cmd, "abort") == 0) {
        pthread_mutex_lock(&crash_mutex);
        crash_type = 2;
        crash_pending = 1;
        pthread_cond_signal(&crash_cond);
        pthread_mutex_unlock(&crash_mutex);
        return size;
    } else if (strcmp(cmd, "exit") == 0) {
        pthread_mutex_lock(&crash_mutex);
        crash_type = 3;
        crash_pending = 1;
        pthread_cond_signal(&crash_cond);
        pthread_mutex_unlock(&crash_mutex);
        return size;
    } else if (strcmp(cmd, "fuse_exit") == 0) {
        pthread_mutex_lock(&crash_mutex);
        crash_type = 4;
        crash_pending = 1;
        pthread_cond_signal(&crash_cond);
        pthread_mutex_unlock(&crash_mutex);
        return size;
    }

    /* Unknown command */
    return -EINVAL;
}

static int fuse_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    if (strcmp(path, "/ctl_crash") != 0)
        return -ENOENT;
    (void)fi;
    size_t len = strlen(ctl_response);
    if (offset >= (off_t)len)
        return 0;
    size_t to_copy = size < (len - offset) ? size : (len - offset);
    memcpy(buf, ctl_response + offset, to_copy);
    return to_copy;
}

static int fuse_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    if (strcmp(path, "/ctl_crash") == 0)
        return 0;
    return -ENOSPC;
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
    .create     = fuse_create,
    .release    = fuse_release,
};

int main(int argc, char *argv[]) {
    /* Start crash handler thread */
    pthread_t crash_thread;
    pthread_create(&crash_thread, NULL, crash_thread_func, NULL);
    pthread_detach(crash_thread);

    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    int ret = fuse_main(args.argc, args.argv, &fuse_ops, NULL);
    fuse_opt_free_args(&args);
    return ret;
}
