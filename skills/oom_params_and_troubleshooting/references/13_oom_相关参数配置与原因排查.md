# 13 OOM 相关参数配置与原因排查

## OOM 相关概念

OOM（Out Of Memory，简称OOM）指系统内存已用完，在linux系统中，如果内存用完会导致系统无法正常工作，触发系统panic或者OOM killer。

OOM killer是linux内核的一个机制，该机制会监控那些占用内存过大的进程，尤其是短时间内消耗大量内存的进程，在系统的内存即将不够用时结束这些进程从而保障系统的整体可用性。

## OOM 相关参数

### 表13-1 OOM 相关参数

| 参数名称 | 参数说明 | 取值 | 修改方式 |
| :--- | :--- | :--- | :--- |
| `panic_on_oom` | 控制系统遇到OOM时如何反应。当系统遇到OOM的时候，通常会有两种选择：<br>● 触发系统panic，可能会出现频繁宕机的情况。<br>● 选择一个或者几个进程，触发OOM killer，结束选中的进程，释放内存，让系统保持整体可用。<br>可以通过以下命令查看参数取值：<br>`cat /proc/sys/vm/panic_on_oom` 或者 `sysctl -a | grep panic_on_oom` | ● **值为0**：内存不足时，触发OOM killer。<br>● **值为1**：内存不足时，根据具体情况可能发生kernel panic，也可能触发OOM killer。<br>● **值为2**：内存不足时，强制触发系统panic，导致系统重启。<br>**说明**<br>HCE中参数默认值为0。 | 例如将参数设置为0，可用以下两种方式：<br>● **临时配置**，立即生效，但重启后恢复成默认值。<br>`sysctl -w vm.panic_on_oom=0`<br>● **持久化配置**，系统重启仍生效。<br>执行命令 `vim /etc/sysctl.conf`，在该文件中添加一行 `vm.panic_on_oom =0`，再执行命令 `sysctl –p` 或重启系统后生效。 |
| `oom_kill_allocating_task` | 当系统选择触发OOM killer，试图结束某些进程时，`oom_kill_allocating_task` 参数会控制选择哪些进程，有以下两种选择：<br>● 触发OOM的进程。<br>● `oom_score` 得分最高的进程。<br>可以通过以下命令查看参数取值：<br>`cat /proc/sys/vm/oom_kill_allocating_task` 或者 `sysctl -a | grep oom_kill_allocating_task` | ● **值为0**：选择 `oom_score` 得分最高的进程。<br>● **值为非0**：选择触发OOM的进程。<br>**说明**<br>HCE中参数默认值为0。 | 例如将该参数设置成1，可用以下两种方式：<br>● **临时配置**，立即生效，但重启后恢复成默认值。<br>`sysctl -w vm.oom_kill_allocating_task=1`<br>● **持久化配置**，系统重启仍生效。<br>执行命令 `vim /etc/sysctl.conf`，在该文件中添加一行 `vm.oom_kill_allocating_task=1`，再执行命令 `sysctl –p` 或重启系统后生效。 |
| `oom_score` | 指进程的得分，主要由两部分组成：<br>● 系统打分，主要是根据该进程的内存使用情况由系统自动计算。<br>● 用户打分，也就是 `oom_score_adj`，可以自定义。<br>可以通过调整 `oom_score_adj` 的值进而调整一个进程最终的得分。通过以下命令查看参数取值：<br>`cat /proc/进程id/oom_score_adj` | ● **值为0**：不调整 `oom_score`。<br>● **值为负值**：在实际打分值上减去一个折扣。<br>● **值为正值**：增加该进程的 `oom_score`。<br>**说明**<br>`oom_score_adj` 的取值范围是 `-1000～1000`。<br>若设定成 `OOM_SCORE_ADJ_MIN` 或 `-1000`，则表示禁止 OOM killer 结束该进程。 | 例如将进程id为2939的进程 `oom_score_adj` 参数值设置为1000，可用以下命令：<br>`echo 1000 > /proc/2939/oom_score_adj` |
| `oom_dump_tasks` | `oom_dump_tasks` 参数控制OOM发生时是否记录系统的进程信息和 OOM killer 信息。<br>例如dump系统中所有的用户空间进程关于内存方面的一些信息，包括：进程标识信息、该进程使用的内存信息、该进程的页表信息等，这些信息有助于了解出现OOM的原因。<br>可以通过以下命令查看参数取值：<br>`cat /proc/sys/vm/oom_dump_tasks` 或者 `sysctl -a | grep oom_dump_tasks` | ● **值为0**：OOM发生时不会打印相关信息。<br>● **值为非0**：以下三种情况会调用 `dump_tasks` 打印系统中所有task的内存状况。<br>– 由于OOM导致 kernel panic。<br>– 没有找到需要结束的进程。<br>– 找到进程并将其结束的时候。<br>**说明**<br>HCE中参数默认值为1。 | 例如将该参数设置成0，可用以下两种方式：<br>● **临时配置**，立即生效，但重启后恢复成默认值。<br>`sysctl –w vm.oom_dump_tasks=0`<br>● **持久化配置**，系统重启仍生效。<br>执行命令 `vim /etc/sysctl.conf`，在该文件中添加一行 `vm.oom_dump_tasks=0`，再执行命令 `sysctl –p` 或重启系统后生效。 |

