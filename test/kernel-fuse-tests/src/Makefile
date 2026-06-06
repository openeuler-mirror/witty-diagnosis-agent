# Makefile for FUSE test daemons
# Build: make
# Clean: make clean

CFLAGS = -Wall -Wextra -g -O0 $(shell pkg-config --cflags fuse3 2>/dev/null || pkg-config --cflags fuse 2>/dev/null)
LDFLAGS = $(shell pkg-config --libs fuse3 2>/dev/null || pkg-config --libs fuse 2>/dev/null)
BINDIR = bin

TARGETS = \
	$(BINDIR)/fuse_test_daemon \
	$(BINDIR)/fuse_crash_daemon \
	$(BINDIR)/fuse_slow_daemon \

.PHONY: all clean dirs

all: dirs $(TARGETS)

dirs:
	mkdir -p $(BINDIR)

$(BINDIR)/fuse_test_daemon: fuse_test_daemon.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(BINDIR)/fuse_crash_daemon: fuse_crash_daemon.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(BINDIR)/fuse_slow_daemon: fuse_slow_daemon.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -rf $(BINDIR)

run_test:
	@echo "=== Test: Basic FUSE mount ==="
	mkdir -p /tmp/fuse_test
	./$(BINDIR)/fuse_test_daemon -f /tmp/fuse_test &
	sleep 2
	ls -la /tmp/fuse_test
	echo "=== Cleaning ==="
	-fusermount -u /tmp/fuse_test 2>/dev/null
	kill %1 2>/dev/null
	rmdir /tmp/fuse_test 2>/dev/null
