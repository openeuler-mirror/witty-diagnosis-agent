/**
 * fuse_test_daemon.c — Minimal FUSE test daemon
 *
 * A simple FUSE filesystem that stores files in memory.
 * Used as a baseline test target for FUSE diagnosis skills.
 *
 * Build: gcc -o fuse_test_daemon fuse_test_daemon.c `pkg-config --cflags --libs fuse3`
 * Usage: ./fuse_test_daemon -f <mount_point>
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

/* Simple in-memory file storage */
#define MAX_FILES 128
#define MAX_NAME 256
#define MAX_SIZE (1024 * 1024) /* 1MB per file */

struct fuse_file_entry {
    char name[MAX_NAME];
    char *data;
    size_t size;
    int exists;
};

static struct fuse_file_entry files[MAX_FILES];
static int file_count = 0;

static int find_file(const char *path) {
    for (int i = 0; i < MAX_FILES; i++) {
        if (files[i].exists && strcmp(files[i].name, path) == 0)
            return i;
    }
    return -1;
}

static int add_file(const char *path) {
    if (file_count >= MAX_FILES)
        return -1;
    int idx = -1;
    for (int i = 0; i < MAX_FILES; i++) {
        if (!files[i].exists) { idx = i; break; }
    }
    if (idx < 0) return -1;
    strncpy(files[idx].name, path, MAX_NAME - 1);
    files[idx].data = calloc(1, MAX_SIZE);
    files[idx].size = 0;
    files[idx].exists = 1;
    file_count++;
    return idx;
}

static int fuse_getattr(const char *path, struct stat *stbuf) {
    memset(stbuf, 0, sizeof(struct stat));
    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }
    int idx = find_file(path);
    if (idx < 0) return -ENOENT;
    stbuf->st_mode = S_IFREG | 0644;
    stbuf->st_nlink = 1;
    stbuf->st_size = files[idx].size;
    stbuf->st_uid = getuid();
    stbuf->st_gid = getgid();
    return 0;
}

static int fuse_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    (void)offset;
    (void)fi;
    if (strcmp(path, "/") != 0) return -ENOENT;
    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);
    for (int i = 0; i < MAX_FILES; i++) {
        if (files[i].exists) {
            filler(buf, files[i].name + 1, NULL, 0);
        }
    }
    return 0;
}

static int fuse_open(const char *path, struct fuse_file_info *fi) {
    int idx = find_file(path);
    if (idx < 0) return -ENOENT;
    return 0;
}

static int fuse_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    int idx = find_file(path);
    if (idx < 0) return -ENOENT;
    if (offset >= (off_t)files[idx].size)
        return 0;
    size_t remaining = files[idx].size - offset;
    size_t to_read = size < remaining ? size : remaining;
    memcpy(buf, files[idx].data + offset, to_read);
    return to_read;
}

static int fuse_write(const char *path, const char *buf, size_t size,
                      off_t offset, struct fuse_file_info *fi) {
    int idx = find_file(path);
    if (idx < 0) {
        idx = add_file(path);
        if (idx < 0) return -ENOSPC;
    }
    if (offset + size > MAX_SIZE)
        return -EFBIG;
    memcpy(files[idx].data + offset, buf, size);
    if (offset + size > files[idx].size)
        files[idx].size = offset + size;
    return size;
}

static int fuse_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    int idx = add_file(path);
    if (idx < 0) return -ENOSPC;
    return 0;
}

static int fuse_unlink(const char *path) {
    int idx = find_file(path);
    if (idx < 0) return -ENOENT;
    free(files[idx].data);
    files[idx].exists = 0;
    file_count--;
    return 0;
}

static int fuse_truncate(const char *path, off_t size) {
    int idx = find_file(path);
    if (idx < 0) return -ENOENT;
    files[idx].size = size;
    return 0;
}

static int fuse_release(const char *path, struct fuse_file_info *fi) {
    (void)path;
    (void)fi;
    return 0;
}

static int fuse_flush(const char *path, struct fuse_file_info *fi) {
    (void)path;
    (void)fi;
    return 0;
}

static int fuse_fsync(const char *path, int isdatasync, struct fuse_file_info *fi) {
    (void)path;
    (void)isdatasync;
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
    .truncate   = fuse_truncate,
    .release    = fuse_release,
    .flush      = fuse_flush,
    .fsync      = fuse_fsync,
};

int main(int argc, char *argv[]) {
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    int ret = fuse_main(args.argc, args.argv, &fuse_ops, NULL);
    fuse_opt_free_args(&args);
    return ret;
}
