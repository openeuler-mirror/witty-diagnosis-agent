# 🔴 故障诊断报告 — Thread Stack Leak (PID 1252)

> **报告编号**：RCA-20260604-002  
> **故障级别**：P1（高）  
> **报告时间**：2026-06-04 02:09 UTC  
> **报告生成 Agent**：Baize (witty-diagnosis-agent)  
> **当前状态**：🟢 已恢复（进程已退出，OS 已回收泄漏内存）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 用户态线程栈泄漏 — `fault_thread_leak.py` 每 0.5s 创建新线程永不退出，120 线程累计泄漏 625 MB |
| 影响范围 | PID 1252 — `python3 /test/fault_thread_leak.py 2 5 60`，60s 内创建 120 线程 |
| 故障时段 | 2026-06-04 02:08:00 ~ 02:09:00 UTC（约 60 秒） |
| 根本原因 | `fault_thread_leak.py` 以 2 线程/s 的速度创建线程（参数 `2 5 60` = 2 线程/步 × 5 MB/线程 × 60 s），每个线程分配 5 MB `bytearray` 并通过 `while running: time.sleep(1)` 永久持有，线程栈（~8 MB 映射）及分配的堆内存在线程退出前均不释放，最终创建 120 个线程累计分配 625 MB |
| 是否恢复 | ✅ 已恢复（进程退出后 OS 已回收） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 本报告匹配度 |
|------|------|------|-------------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | ✅ 线程数 45→61（+16/8s），RSS 234→316 MB（+82 MB），增速吻合 2 线程/s |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

**根本原因**：`fault_thread_leak.py` 在 60 秒内以 2 线程/s 的速度创建线程，每个线程分配 5 MB `bytearray` 且在线程函数中使用 `while running: time.sleep(1)` 使线程永不退出。每个线程持有约 5 MB bytearray + 线程栈映射（约 8 MB），导致 RSS 以约 10 MB/s 线性增长，最终创建 120 个线程累计泄漏约 625 MB。

### 事故时间线与故障传导链路

```text
时间                          事件                                           性质          溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-04 02:08:00           fault_thread_leak.py 启动，PID=1252               📈 触发      [thread_leak.log]
  │                           参数: 线程组=2, MB/线程=5, 持续=60s
  ▼
2026-02-04 02:08:20           T0 诊断采集开始: Threads=45, VmRSS=234 MB         ⚠️ 已有 45 线程 [proc_status_base.txt]
  │
  ▼
2026-06-04 02:08:22           Threads=49, VmRSS=255 MB (+21 MB / 2s)           🟡 增长中     [rss_trend.csv]
  │                           新增 4 线程
  ▼
2026-06-04 02:08:24           Threads=53, VmRSS=275 MB (+20 MB / 2s)           🟡 增长中     [rss_trend.csv]
  │                           新增 4 线程
  ▼
2026-06-04 02:08:26           Threads=57, VmRSS=296 MB (+21 MB / 2s)           🟡 增长中     [rss_trend.csv]
  │                           新增 4 线程
  ▼
2026-06-04 02:08:28           Threads=61, VmRSS=316 MB (+20 MB / 2s)           🔴 持续泄漏   [rss_trend.csv]
  │                           新增 4 线程 → 8s 总计 +16 线程 / +82 MB
  ▼
2026-06-04 02:09:00           进程退出前: 创建 120 线程，RSS=625 MB              🔴 峰值       [thread_leak.log]
  │
  ▼
2026-06-04 02:09:00+          进程退出 → OS 回收全部线程内存                     🟢 已恢复
```

### 故障因果链

```text
fault_thread_leak.py 启动 (2 线程/s)
    └─► for 60 秒 { 每 0.5s 创建新线程 }
            └─► threading.Thread(target=thread_worker).start()
                    ├─► thread_worker 内: chunk = bytearray(5 * 1024 * 1024)  # 5 MB
                    └─► while running: time.sleep(1)  # 线程永不退出
                            ├─► 每线程持有 ~5 MB bytearray
                            └─► 每线程拥有 ~8 MB 线程栈映射
                                    └─► 120 线程 × (~5 MB 堆 + ~栈映射) ≈ 625 MB
                                            └─► RSS 以 ~10 MB/s 线性增长
                                                    └─► 进程退出 → OS 回收 ✅
```

---

## 三、排查过程

### 3.1 初始现象

- **观测指标**：PID 1252 Threads 从 45→61 持续增长（8 s 窗口），VmRSS 同步从 234 MB→316 MB
- **诊断脚本**：`bash diagnose_rss_growth.sh -p 1252 -i 2 -c 5`（分支 A3）
- **可疑特征**：线程数与 RSS 严格正相关，pmap 显示大量 10 MB+ [anon] 匿名区域

### 3.2 假设驱动排查

#### 假设 A3：线程栈泄漏 ✅ 确认根因

> 🧪 假设：线程持续创建且永不退出，线程持有的内存永不释放，导致 RSS 线性增长

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 线程数趋势 | `rss_trend.csv` 显示 45→49→53→57→61（+16 线程/8s） | ✅ 增速约 2 线程/s |
| RSS 同步增长 | VmRSS 从 234 MB→316 MB（+82 MB/8s, ~10 MB/s） | ✅ 每线程约 5 MB + 栈映射 |
| pmap 匿名映射 | `pmap_top.txt` 显示多个 10 MB+ [anon] 区域（线程内存） | ✅ 每线程独立分配 |
| VmStk 稳定 | VmStk=132 KB 仅为主线程栈，子线程栈在匿名映射中 | ✅ 符合 Linux 线程栈计账行为 |
| 程序日志 | 日志确认每线程分配 5 MB bytearray 且持续存活 | ✅ 根因证实 |

