/**
 * branch_f_signal.c - Signal/Interrupt Pattern Injection
 * Modes: eintr | sigpipe | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 * Compile: gcc -O2 -o branch_f_signal branch_f_signal.c -lpthread
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/wait.h>

static volatile int eintr_count = 0;
static void sig_handler(int s) { eintr_count++; }

static void fault_eintr(int cycles) {
    printf("[eintr] %d cycles, SIGALRM 100ms NO SA_RESTART\n", cycles);
    struct sigaction sa; memset(&sa,0,sizeof(sa)); sa.sa_handler=sig_handler; sa.sa_flags=0;
    sigaction(SIGALRM,&sa,NULL);
    struct itimerval timer={.it_value={.tv_usec=100000},.it_interval={.tv_usec=100000}};
    setitimer(ITIMER_REAL,&timer,NULL);
    for(int i=0;i<cycles;i++){
        int p[2]; pipe(p);
        printf("  read() on empty pipe (will get EINTR)...\n");
        char b[64]; errno=0; ssize_t n=read(p[0],b,sizeof(b));
        if(n==-1&&errno==EINTR) printf("  read() = -1 EINTR (#%d)\n",eintr_count);
        close(p[0]); close(p[1]);
        if(i%3==0){kill(getpid(),SIGUSR1);usleep(10000);}
    }
    struct itimerval z={0}; setitimer(ITIMER_REAL,&z,NULL);
}

static void fault_sigpipe(int cycles) {
    printf("[sigpipe] %d cycles (Phase1:EPIPE Phase2:SIGPIPE)\n", cycles);
    signal(SIGPIPE,SIG_IGN);
    for(int i=0;i<cycles;i++){
        int p[2]; pipe(p); close(p[0]);
        printf("  write broken pipe (ignored SIGPIPE -> EPIPE)...\n");
        ssize_t n=write(p[1],"data",4); if(n==-1) printf("  write() = -1 %s\n",strerror(errno));
        close(p[1]); usleep(50000);
    }
    printf("  Phase2: fork child with SIGPIPE=default\n");
    pid_t pid=fork();
    if(pid==0){signal(SIGPIPE,SIG_DFL);int p[2];pipe(p);close(p[0]);write(p[1],"data",4);_exit(0);}
    else if(pid>0){int s;waitpid(pid,&s,0);
        if(WIFSIGNALED(s))printf("  child killed by SIGPIPE (signal %d)\n",WTERMSIG(s));
    }
}

static void run_all(int c){fault_eintr(c);printf("---\n");fault_sigpipe(c>5?3:c);}

int main(int argc,char*argv[]){
    const char*mode="all"; int cycles=5; int loop=0;
    if(argc>1&&strcmp(argv[1],"--loop")==0){loop=1;if(argc>2)mode=argv[2];}
    else if(argc>1){mode=argv[1];if(argc>2)cycles=atoi(argv[2]);}
    if(cycles<1)cycles=1;if(cycles>100000)cycles=100000;
    printf("=== F mode=%s loop=%d cycles=%d\n",mode,loop,cycles);
    if(loop){while(1){
        if(strcmp(mode,"eintr")==0)fault_eintr(3);
        else if(strcmp(mode,"sigpipe")==0)fault_sigpipe(2);
        else{fault_eintr(2);printf("---\n");fault_sigpipe(1);}
        sleep(2);
    }}
    if(strcmp(mode,"eintr")==0)fault_eintr(cycles);
    else if(strcmp(mode,"sigpipe")==0)fault_sigpipe(cycles);
    else if(strcmp(mode,"all")==0)run_all(cycles);
    else{fprintf(stderr,"Usage: %s [--loop] <mode>\n",argv[0]);return 1;}
    printf("=== F done ===\n"); return 0;
}
