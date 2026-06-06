/**
 * fuse_slow_daemon.c — FUSE daemon that artificially delays requests
 *
 * Injects Branch B fault (Request Queue Block).
 * All read/write operations are delayed by a configurable amount.
 * The delay causes waiting to increase and D-state processes to appear.
 *
 * Build: gcc -o fuse_slow_daemon fuse_slow_daemon.c `pkg-config --cflags --libs fuse3`
 * Usage: ./fuse_slow_daemon -f <mount_point> [-o delay_ms=500]
 * Control: echo "delay=2000" > <mount_point>/ctl_delay
 *          echo "delay=0" > <mount_point>/ctl_delay    # reset
 */

#define FUSE_USE_VERSION 31

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <pthread.h>

/* Configurable delay (ms) */
static int delay_ms = 500;
static pthread_mutex_t delay_mutex = PTHREAD_MUTEX_INITIALIZER;
static int request_count = 0;

/* In-memory file storage */
#define MAX_SIZE (1024 * 1024)
static char *file_data = NULL;
static size_t file_size = 0;

static void apply_delay(void) {
    pthread_mutex_lock(&delay_mutex);
    int d = delay_ms;
    request_count++;
    pthread_mutex_unlock(&delay_mutex);
    if (d > 0)
        usleep(d * 1000);
}

static int fuse_getattr(const char *path, struct stat *stbuf) {
    apply_delay();
    memset(stbuf, 0, sizeof(struct stat));
    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }
    if (strcmp(path, "/ctl_delay") == 0) {
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        stbuf->st_size = 0;
        stbuf->st_uid = getuid();
        stbuf->st_gid = getgid();
        return 0;
    }
    if (strcmp(path, "/test_file") == 0) {
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        stbuf->st_size = file_size;
        stbuf->st_uid = getuid();
        stbuf->st_gid = getgid();
        return 0;
    }
    return -ENOENT;
}

static int fuse_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    apply_delay();
    (void)offset;
    (void)fi;
    if (strcmp(path, "/") != 0) return -ENOENT;
    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);
    filler(buf, "ctl_delay", NULL, 0);
    filler(buf, "test_file", NULL, 0);
    return 0;
}

static int fuse_open(const char *path, struct fuse_file_info *fi) {
    apply_delay();
    return 0;
}

static int fuse_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    apply_delay();
    if (strcmp(path, "/ctl_delay") == 0) {
        pthread_mutex_lock(&delay_mutex);
        char status[64];
        int n = snprintf(status, sizeof(status), "delay=%dms reqs=%d\n",
                        delay_ms, request_count);
        pthread_mutex_unlock(&delay_mutex);
        if (offset >= n) return 0;
        size_t to_copy = size < (size_t)(n - offset) ? size : (size_t)(n - offset);
        memcpy(buf, status + offset, to_copy);
        return to_copy;
    }
    if (strcmp(path, "/test_file") != 0) return -ENOENT;
    if (offset >= (off_t)file_size) return 0;
    size_t remaining = file_size - offset;
    size_t to_read = size < remaining ? size : remaining;
    if (file_data) memcpy(buf, file_data + offset, to_read);
    return to_read;
}

static int fuse_write(const char *path, const char *buf, size_t size,
                      off_t offset, struct fuse_file_info *fi) {
    apply_delay();
    if (strcmp(path, "/ctl_delay") == 0) {
        char cmd[64];
        size_t len = size < (sizeof(cmd) - 1) ? size : (sizeof(cmd) - 1);
        memcpy(cmd, buf, len);
        cmd[len] = '\0';
        if (len > 0 && cmd[len-1] == '\n') cmd[len-1] = '\0';

        if (sscanf(cmd, "delay=%d", &delay_ms) == 1) {
            pthread_mutex_lock(&delay_mutex);
            delay_ms = delay_ms;
            pthread_mutex_unlock(&delay_mutex);
        }
        return size;
    }

    if (strcmp(path, "/test_file") != 0) return -ENOENT;
    if (!file_data) file_data = calloc(1, MAX_SIZE);
    if (offset + size > MAX_SIZE) return -EFBIG;
    memcpy(file_data + offset, buf, size);
    if (offset + size > file_size) file_size = offset + size;
    return size;
}

static int fuse_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    apply_delay();
    return 0;
}

static int fuse_unlink(const char *path) {
    apply_delay();
    return 0;
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
    .unlink     = fuse_unlink,
    .release    = fuse_release,
};

int main(int argc, char *argv[]) {
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);

    /* Parse custom options */
    struct fuse_opt fuse_opts[] = {
        { "delay_ms=%d", offsetof(struct fuse_args, argv), 0 },
        FUSE_OPT_END
    };
    /* Manually check for -o delay_ms= */
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-o", 2) == 0 && i + 1 < argc) {
            if (sscanf(argv[i+1], "delay_ms=%d", &delay_ms) == 1) {
                /* Remove the delay option from args */
                memmove(&argv[i+1], &argv[i+2], (argc - i - 1) * sizeof(char*));
                argc--;
                break;
            }
        }
    }
    args.argc = argc;
    args.argv = argv;

    int ret = fuse_main(args.argc, args.argv, &fuse_ops, NULL);
    free(file_data);
    fuse_opt_free_args(&args);
    return ret;
}