**✅ 结论**：线程以 2/s 创建，每线程 5 MB bytearray 加线程栈映射，RSS ~10 MB/s 线性增长。

#### 假设 A1：Heap 段泄漏 ❌ 排除

| 检查项 | 操作 | 结论 |
|--------|------|------|
| heap 大小 | `heap_anon.txt` 显示 heap 仅 896 KB | ❌ heap 占 RSS < 0.3% |

#### 假设 A5：共享内存泄漏 ❌ 排除

| 检查项 | 操作 | 结论 |
|--------|------|------|
| /dev/shm | 共享内存段无增长 | ❌ 无共享内存使用 |

### 3.3 排查结论与逻辑树

```text
PID 1252 VmRSS 持续增长 (234→316 MB / 8s)
├─► 假设 A1: Heap 段泄漏         → ❌ 排除 (heap 仅 896KB, <0.3%)
├─► 假设 A5: 共享内存泄漏        → ❌ 排除 (/dev/shm 无增长)
└─► 假设 A3: 线程栈泄漏          → ✅ 确认 (Threads 45→61, VmRSS +82MB)
        └─► 🎯 根因: 线程持续创建 + 每线程 bytearray 永不释放
```

---

## 四、关键证据

| 编号 | 证据 | 文件 | 关键内容 |
|------|------|------|---------|
| 1 | 线程数持续增长 | `rss_trend.csv` | 45→49→53→57→61（8s +16 线程） |
| 2 | RSS 同步增长 | `rss_trend.csv` | 234→255→275→296→316 MB（+82 MB） |
| 3 | heap 极小而排除 A1 | `heap_anon.txt` | heap 仅 896 KB |
| 4 | pmap 显示大量 [anon] | `pmap_top.txt` | 多个 10 MB+ 匿区 |
| 5 | VmStk 稳定 | `proc_status_base.txt` | 132 KB，仅主线程栈 |
| 6 | 程序日志确认 | `thread_leak.log` | 每线程 5 MB bytearray 持续存活 |

---

## 五、反事实验证

| 维度 | 推演结果 | 实际现象 | 是否吻合 |
|------|---------|---------|---------|
| 线程增长速度 | 2 线程/s，8s 内应增 ~16 线程 | 45→61（+16） | ✅ 是 |
| 内存增长率 | 每线程 ~5 MB bytearray + 栈映射 ≈ ~10 MB/s | 平均 ~10 MB/s（82 MB/8s） | ✅ 是 |
| VmStk 表现 | 子线程栈不计入 VmStk | VmStk 稳定 132 KB | ✅ 是 |
| pmap 大区域 | 每线程应有独立匿名映射 | 多个 10 MB+ [anon] 区域 | ✅ 是 |
| 泄漏总量 | 120 线程 × ~5 MB ≈ 600 MB | 日志确认 ~625 MB | ✅ 是 |

**三条全 ✅ → 根因确认 🟢**

---

## 六、排除的替代假设

| 排除假设 | 排除原因 | 依据数据 |
|----------|---------|---------|
| 假设 A1（Heap 段泄漏） | heap 仅 896 KB，未显著增长（占 RSS < 0.3%） | `heap_anon.txt` |
| 假设 A5（共享内存泄漏） | /dev/shm 无使用 | `shm_segments.txt` |

---

## 七、修复建议

### 应急处置
1. **无需操作**：故障进程已退出，所有线程内存已由 OS 回收
2. **生产环境**：若发现进程 Threads 数异常增长，立即 kill 异常进程防止 OOM
3. **临时限制**：
   ```bash
   ulimit -u 100            # 限制每用户最大进程/线程数
   ```
   或通过 systemd/cgroup 设置 `TasksMax=50` 限制容器内线程数

### 永久修复
1. **代码修复**：使用 `threading.Event` 替代 `while running: sleep(1)`，确保线程可被优雅退出
   ```python
   # Before (leak):
   def thread_worker(tid, mb):
       chunk = bytearray(mb * 1024 * 1024)
       while running:
           time.sleep(1)  # 永不退出
   
   # After (fixed):
   def thread_worker(tid, mb, stop_event):
       chunk = bytearray(mb * 1024 * 1024)
       stop_event.wait()  # 等待退出信号，释放后 bytearray 自动回收
   ```
2. **使用线程池**：用 `concurrent.futures.ThreadPoolExecutor` 限制最大并发线程数
   ```python
   with ThreadPoolExecutor(max_workers=10) as executor:
       executor.submit(thread_worker, tid, mb, stop_event)
   ```
3. **资源追踪**：使用 `gc` 模块或 `weakref` 检测未回收的线程对象

### 预防措施
1. 监控线程数变化：定期检查 `/proc/[pid]/status | grep Threads`
2. 设置 systemd/cgroup `TasksMax` 限制每容器最大线程数（如 100）
3. CI 中加入资源泄漏检测（如 pytest-timeout 监控线程泄漏）
4. 代码审查规则：线程必须可被优雅终止，禁止 `while True: sleep()` 模式

---

## 八、附件

- 诊断报告源：`PID_1252_thread_leak/diagnosis_report.md`
- 进程日志：`PID_1252_thread_leak/thread_leak_process.log`
- RSS 趋势数据：`PID_1252_thread_leak/rss_trend_pid1252.csv`
- 进程内存基线：`PID_1252_thread_leak/proc_status_base.txt`
- 内存映射 TOP：`PID_1252_thread_leak/pmap_top.txt`
- 匿名页分析：`PID_1252_thread_leak/heap_anon.txt`
- 诊断采集脚本：`diagnose_rss_growth.sh -p 1252 -i 2 -c 5`
- 技能参考：`memory-leak-diagnosis` → 分支 A3