## 触发OOM killer 示例

1.  您可以参考表13-1设置HCE系统参数，示例配置如下：

    ```bash
    [root@localhost ~]# cat /proc/sys/vm/panic_on_oom
    0
    [root@localhost ~]# cat /proc/sys/vm/oom_kill_allocating_task
    0
    [root@localhost ~]# cat /proc/sys/vm/oom_dump_tasks
    1
    ```

    - `panic_on_oom=0`，表示在发生系统OOM的时候触发OOM killer。
    - `oom_kill_allocating_task=0`，表示触发OOM killer的时候优先选择结束得分高的进程。
    - `oom_dump_tasks=1`，表示系统发生OOM的时候记录系统的进程信息和 OOM killer 信息。

2.  启动测试进程。
    在系统中同时启动三个相同的测试进程（test、test1、test2），不断申请新的内存，并将test1的 `oom_score_adj` 设置成最大的1000，表示OOM killer优先结束该进程，直至内存耗尽触发系统OOM。

    ```bash
    [root@localhost ~]# ps -ef | grep test
    root        2938    2783  0 19:08 pts/2    00:00:00 ./test
    root        2939    2822  0 19:08 pts/3    00:00:00 ./test1
    root        2940    2918  0 19:08 pts/5    00:00:00 ./test2
    [root@localhost ~]# echo 1000 > /proc/2939/oom_score_adj
    [root@localhost ~]# cat /proc/2939/oom_score_adj
    1000
    ```

3.  查看OOM信息。
    经过一段时间后系统发生OOM并触发OOM killer，同时在 `/var/log/messages` 中打印系统所有进程的内存等信息并结束了test1进程。

## OOM 可能的原因

- **cgroup内存不足**
    使用的内存超出了cgroup中 `memory.limit_in_bytes` 配置的大小，如下示例演示 `memory.limit_in_bytes` 配置为80M，使用memhog模拟分配100M，触发OOM，`/var/log/messages` 部分日志如下，可以从日志中看到memhog所在进程（PID: 2021820）使用了81920kB内存，超出了限制，触发了OOM：

    ```
    warning|kernel[-]|[2919920.414131] memhog invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
    info|kernel[-]|[2919920.414220] memory: usage 81920kB, limit 81920kB, failcnt 30
    err|kernel[-]|[2919920.414272] Memory cgroup out of memory: Killed process 2021820 (memhog) total-vm:105048kB, anon-rss:81884kB, file-rss:1544kB, shmem-rss:0kB, UID:0 pgtables:208kB oom_score_adj:0
    ```

- **父cgroup内存不足**
    在子cgroup中内存仍然足够，但是父cgroup的内存不足，超过了内存限制，如下示例演示父cgroup `memory.limit_in_bytes` 配置为80M，两个子cgroup `memory.limit_in_bytes` 均配置为50M，在两个子cgroup中使用程序循环分配内存，触发OOM，`/var/log/messages` 部分日志如下：

    ```
    warning|kernel[-]|[2925796.529231] main invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
    info|kernel[-]|[2925796.529315] memory: usage 81920kB, limit 81920kB, failcnt 199
    err|kernel[-]|[2925796.529366] Memory cgroup out of memory: Killed process 3238866 (main) total-vm:46792kB, anon-rss:44148kB, file-rss:1264kB, shmem-rss:0kB, UID:0 pgtables:124kB oom_score_adj:0
    ```

