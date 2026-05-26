[FAULT] PID=7
[FAULT] RLIMIT_MEMLOCK: soft=4096 KB  hard=4096 KB
[FAULT] 灏濊瘯閿佸畾 4097 KB (瓒呰繃闄愬埗)...
[FAULT] mlock SUCCESS锛堝皾璇曢攣瀹?4097 KB锛?[FAULT] 閿佸畾鍐呭瓨鍐呭楠岃瘉: 0

鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽
鈺? [SUMMARY] 璺緞C mlock 瓒呴檺璇婃柇 鈥?妯″瀷浼樺厛闃呰姝よ妭鈺?鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆
鍒嗘瀽鏃舵: 2026-05-25 ~ 鍏ㄩ噺
鐩爣PID:  鏈寚瀹?
鈹佲攣鈹?S1. memlock 闄愬埗妫€鏌?鈹佲攣鈹?
  褰撳墠 shell RLIMIT_MEMLOCK:
    soft = 4096
    hard = 4096


  systemd 鍏ㄥ眬 DefaultLimitMEMLOCK:
    N/A

  /etc/security/limits.conf memlock 閰嶇疆:

  limits.d memlock 閰嶇疆:

鈹佲攣鈹?S2. 绯荤粺閿佸畾鍐呭瓨鐘舵€?鈹佲攣鈹?
Unevictable:           0 kB
Mlocked:               0 kB

鈹佲攣鈹?S3. 鍐呮牳鏃ュ織 鈥?mlock 鐩稿叧 鈹佲攣鈹?
  鏈壘鍒?mlock 鐩稿叧鍐呮牳鏃ュ織

鈹佲攣鈹?S4. Elasticsearch bootstrap.memory_lock 妫€鏌?鈹佲攣鈹?
  鏈彂鐜?ES 閰嶇疆

============================================
瀹屾暣鏃ュ織宸蹭繚瀛樺埌: /tmp/mmap_mlock_20260525_102435
============================================
