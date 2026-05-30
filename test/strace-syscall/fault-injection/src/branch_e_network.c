/**
 * branch_e_network.c - Network Syscall Error Pattern Injection
 * Modes: econnrefused | etimedout | econnreset | epipe | eaddrinuse | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 * Compile: gcc -O2 -o branch_e_network branch_e_network.c -lpthread
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <pthread.h>

static void fault_econnrefused(int cycles) {
    printf("[econnrefused] %d cycles\n", cycles);
    for (int i=0;i<cycles;i++){
        int s=socket(AF_INET,SOCK_STREAM,0); if(s<0)continue;
        struct sockaddr_in a; memset(&a,0,sizeof(a));
        a.sin_family=AF_INET; a.sin_port=htons(34987+i); a.sin_addr.s_addr=inet_addr("127.0.0.1");
        int r=connect(s,(struct sockaddr*)&a,sizeof(a));
        if(r==-1) printf("  connect(127.0.0.1:%d) = -1 %s\n",34987+i,strerror(errno));
        close(s); usleep(50000);
    }
}

static void *reset_server(void *arg){
    int port=*(int*)arg;
    int s=socket(AF_INET,SOCK_STREAM,0); int opt=1;
    setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&opt,sizeof(opt));
    struct sockaddr_in a; memset(&a,0,sizeof(a));
    a.sin_family=AF_INET; a.sin_addr.s_addr=INADDR_ANY; a.sin_port=htons(port);
    bind(s,(struct sockaddr*)&a,sizeof(a)); listen(s,1);
    struct sockaddr_in ca; socklen_t cl=sizeof(ca);
    int c=accept(s,(struct sockaddr*)&ca,&cl);
    if(c>=0){struct linger l={.l_onoff=1,.l_linger=0};setsockopt(c,SOL_SOCKET,SO_LINGER,&l,sizeof(l));close(c);}
    close(s); return NULL;
}

static void fault_econnreset(int cycles){
    printf("[econnreset] %d cycles\n", cycles);
    int port=43000+(getpid()%5000);
    for(int i=0;i<cycles&&i<3;i++){
        int sp=port+i*2; pthread_t t;
        pthread_create(&t,NULL,reset_server,&sp); usleep(200000);
        int s=socket(AF_INET,SOCK_STREAM,0);
        struct sockaddr_in a; memset(&a,0,sizeof(a));
        a.sin_family=AF_INET; a.sin_port=htons(sp); inet_pton(AF_INET,"127.0.0.1",&a.sin_addr);
        if(connect(s,(struct sockaddr*)&a,sizeof(a))==0){
            printf("  connected, reading (will get ECONNRESET)...\n");
            char b[64]; ssize_t n=read(s,b,sizeof(b));
            if(n==-1) printf("  read() = -1 %s\n",strerror(errno));
        }
        close(s); pthread_join(t,NULL);
    }
}

static void *pipe_server(void *arg){
    int port=*(int*)arg;
    int s=socket(AF_INET,SOCK_STREAM,0); int opt=1;
    setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&opt,sizeof(opt));
    struct sockaddr_in a; memset(&a,0,sizeof(a));
    a.sin_family=AF_INET; a.sin_addr.s_addr=INADDR_ANY; a.sin_port=htons(port);
    bind(s,(struct sockaddr*)&a,sizeof(a)); listen(s,1);
    struct sockaddr_in ca; socklen_t cl=sizeof(ca);
    int c=accept(s,(struct sockaddr*)&ca,&cl);
    if(c>=0){char t;recv(c,&t,1,0);shutdown(c,SHUT_RDWR);close(c);}
    close(s); return NULL;
}

static void fault_epipe(int cycles){
    printf("[epipe] %d cycles\n", cycles);
    signal(SIGPIPE,SIG_IGN); printf("  SIGPIPE ignored -> EPIPE\n");
    int port=44000+(getpid()%5000);
    for(int i=0;i<cycles&&i<3;i++){
        int sp=port+i*2; pthread_t t;
        pthread_create(&t,NULL,pipe_server,&sp); usleep(200000);
        int s=socket(AF_INET,SOCK_STREAM,0);
        struct sockaddr_in a; memset(&a,0,sizeof(a));
        a.sin_family=AF_INET; a.sin_port=htons(sp); inet_pton(AF_INET,"127.0.0.1",&a.sin_addr);
        if(connect(s,(struct sockaddr*)&a,sizeof(a))==0){
            send(s,"hello",5,0); usleep(300000);
            printf("  write to closed socket...\n");
            ssize_t n=send(s,"data",4,0);
            if(n==-1) printf("  send() = -1 %s\n",strerror(errno));
        }
        close(s); pthread_join(t,NULL);
    }
}

static void fault_eaddrinuse(int cycles){
    printf("[eaddrinuse] %d cycles\n", cycles);
    int port=45000+(getpid()%5000);
    for(int i=0;i<cycles&&i<3;i++){
        int sp=port+i*2;
        int s1=socket(AF_INET,SOCK_STREAM,0);
        struct sockaddr_in a; memset(&a,0,sizeof(a));
        a.sin_family=AF_INET; a.sin_addr.s_addr=INADDR_ANY; a.sin_port=htons(sp);
        if(bind(s1,(struct sockaddr*)&a,sizeof(a))==0){
            printf("  first bind(port %d) = OK\n",sp); listen(s1,1);
            int s2=socket(AF_INET,SOCK_STREAM,0);
            if(s2>=0){int r=bind(s2,(struct sockaddr*)&a,sizeof(a));if(r==-1)printf("  second bind(port %d) = -1 %s\n",sp,strerror(errno));close(s2);}
            close(s1);
        }
        usleep(100000);
    }
}

static void run_all(int c){fault_econnrefused(c);printf("---\n");fault_econnreset(c);printf("---\n");fault_epipe(c);printf("---\n");fault_eaddrinuse(c);}

int main(int argc,char*argv[]){
    const char*mode="all"; int cycles=5; int loop=0;
    if(argc>1&&strcmp(argv[1],"--loop")==0){loop=1;if(argc>2)mode=argv[2];}
    else if(argc>1){mode=argv[1];if(argc>2)cycles=atoi(argv[2]);}
    if(cycles<1)cycles=1;if(cycles>100000)cycles=100000;
    printf("=== E mode=%s loop=%d cycles=%d\n",mode,loop,cycles);
    if(loop){while(1){
        if(strcmp(mode,"econnrefused")==0)fault_econnrefused(3);
        else if(strcmp(mode,"econnreset")==0)fault_econnreset(2);
        else if(strcmp(mode,"epipe")==0)fault_epipe(2);
        else if(strcmp(mode,"eaddrinuse")==0)fault_eaddrinuse(2);
        else{fault_econnrefused(2);printf("---\n");fault_econnreset(1);printf("---\n");fault_epipe(1);printf("---\n");fault_eaddrinuse(1);}
        sleep(3);
    }}
    if(strcmp(mode,"econnrefused")==0)fault_econnrefused(cycles);
    else if(strcmp(mode,"econnreset")==0)fault_econnreset(cycles);
    else if(strcmp(mode,"epipe")==0)fault_epipe(cycles);
    else if(strcmp(mode,"eaddrinuse")==0)fault_eaddrinuse(cycles);
    else if(strcmp(mode,"all")==0)run_all(cycles);
    else{fprintf(stderr,"Usage: %s [--loop] <mode>\n",argv[0]);return 1;}
    printf("=== E done ===\n"); return 0;
}
