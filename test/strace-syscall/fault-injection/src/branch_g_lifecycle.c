/**
 * branch_g_lifecycle.c - Process Lifecycle Anomaly Pattern Injection
 * Modes: fork_storm | execve_fail | zombie | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 * Compile: gcc -O2 -o branch_g_lifecycle branch_g_lifecycle.c -lpthread
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
#include <sys/wait.h>
#include <sys/stat.h>

static void fault_fork_storm(int cycles) {
    printf("[fork_storm] %d forks\n", cycles);
    for(int i=0;i<cycles;i++){
        pid_t p=fork();
        if(p==0)_exit(42);
        else if(p>0){printf("  fork[%d]->%d\n",i,p);usleep(50000);}
        else break;
    }
    int reaped=0;
    while(1){int s;pid_t p=waitpid(-1,&s,WNOHANG);if(p<=0)break;reaped++;printf("  reaped %d\n",p);}
    while(1){int s;pid_t p=wait(&s);if(p<=0)break;reaped++;printf("  reaped %d\n",p);}
    printf("  reaped %d total\n",reaped);
}

static void fault_execve_fail(int cycles) {
    printf("[execve_fail] %d cycles\n", cycles);
    char *env[]={"PATH=/usr/bin",NULL};
    for(int i=0;i<cycles;i++){
        errno=0; char *a1[]={"nonexistent",NULL};
        execve("/tmp/definitely_not_a_real_binary",a1,env);
        printf("  execve(/tmp/nonexistent) = -1 %s\n",strerror(errno));
        errno=0; char *a2[]={"/tmp",NULL};
        execve("/tmp",a2,env);
        printf("  execve(/tmp) = -1 %s\n",strerror(errno));
        char p[128]; snprintf(p,sizeof(p),"/tmp/nex_%d",getpid());
        int f=open(p,O_CREAT|O_WRONLY,0644); if(f>=0){write(f,"#!/bin/sh\necho hi\n",16);close(f);chmod(p,0644);}
        errno=0; char *a3[]={p,NULL};
        execve(p,a3,env);
        printf("  execve(non-exec) = -1 %s\n",strerror(errno));
        unlink(p);
        usleep(200000);
    }
}

static void fault_zombie(int cycles) {
    printf("[zombie] creating %d zombies\n", cycles);
    pid_t *zp=malloc(cycles*sizeof(pid_t));
    int zc=0;
    for(int i=0;i<cycles;i++){
        pid_t p=fork();
        if(p==0)_exit(i);
        else if(p>0){zp[zc++]=p;printf("  zombie[%d]=PID %d\n",i,p);usleep(100000);}
        else break;
    }
    printf("  Created %d zombies, sleeping 10s for inspection...\n",zc);
    sleep(10);
    for(int i=0;i<zc;i++){int s;waitpid(zp[i],&s,0);printf("  reaped %d\n",zp[i]);}
    free(zp);
}

static void run_all(int c){fault_fork_storm(c>10?10:c);printf("---\n");fault_execve_fail(c>5?5:c);printf("---\n");printf("[SKIP] zombie needs 10s, run separately\n");}

int main(int argc,char*argv[]){
    const char*mode="all"; int cycles=8; int loop=0;
    if(argc>1&&strcmp(argv[1],"--loop")==0){loop=1;if(argc>2)mode=argv[2];}
    else if(argc>1){mode=argv[1];if(argc>2)cycles=atoi(argv[2]);}
    if(cycles<1)cycles=1;if(cycles>100000)cycles=100000;
    printf("=== G mode=%s loop=%d cycles=%d\n",mode,loop,cycles);
    if(loop){while(1){
        if(strcmp(mode,"fork_storm")==0)fault_fork_storm(5);
        else if(strcmp(mode,"execve_fail")==0)fault_execve_fail(3);
        else if(strcmp(mode,"zombie")==0){fault_zombie(3);}
        else{fault_fork_storm(3);printf("---\n");fault_execve_fail(2);}
        sleep(3);
    }}
    if(strcmp(mode,"fork_storm")==0)fault_fork_storm(cycles);
    else if(strcmp(mode,"execve_fail")==0)fault_execve_fail(cycles);
    else if(strcmp(mode,"zombie")==0)fault_zombie(cycles);
    else if(strcmp(mode,"all")==0)run_all(cycles);
    else{fprintf(stderr,"Usage: %s [--loop] <mode>\n",argv[0]);return 1;}
    printf("=== G done ===\n"); return 0;
}
