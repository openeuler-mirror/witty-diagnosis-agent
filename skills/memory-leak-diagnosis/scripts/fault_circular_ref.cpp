/*
 * fault_circular_ref.cpp — C++ shared_ptr 循环引用泄漏模拟器 (Branch C3)
 * shared_ptr 循环引用导致引用计数永不归零，内存泄漏
 *
 * Usage: ./fault_circular_ref [iterations] [sleep_sec]
 * Default: 1000 iterations, sleep 30
 */
#include <iostream>
#include <memory>
#include <vector>
#include <cstring>
#include <unistd.h>
#include <signal.h>

volatile bool running = true;
void handle_sigint(int) { running = false; }

struct Node {
    std::shared_ptr<Node> next;  // 循环引用的关键
    std::vector<char> data;
    int id;

    Node(int i, size_t size) : id(i), data(size, 'D') {
        // std::cout << "Node " << id << " created" << std::endl;
    }
    ~Node() {
        // std::cout << "Node " << id << " destroyed" << std::endl;
    }
};

int main(int argc, char *argv[]) {
    int iterations = argc > 1 ? atoi(argv[1]) : 1000;
    int sleep_time = argc > 2 ? atoi(argv[2]) : 30;
    signal(SIGINT, handle_sigint);

    std::vector<std::shared_ptr<Node>> roots;
    const size_t DATA_SIZE = 1024 * 100;  // 100KB per node

    printf("[fault_circular_ref] PID=%d, %d iterations, %zu KB/cycle\n",
           getpid(), iterations, (DATA_SIZE * 2) / 1024);

    for (int i = 0; i < iterations && running; i++) {
        // Create two nodes with circular reference
        auto a = std::make_shared<Node>(i * 2, DATA_SIZE);
        auto b = std::make_shared<Node>(i * 2 + 1, DATA_SIZE);

        // Create the cycle: a->next = b, b->next = a
        a->next = b;
        b->next = a;

        // Keep root reference to prevent immediate stack cleanup
        roots.push_back(a);

        if (i % 100 == 0) {
            printf("[%d] Created %d nodes, RSS:", i/100, (i+1)*2);
            fflush(stdout);
            FILE *f = fopen("/proc/self/status", "r");
            if (f) {
                char line[256];
                while (fgets(line, sizeof(line), f)) {
                    if (strncmp(line, "VmRSS:", 6) == 0)
                        printf(" %s", line);
                }
                fclose(f);
            }
        }
    }

    printf("\n[fault_circular_ref] Created %d nodes. Holding for %ds...\n",
           iterations * 2, sleep_time);
    printf("  Root references NOT cleared -> circular refs prevent destruction\n");
    sleep(sleep_time);

    printf("[fault_circular_ref] Done.\n");
    return 0;
}
