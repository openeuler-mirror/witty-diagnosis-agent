
鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽
鈺? [SUMMARY] VMA 缁煎悎淇℃伅鎽樿 鈥?妯″瀷浼樺厛闃呰姝よ妭鈺?鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆
鍒嗘瀽鏃舵: 2026-05-25 ~ 2026-05-25 01:00:00
鐩爣PID:  鏈寚瀹?

###############################################
# S1. 绯荤粺 VMA 鍙傛暟
###############################################

  vm.max_map_count  = 5000
  vm.overcommit_memory = 1
  vm.overcommit_ratio  = 50
  vm.mmap_min_addr     = 65536

  鍏变韩鍐呭瓨闄愬埗:
  kernel.shmall = 18446744073692774399
  kernel.shmmax = 18446744073692774399
  kernel.shmmni = 4096

  ASLR: randomize_va_space = 2

###############################################
# S2. 绯荤粺璧勬簮闄愬埗
###############################################

  RLIMIT_MEMLOCK (褰撳墠 shell):
    soft = unlimited
    hard = unlimited


###############################################
# S3. 鐩爣杩涚▼ VMA 缁熻
###############################################
  鐩爣 PID  鏈寚瀹氭垨杩涚▼宸查€€鍑?
###############################################
# S4. 鍏变韩鍐呭瓨鐘舵€?###############################################


------ Message Queues --------
key        msqid      owner      perms      used-bytes   messages    

------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status      

------ Semaphore Arrays --------
key        semid      owner      perms      nsems     


鍏变韩鍐呭瓨璧勬簮浣跨敤:

------ Messages Status --------
allocated queues = 0
used headers = 0
used space = 0 bytes

------ Shared Memory Status --------
segments allocated 0
pages allocated 0
pages resident  0
pages swapped   0
Swap performance: 0 attempts	 0 successes

------ Semaphore Status --------
used arrays = 0
allocated semaphores = 0


###############################################
# S5. 鍐呭瓨纰庣墖鐘舵€?###############################################

Buddyinfo (楂橀樁椤靛彲鐢ㄦ€?:
  Node 0,: max contiguous order=11 (2048 pages, 8192 KB)
  Node 0,: max contiguous order=11 (2048 pages, 8192 KB)

HugePage 鐘舵€?
HugePages_Total:       0
HugePages_Free:        0
Hugepagesize:       2048 kB

###############################################
# S6. 鍐呮牳鏃ュ織鍏抽敭瀛楁悳绱?###############################################

  鏈壘鍒扮浉鍏冲唴鏍搁敊璇棩蹇?
###############################################
# S7. 绯荤粺鍐呭瓨鍏抽敭鎸囨爣
###############################################

MemTotal:       15986876 kB
MemFree:        14706188 kB
MemAvailable:   14993676 kB
Unevictable:           0 kB
Mlocked:               0 kB
Shmem:              4804 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB

============================================
瀹屾暣鏃ュ織宸蹭繚瀛樺埌: /tmp/vma_diag_20260525_102745
============================================
