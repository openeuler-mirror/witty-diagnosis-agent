/**
 * branch_c_library.c - Library Function Tracing Pattern Injection
 * Modes: mallocfreq | callpath | all
 * Prefix --loop to run continuously (for agent attach diagnosis)
 * Compile: gcc -O0 -g -o branch_c_library branch_c_library.c -ldl
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>

static void fault_mallocfreq(int cycles) {
    printf("[mallocfreq] %d cycles\n", cycles);
    for (int i = 0; i < cycles; i++) {
        int n = 500; void **p = malloc(n * sizeof(void*));
        if (!p) continue;
        for (int j = 0; j < n; j++) { size_t s = (rand()%512)+16; p[j]=malloc(s); if(p[j]) memset(p[j],0xCC,s); }
        for (int j = 0; j < n; j+=2) { free(p[j]); p[j]=NULL; }
        for (int j = 0; j < n; j+=2) { size_t s = (rand()%256)+32; p[j]=malloc(s); if(p[j]) memset(p[j],0xDD,s); }
        for (int j = 0; j < n; j++) free(p[j]);
        free(p);
    }
}

static void process_data(const char *d) { printf("  [process_data] %s\n", d ? d : ""); }
static void validate_and_process(const char *d) {
    printf("  [validate_and_process] unexpected wrapper\n");
    process_data(d);
}

static void fault_callpath(int cycles) {
    printf("[callpath] %d cycles\n", cycles);
    for (int i = 0; i < cycles && i < 5; i++) {
        char m[64]; snprintf(m,sizeof(m),"pkt-%d",i);
        validate_and_process(m);
    }
    void *h = dlopen("libc.so.6", RTLD_LAZY | RTLD_NOLOAD);
    if (h) {
        for (int i = 0; i < cycles && i < 5; i++) {
            void *s = dlsym(h,"malloc"); if(s) printf("  dlsym(malloc)=%p\n",s);
            s = dlsym(h,"free"); if(s) printf("  dlsym(free)=%p\n",s);
            usleep(50000);
        }
        dlclose(h);
    }
}

static void run_all(int c) { fault_mallocfreq(c); printf("---\n"); fault_callpath(c); }

int main(int argc,char*argv[]){
    const char*mode="all"; int cycles=5; int loop=0;
    if(argc>1&&strcmp(argv[1],"--loop")==0){loop=1;if(argc>2)mode=argv[2];}
    else if(argc>1){mode=argv[1];if(argc>2)cycles=atoi(argv[2]);}
    if(cycles<1)cycles=1;if(cycles>100000)cycles=100000;
    printf("=== C mode=%s loop=%d cycles=%d\n",mode,loop,cycles);
    if(loop){while(1){
        if(strcmp(mode,"mallocfreq")==0)fault_mallocfreq(3);
        else if(strcmp(mode,"callpath")==0)fault_callpath(3);
        else{fault_mallocfreq(2);printf("---\n");fault_callpath(2);}
        sleep(2);
    }}
    if(strcmp(mode,"mallocfreq")==0)fault_mallocfreq(cycles);
    else if(strcmp(mode,"callpath")==0)fault_callpath(cycles);
    else if(strcmp(mode,"all")==0)run_all(cycles);
    else{fprintf(stderr,"Usage: %s [--loop] <mode>\n",argv[0]);return 1;}
    printf("=== C done ===\n"); return 0;
}
