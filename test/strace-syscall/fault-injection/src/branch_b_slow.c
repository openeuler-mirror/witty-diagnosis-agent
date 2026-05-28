/**
 * branch_b_slow.c - Slow Syscall Pattern Injection
 * Modes: futex | slowio | slowopen | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 * Compile: gcc -O2 -o branch_b_slow branch_b_slow.c -lpthread
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <sys/epoll.h>
#include <sys/timerfd.h>
#include <sys/stat.h>
#include <sys/time.h>

typedef struct { pthread_mutex_t *mutex; int thread_id; int work_cycles; } futex_arg_t;

static void *futex_worker(void *arg) {
    futex_arg_t *a = (futex_arg_t *)arg;
    for (int i = 0; i < a->work_cycles; i++) {
        pthread_mutex_lock(a->mutex);
        struct timeval start, now;
        gettimeofday(&start, NULL);
        do { gettimeofday(&now, NULL);
            long e = (now.tv_sec-start.tv_sec)*1000000 + (now.tv_usec-start.tv_usec);
            if (e >= 50000) break;
        } while (1);
        pthread_mutex_unlock(a->mutex);
        usleep(10000);
    }
    return NULL;
}

static void fault_futex(int cycles) {
    printf("[futex] 4 threads %d cycles 50ms CS\n", cycles);
    pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_t t[4]; futex_arg_t a[4];
    for (int i = 0; i < 4; i++) {
        a[i].mutex=&mutex; a[i].thread_id=i; a[i].work_cycles=cycles;
        pthread_create(&t[i],NULL,futex_worker,&a[i]);
    }
    for (int i = 0; i < 4; i++) pthread_join(t[i],NULL);
    pthread_mutex_destroy(&mutex);
}

static void fault_slowio(int cycles) {
    printf("[slowio] %d cycles\n", cycles);
    int tfd = timerfd_create(CLOCK_MONOTONIC,0);
    int epfd = epoll_create1(0);
    struct epoll_event ev={.events=EPOLLIN,.data.fd=tfd};
    epoll_ctl(epfd,EPOLL_CTL_ADD,tfd,&ev);
    for (int i=0;i<cycles&&i<3;i++) {
        struct itimerspec ts={.it_value={.tv_sec=0,.tv_nsec=200000000}};
        timerfd_settime(tfd,0,&ts,NULL);
        printf("  epoll_wait 200ms...\n");
        struct epoll_event evs[4]; int n=epoll_wait(epfd,evs,4,3000);
        if(n>0){uint64_t ex;read(tfd,&ex,sizeof(ex));printf("  epoll_wait done\n");}
    }
    int p2[2]; pipe(p2);
    pid_t pid=fork();
    if(pid==0){close(p2[0]);sleep(2);write(p2[1],"hello",5);close(p2[1]);_exit(0);}
    close(p2[1]); char buf[64];
    printf("  read() block ~2s...\n"); ssize_t n=read(p2[0],buf,sizeof(buf));
    if(n>0){buf[n]=0;printf("  read done: \"%s\"\n",buf);} close(p2[0]);
    close(epfd); close(tfd);
}

static void fault_slowopen(int cycles) {
    printf("[slowopen] %d files\n", cycles);
    char dir[128]; snprintf(dir,sizeof(dir),"/tmp/slo_%d",getpid());
    mkdir(dir,0755); int n=cycles>50?50:cycles;
    for(int i=0;i<n;i++){char p[256];snprintf(p,sizeof(p),"%s/f%04d",dir,i);int f=open(p,O_CREAT|O_WRONLY|O_TRUNC,0644);if(f>=0){write(f,"t",1);close(f);}}
    for(int i=0;i<n;i++){char p[256];snprintf(p,sizeof(p),"%s/f%04d",dir,i);struct stat s;stat(p,&s);int f=open(p,O_RDONLY);if(f>=0)close(f);}
    for(int i=0;i<n;i++){char p[256];snprintf(p,sizeof(p),"%s/f%04d",dir,i);unlink(p);}
    rmdir(dir);
}

static void run_all(int c) { fault_futex(c>2?5:2); printf("---\n"); fault_slowio(2); printf("---\n"); fault_slowopen(c); }

int main(int argc,char*argv[]){
    const char*mode="all"; int cycles=10; int loop=0;
    if(argc>1&&strcmp(argv[1],"--loop")==0){loop=1;if(argc>2)mode=argv[2];}
    else if(argc>1){mode=argv[1];if(argc>2)cycles=atoi(argv[2]);}
    if(cycles<1)cycles=1;if(cycles>100000)cycles=100000;
    printf("=== B mode=%s loop=%d cycles=%d\n",mode,loop,cycles);
    if(loop){while(1){
        if(strcmp(mode,"futex")==0)fault_futex(5);
        else if(strcmp(mode,"slowio")==0)fault_slowio(2);
        else if(strcmp(mode,"slowopen")==0)fault_slowopen(10);
        else{fault_futex(3);printf("---\n");fault_slowio(1);printf("---\n");fault_slowopen(10);}
        sleep(2);
    }}
    if(strcmp(mode,"futex")==0)fault_futex(cycles);
    else if(strcmp(mode,"slowio")==0)fault_slowio(cycles);
    else if(strcmp(mode,"slowopen")==0)fault_slowopen(cycles);
    else if(strcmp(mode,"all")==0)run_all(cycles);
    else{fprintf(stderr,"Usage: %s [--loop] <mode>\n",argv[0]);return 1;}
    printf("=== B done ===\n"); return 0;
}
