// Raw-syscall io_uring fault probe for kernel-io-uring-diagnosis tests.
// This program intentionally avoids liburing so the test can run with standard
// Linux headers and gcc.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/io_uring.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

#ifndef SYS_io_uring_setup
# if defined(__x86_64__)
#  define SYS_io_uring_setup 425
#  define SYS_io_uring_enter 426
#  define SYS_io_uring_register 427
# elif defined(__aarch64__)
#  define SYS_io_uring_setup 425
#  define SYS_io_uring_enter 426
#  define SYS_io_uring_register 427
# else
#  error "SYS_io_uring_* syscall numbers are not defined for this architecture"
# endif
#endif

static int xio_uring_setup(unsigned entries, struct io_uring_params *params)
{
    return (int)syscall(SYS_io_uring_setup, entries, params);
}

static int xio_uring_register(int fd, unsigned opcode, const void *arg,
                              unsigned nr_args)
{
    return (int)syscall(SYS_io_uring_register, fd, opcode, arg, nr_args);
}

static int xio_uring_enter(int fd, unsigned to_submit, unsigned min_complete,
                           unsigned flags)
{
    return (int)syscall(SYS_io_uring_enter, fd, to_submit, min_complete, flags,
                        NULL, 0);
}

static void print_errno(const char *label, int ret)
{
    if (ret >= 0) {
        printf("%s: ret=%d errno=0\n", label, ret);
        return;
    }
    printf("%s: ret=%d errno=%d (%s)\n", label, ret, errno, strerror(errno));
}

static int setup_ring(unsigned entries, unsigned flags)
{
    struct io_uring_params params;
    memset(&params, 0, sizeof(params));
    params.flags = flags;
    int fd = xio_uring_setup(entries, &params);
    print_errno("io_uring_setup", fd);
    if (fd >= 0) {
        printf("setup_entries=%u setup_flags=0x%x returned_features=0x%x\n",
               entries, flags, params.features);
    }
    return fd;
}

static int scenario_baseline(void)
{
    int fd = setup_ring(8, 0);
    if (fd >= 0) {
        close(fd);
        return 0;
    }
    return errno == ENOSYS ? 2 : 1;
}

static int scenario_memlock(void)
{
    int fd = setup_ring(8, 0);
    if (fd < 0) {
        return 1;
    }

    size_t len = 4 * 1024 * 1024;
    void *buf = mmap(NULL, len, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buf == MAP_FAILED) {
        print_errno("mmap_fixed_buffer", -1);
        close(fd);
        return 1;
    }

    struct iovec iov;
    iov.iov_base = buf;
    iov.iov_len = len;

    errno = 0;
    int ret = xio_uring_register(fd, IORING_REGISTER_BUFFERS, &iov, 1);
    print_errno("io_uring_register_buffers", ret);
    printf("registered_buffer_bytes=%zu\n", len);

    if (ret == 0) {
        xio_uring_register(fd, IORING_UNREGISTER_BUFFERS, NULL, 0);
    }
    munmap(buf, len);
    close(fd);
    return ret == 0 ? 0 : 1;
}

static int scenario_ring(void)
{
    int fd = setup_ring(2, 0);
    if (fd < 0) {
        return 1;
    }
    errno = 0;
    int ret = xio_uring_enter(fd, 0, 0, 0);
    print_errno("io_uring_enter_empty", ret);
    printf("ring_pressure_hint=entries=2; use application logs to confirm SQ full or CQ overflow\n");
    close(fd);
    return 0;
}

static int scenario_sqpoll(void)
{
    int fd = setup_ring(8, IORING_SETUP_SQPOLL);
    if (fd >= 0) {
        close(fd);
        return 0;
    }
    return 1;
}

static int scenario_odirect(void)
{
    char path[] = "/tmp/io-uring-odirect-test-file.XXXXXX";
    int tmpfd = mkstemp(path);
    if (tmpfd < 0) {
        print_errno("mkstemp", -1);
        return 1;
    }
    close(tmpfd);

    int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY | O_DIRECT, 0600);
    if (fd < 0) {
        print_errno("open_O_DIRECT", -1);
        unlink(path);
        return 1;
    }

    char *buf = malloc(4097);
    if (!buf) {
        close(fd);
        unlink(path);
        return 1;
    }
    memset(buf, 'A', 4097);
    errno = 0;
    ssize_t wr = write(fd, buf + 1, 4096);
    if (wr < 0) {
        printf("O_DIRECT_unaligned_write: ret=%zd errno=%d (%s)\n", wr, errno,
               strerror(errno));
    } else {
        printf("O_DIRECT_unaligned_write: ret=%zd errno=0\n", wr);
    }
    printf("odirect_buffer_offset=1 length=4096 file_offset=0\n");

    free(buf);
    close(fd);
    unlink(path);
    return wr < 0 && errno == EINVAL ? 0 : 1;
}

static int scenario_compat(void)
{
    printf("compat_probe_kernel_header=linux/io_uring.h available\n");
#ifdef IORING_FEAT_SINGLE_MMAP
    printf("header_feature=IORING_FEAT_SINGLE_MMAP\n");
#endif
#ifdef IORING_FEAT_NODROP
    printf("header_feature=IORING_FEAT_NODROP\n");
#endif
#ifdef IORING_FEAT_NATIVE_WORKERS
    printf("header_feature=IORING_FEAT_NATIVE_WORKERS\n");
#endif
    int fd = setup_ring(8, 0);
    if (fd >= 0) {
        close(fd);
        return 0;
    }
    return errno == ENOSYS ? 2 : 1;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <baseline|memlock|ring|sqpoll|odirect|compat>\n",
                argv[0]);
        return 2;
    }

    if (strcmp(argv[1], "baseline") == 0) {
        return scenario_baseline();
    }
    if (strcmp(argv[1], "memlock") == 0) {
        return scenario_memlock();
    }
    if (strcmp(argv[1], "ring") == 0) {
        return scenario_ring();
    }
    if (strcmp(argv[1], "sqpoll") == 0) {
        return scenario_sqpoll();
    }
    if (strcmp(argv[1], "odirect") == 0) {
        return scenario_odirect();
    }
    if (strcmp(argv[1], "compat") == 0) {
        return scenario_compat();
    }

    fprintf(stderr, "unknown scenario: %s\n", argv[1]);
    return 2;
}
