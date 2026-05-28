/**
 * branch_d_leak.c - FD/Resource Leak Pattern Injection
 * Modes: fd_leak | mmap_leak | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 * Compile: gcc -O2 -o branch_d_leak branch_d_leak.c -lpthread
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/resource.h>

static void fault_fd_leak(int cycles) {
    printf("[fd_leak] %d cycles (leak 3 FD/cycle)\n", cycles);
    struct rlimit rl = {.rlim_cur=65535,.rlim_max=65535};
    setrlimit(RLIMIT_NOFILE,&rl);
    int leaked=0;
    int *fds = malloc(cycles*3*sizeof(int));
    for (int i=0;i<cycles;i++){
        char p[256]; snprintf(p,sizeof(p),"/tmp/fdl_%d_%d.tmp",getpid(),i);
        int fd = open(p,O_CREAT|O_RDWR,0644);
        if(fd>=0){fds[leaked++]=fd;write(fd,"l",1);printf("  LEAK open(%s)=%d\n",p,fd);}
        fd = open("/dev/null",O_RDWR);
        if(fd>=0){fds[leaked++]=fd;printf("  LEAK open(/dev/null)=%d\n",fd);}
        fd = dup(1);
        if(fd>=0){fds[leaked++]=fd;printf("  LEAK dup(1)=%d\n",fd);}
        int nf = open("/proc/self/status",O_RDONLY);
        if(nf>=0){char b[256];read(nf,b,sizeof(b));close(nf);printf("  OK close(%d)\n",nf);}
        usleep(50000);
    }
    printf("  Leaked %d FD total\n",leaked);
    free(fds);
}

static void fault_mmap_leak(int cycles) {
    printf("[mmap_leak] %d cycles\n", cycles);
    void **maps = malloc(cycles*sizeof(void*));
    int leaked=0;
    for (int i=0;i<cycles;i++){
        void *p = mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
        if(p!=MAP_FAILED){maps[leaked++]=p;*(volatile char*)p=0xBB;printf("  LEAK mmap=%p\n",p);}
        else break;
        void *g = mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
        if(g!=MAP_FAILED){*(volatile char*)g=0xAA;munmap(g,4096);printf("  OK mmap/munmap\n");}
        usleep(20000);
    }
    printf("  Leaked %d mmap regions\n",leaked);
    free(maps);
}

static void run_all(int c) { fault_fd_leak(c>30?30:c); printf("---\n"); fault_mmap_leak(c>30?30:c); }

int main(int argc,char*argv[]){
    const char*mode="all"; int cycles=20; int loop=0;
    if(argc>1&&strcmp(argv[1],"--loop")==0){loop=1;if(argc>2)mode=argv[2];}
    else if(argc>1){mode=argv[1];if(argc>2)cycles=atoi(argv[2]);}
    if(cycles<1)cycles=1;if(cycles>100000)cycles=100000;
    printf("=== D mode=%s loop=%d cycles=%d\n",mode,loop,cycles);
    if(loop){while(1){
        if(strcmp(mode,"fd_leak")==0)fault_fd_leak(10);
        else if(strcmp(mode,"mmap_leak")==0)fault_mmap_leak(10);
        else{fault_fd_leak(5);printf("---\n");fault_mmap_leak(5);}
        sleep(2);
    }}
    if(strcmp(mode,"fd_leak")==0)fault_fd_leak(cycles);
    else if(strcmp(mode,"mmap_leak")==0)fault_mmap_leak(cycles);
    else if(strcmp(mode,"all")==0)run_all(cycles);
    else{fprintf(stderr,"Usage: %s [--loop] <mode>\n",argv[0]);return 1;}
    printf("=== D done ===\n"); return 0;
}
