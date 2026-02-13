# OS Crash Analyzer 使用示例

## 快速开始

1. **配置环境：**
   ```bash
   ./scripts/crash_config.sh set \
     --vmlinux /usr/lib/debug/lib/modules/$(uname -r)/vmlinux \
     --vmcore /var/crash/vmcore
   ```

2. **验证配置：**
   ```bash
   ./scripts/crash_config.sh test
   ```

3. **生成快速报告：**
   ```bash
   ./scripts/quick_report.sh
   ```

## 示例工作流

### 场景 1：分析新的崩溃

```bash
# 1. 设置路径
./scripts/crash_config.sh set \
  --vmlinux /usr/lib/debug/vmlinux-5.10.0 \
  --vmcore /var/crash/202402051200/vmcore

# 2. 运行自动化分析
./scripts/crash_wrapper.sh

# 3. 查看日志
less ~/crash_logs/crash_session_*.log
```

### 场景 2：手动调查

```bash
# 使用保存的配置启动 crash
./scripts/crash_config.sh run

# 在 crash 内部：
crash> sys
crash> log | tail -100
crash> bt
crash> kmem -i
```

### 场景 3：分析特定结构

```bash
# 在 crash 内部，获取 task_struct 地址
crash> ps
  PID    PPID  CPU       TASK        ST  %MEM     VSZ    RSS  COMM
  1234   1     2   ffff8800345fb040  RU   1.2  123456  45678  myapp

# 保存到文件
crash> struct task_struct ffff8800345fb040 > /tmp/task.txt
crash> exit

# 使用脚本分析
./scripts/analyze_struct.py /tmp/task.txt --type task
```

## 配置示例

### 多个崩溃转储 (Multiple Crash Dumps)

```bash
# 为不同的 crash 保存配置
export VMLINUX=/usr/lib/debug/vmlinux-5.10.0
export VMCORE_CRASH1=/var/crash/crash1/vmcore
export VMCORE_CRASH2=/var/crash/crash2/vmcore

# 分析第一个 crash
./scripts/crash_config.sh set --vmlinux $VMLINUX --vmcore $VMCORE_CRASH1
./scripts/quick_report.sh

# 分析第二个 crash
./scripts/crash_config.sh set --vmlinux $VMLINUX --vmcore $VMCORE_CRASH2
./scripts/quick_report.sh
```

### 远程崩溃转储分析 (Remote Crash Dump Analysis)

```bash
# 从远程服务器复制 vmcore
scp server:/var/crash/vmcore /tmp/remote_vmcore

# 分析
./scripts/crash_config.sh set \
  --vmlinux /usr/lib/debug/vmlinux-5.10.0 \
  --vmcore /tmp/remote_vmcore
  
./scripts/quick_report.sh
```

## 技巧 (Tips)

1. **保存 crash 输出：** 始终将输出重定向到文件以供稍后查看
   ```bash
   crash> log > /tmp/kernlog.txt
   crash> foreach bt > /tmp/all_backtraces.txt
   ```

2. **使用 grep 过滤模式：** 过滤大量输出
   ```bash
   crash> log | grep -i "error\|panic\|oops"
   ```

3. **比较 crashes：** 如果有多个 vmcore，比较输出
   ```bash
   diff crash1_report.txt crash2_report.txt
   ```

4. **自动化常用检查：** 创建自己的包装脚本
   ```bash
   #!/bin/bash
   # my_analysis.sh
   crash vmlinux vmcore << EOF
   sys
   log | tail -100
   bt
   kmem -i
   ps | grep UN
   exit
   EOF
   ```