- **系统全局内存不足**
    一方面由于OS的空闲内存不足，有程序一直在申请内存，另一方面也无法通过内存回收机制解决内存不足的问题，因此触发了OOM，如下示例演示OS中使用程序循环分配内存，触发OOM，`/var/log/messages` 部分日志如下，可以从日志中看到内存节点Node 0的空闲内存（free）已经低于了内存最低水位线（low），触发了OOM：

    ```
    kernel: [ 1475.869152] main invoked oom: gfp_mask=0x100dca(GFP_HIGHUSER_MOVABLE|__GFP_ZERO), order=0
    kernel: [ 1477.959960] Node 0 DMA32 free:22324kB min:44676kB low:55844kB high:67012kB reserved_highatomic:0KB active_anon:174212kB inactive_anon:1539340kB active_file:0kB inactive_file:64kB unevictable:0kB writepending:0kB present:2080636kB managed:1840628kB mlocked:0kB pagetables:7536kB bounce:0kB free_pcp:0kB local_pcp:0kB free_cma:0kB
    kernel: [ 1477.960064] oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/,mems_allowed=0,global_oom,task_memcg=/system.slice/sshd.service,task=main,pid=1822,uid=0
    kernel: [ 1477.960084] Out of memory: Killed process 1822 (main) total-vm:742748kB, anon-rss:397884kB, file-rss:4kB, shmem-rss:0kB, UID:0 pgtables:1492kB oom_score_adj:1000
    ```

- **内存节点（Node）的内存不足**
    在NUMA存储模式下，OS会存在多个内存节点，如果程序指定使用特定节点的内存，可能在OS内存充足的情况下触发OOM，如下示例演示在两个内存节点的条件下，使用程序循环在Node 1分配内存，导致Node 1内存不足，但是OS内存足够，`/var/log/messages` 部分日志如下：

    ```
    kernel: [  465.863160] main invoked oom: gfp_mask=0x100dca(GFP_HIGHUSER_MOVABLE|__GFP_ZERO), order=0
    kernel: [  465.878286] active_anon:218 inactive_anon:202527 isolated_anon:0#012 active_file:5979 inactive_file:5231 isolated_file:0#012 unevictable:0 dirty:0 writeback:0#012 slab_reclaimable:6164 slab_unreclaimable:9671#012 mapped:4663 shmem:2556 pagetables:846 bounce:0#012 free:226231 free_pcp:36 free_cma:0
    kernel: [  465.878292] Node 1 DMA32 free:34068kB min:32016kB low:40020kB high:48024kB reserved_highatomic:0KB active_anon:188kB inactive_anon:778076kB active_file:20kB inactive_file:40kB unevictable:0kB writepending:0kB present:1048444kB managed:866920kB mlocked:0kB pagetables:2752kB bounce:0kB free_pcp:144kB local_pcp:0kB free_cma:0kB
    kernel: [  933.264779] oom-kill:constraint=CONSTRAINT_MEMORY_POLICY,nodemask=1,cpuset=/,mems_allowed=0-1,global_oom,task_memcg=/system.slice/sshd.service,task=main,pid=1733,uid=0
    kernel: [  465.878438] Out of memory: Killed process 1734 (main) total-vm:239028kB, anon-rss:236300kB, file-rss:200kB, shmem-rss:0kB, UID:0 pgtables:504kB oom_score_adj:1000
    ```

- **其他可能原因**
    OS在内存分配的过程中，如果伙伴系统的内存不足，则系统会通过OOM Killer释放内存，并将内存提供至伙伴系统。

## OOM 问题解决方法

- 从业务进程排查，确认是否有内存泄漏，导致OOM。
- 排查cgroup `limit_in_bytes` 配置是否与业务内存规划匹配，如需要调整，可以手动执行以下命令修改配置参数：
    ```bash
    echo <value> > /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes
    ```
- 如果确认业务需要比较多的内存，建议升级弹性云服务器内存规格。