# Crash 分析故障排除

分析内核崩溃时常见问题的解决方案。

## 环境问题

### 问题：未找到 crash 命令 (crash command not found)

**症状:**
```bash
-bash: crash: command not found
```

**解决方案:**

1. **安装 crash 工具:**
   ```bash
   # Red Hat/CentOS/Fedora
   sudo yum install crash
   
   # Debian/Ubuntu
   sudo apt-get install crash
   
   # SUSE
   sudo zypper install crash
   ```

2. **验证安装:**
   ```bash
   which crash
   crash --version
   ```

---

### 问题：无法找到 vmlinux (Cannot find vmlinux)

**症状:**
```
crash: cannot find vmlinux
```

**解决方案:**

1. **常见的 vmlinux 位置:**
   ```bash
   # Debug symbols package
   /usr/lib/debug/lib/modules/$(uname -r)/vmlinux
   /usr/lib/debug/boot/vmlinux-$(uname -r)
   
   # Direct kernel build
   /usr/src/linux-$(uname -r)/vmlinux
   /boot/vmlinux-$(uname -r)
   ```

2. **安装调试符号 (debug symbols):**
   ```bash
   # Red Hat/CentOS
   sudo debuginfo-install kernel
   
   # Ubuntu/Debian
   sudo apt-get install linux-image-$(uname -r)-dbg
   
   # Fedora
   sudo dnf debuginfo-install kernel
   ```

3. **查找当前内核的 vmlinux:**
   ```bash
   find /usr -name "vmlinux*$(uname -r)*" 2>/dev/null
   find /boot -name "vmlinux*" 2>/dev/null
   ```

4. **从压缩文件中提取 (如果存在):**
   ```bash
   # Some distributions compress vmlinux
   cd /boot
   sudo gzip -d vmlinux-$(uname -r).gz
   ```

---

### 问题：vmcore 文件丢失或损坏 (vmcore file missing or corrupted)

**症状:**
```
crash: cannot open vmcore
crash: vmcore is corrupted
```

**解决方案:**

1. **常见的 vmcore 位置:**
   ```bash
   /var/crash/
   /var/crash/vmcore
   /var/crash/*/vmcore  # timestamped directories
   ```

2. **检查 kdump 配置:**
   ```bash
   # Verify kdump is enabled
   systemctl status kdump
   
   # Check kdump configuration
   cat /etc/kdump.conf
   ```

3. **确保 kdump 已设置:**
   ```bash
   # Enable kdump
   sudo systemctl enable kdump
   sudo systemctl start kdump
   
   # Verify crashkernel is reserved
   cat /proc/cmdline | grep crashkernel
   ```

4. **验证 vmcore 是否已捕获:**
   ```bash
   ls -lh /var/crash/
   ```

5. **如果 vmcore 被压缩:**
   ```bash
   # makedumpfile creates compressed cores
   cd /var/crash/*/
   # crash can read compressed vmcore directly
   crash /usr/lib/debug/lib/modules/*/vmlinux vmcore
   ```

---

## 符号解析问题 (Symbol Resolution Issues)

### 问题：无调试数据可用 (No debugging data available)

**症状:**
```
crash: no debugging data available
crash: kernel symbols could not be loaded
```

**根本原因:** vmlinux 不包含调试符号

**解决方案:**

1. **验证 vmlinux 是否有符号:**
   ```bash
   file /usr/lib/debug/lib/modules/$(uname -r)/vmlinux
   # Should show: "not stripped"
   
   nm /usr/lib/debug/lib/modules/$(uname -r)/vmlinux | head
   # Should show symbols
   ```

2. **安装 debuginfo 包:**
   ```bash
   # Red Hat family
   sudo yum install kernel-debuginfo-$(uname -r)
   
   # Debian family
   sudo apt-get install linux-image-$(uname -r)-dbgsym
   ```

3. **启用 debuginfo 仓库:**
   ```bash
   # CentOS/RHEL
   sudo yum install yum-utils
   sudo yum-config-manager --enable rhel-*-debug-rpms
   
   # Fedora
   sudo dnf config-manager --enable fedora-debuginfo
   ```

---

### 问题：模块符号未加载 (Module symbols not loaded)

**症状:**
```
crash> mod
MODULE  NAME       SIZE  OBJECT FILE
<module> <name>   <size>  (no symbols)
```

**解决方案:**

1. **安装内核模块 debuginfo:**
   ```bash
   # Red Hat family
   sudo yum install kernel-debuginfo-common-$(uname -m)
   
   # Debian family
   sudo apt-get install linux-modules-$(uname -r)-dbgsym
   ```

2. **在 crash 中重新加载模块符号:**
   ```bash
   crash> mod -S
   ```

3. **手动加载模块符号:**
   ```bash
   crash> mod -s <module_name> /path/to/module.ko
   ```

---

### 问题：版本不匹配 (Version mismatch)

**症状:**
```
WARNING: kernel version mismatch
crash: vmlinux and vmcore do not match!
```

**根本原因:** vmlinux 与 vmcore 来自不同的内核版本

**解决方案:**

1. **查找匹配的 vmlinux:**
   ```bash
   # Check vmcore kernel version
   strings vmcore | grep "Linux version" | head -1
   
   # Find matching vmlinux
   find /usr/lib/debug -name "vmlinux*" -exec file {} \;
   ```

2. **使用特定版本的路径:**
   ```bash
   # Determine exact version from vmcore directory name
   ls /var/crash/
   # Use matching vmlinux
   crash /usr/lib/debug/lib/modules/<version>/vmlinux vmcore
   ```

3. **保留旧内核 debuginfo:**
   ```bash
   # Don't auto-remove old kernels/debuginfo
   # Edit /etc/yum.conf or /etc/dnf/dnf.conf
   installonly_limit=3  # Keep multiple versions
   ```

---

## 分析问题 (Analysis Issues)

### 问题：无法读取地址处的内存 (Cannot read memory at address)

**症状:**
```
crash: cannot access memory at <address>
```

**原因:**
- 无效指针
- 内存损坏
- 虚拟地址未映射

**解决方案:**

1. **验证地址有效性:**
   ```bash
   crash> vm  # Check valid address ranges
   ```

2. **尝试物理地址:**
   ```bash
   crash> rd -p <physical_address>
   ```

3. **检查地址是否曾经有效:**
   ```bash
   crash> kmem -v | grep <address>
   ```

---

### 问题：Crash 挂起或非常慢 (Crash hangs or very slow)

**症状:**
- Crash 工具挂起
- 命令执行时间非常长

**解决方案:**

1. **增加分析用的内存:**
   ```bash
   # crash needs RAM approximately 2x vmcore size
   # If insufficient, use swap
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

2. **使用压缩的 vmcore:**
   ```bash
   # makedumpfile can compress while preserving needed data
   makedumpfile -c -d 31 /proc/vmcore /var/crash/vmcore
   ```

3. **禁用自动加载:**
   ```bash
   # Start crash without immediately loading all symbols
   crash --minimal vmlinux vmcore
   ```

---

### 问题：回溯不完整 (Incomplete backtrace)

**症状:**
```
crash> bt
#0 [address]
#?? [address]
```

**原因:**
- 栈损坏
- 缺少帧指针 (frame pointers)
- 代码优化

**解决方案:**

1. **尝试替代的回溯方法:**
   ```bash
   crash> bt -f  # Full symbols
   crash> bt -t  # Include timestamps
   crash> bt -o  # Old format
   ```

2. **手动遍历栈:**
   ```bash
   crash> rd <stack_address> 100
   # Look for function addresses
   ```

3. **检查栈溢出:**
   ```bash
   crash> bt  # If very deep, likely overflow
   ```

---

## 数据收集问题 (Data Collection Issues)

### 问题：kdump 未捕获 vmcore (kdump not capturing vmcore)

**症状:**
- 系统崩溃但 /var/crash 中没有 vmcore
- kdump 服务似乎在运行但未捕获任何内容

**解决方案:**

1. **验证 crashkernel 内存是否已预留:**
   ```bash
   cat /proc/cmdline | grep crashkernel
   # Should show: crashkernel=auto or crashkernel=256M
   
   dmesg | grep -i crash
   # Should show reserved memory
   ```

2. **将 crashkernel 添加到启动参数:**
   ```bash
   # Edit /etc/default/grub
   GRUB_CMDLINE_LINUX="... crashkernel=256M"
   
   # Regenerate grub config
   sudo grub2-mkconfig -o /boot/grub2/grub.cfg
   # OR for EFI systems
   sudo grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
   
   # Reboot
   sudo reboot
   ```

3. **测试 kdump:**
   ```bash
   echo 1 > /proc/sys/kernel/sysrq
   echo c > /proc/sysrq-trigger  # WARNING: Will crash system!
   ```

4. **检查 kdump 日志:**
   ```bash
   journalctl -u kdump
   cat /var/log/kdump.log
   ```

---

### 问题：没有足够的空间存储 vmcore (Not enough space for vmcore)

**症状:**
```
kdump: saving vmcore failed: No space left on device
```

**解决方案:**

1. **检查可用空间:**
   ```bash
   df -h /var/crash
   ```

2. **配置 makedumpfile 进行压缩:**
   ```bash
   # Edit /etc/kdump.conf
   core_collector makedumpfile -l --message-level 1 -d 31 -c
   
   # Restart kdump
   sudo systemctl restart kdump
   ```

3. **更改 vmcore 目标位置:**
   ```bash
   # Edit /etc/kdump.conf
   path /mnt/largefs/crash
   
   # Restart kdump
   sudo systemctl restart kdump
   ```

4. **网络转储 (dump to remote server):**
   ```bash
   # Edit /etc/kdump.conf
   nfs server.example.com:/export/crash
   
   # Restart kdump
   sudo systemctl restart kdump
   ```

---

## 性能优化 (Performance Optimization)

### 高效分析大型 vmcore 文件

1. **使用选择性页面过滤:**
   ```bash
   makedumpfile -d 31 vmcore vmcore.filtered
   # Filters out:
   # - Cache pages
   # - Free pages
   # - User data
   ```

2. **仅提取所需数据:**
   ```bash
   crash --minimal vmlinux vmcore
   crash> log > kernlog.txt
   crash> bt > backtrace.txt
   crash> ps > processes.txt
   crash> exit
   ```

3. **传输前预过滤:**
   ```bash
   makedumpfile -c --message-level 1 -d 31 \
     /proc/vmcore /var/crash/vmcore.compressed
   ```

---

## Crash 分析环境的最佳实践

1. **设置专用分析系统:**
   - 与生产环境分离
   - 足够的 RAM (预期最大 vmcore 大小的 2 倍)
   - 用于 vmcore 文件的快速存储

2. **维护符号仓库:**
   ```bash
   # Keep debuginfo packages for all deployed kernel versions
   mkdir -p /usr/local/kernel-debuginfo
   # Download and store all versions
   ```

3. **自动化收集:**
   ```bash
   # Script to collect initial analysis
   #!/bin/bash
   crash --minimal vmlinux vmcore << EOF > initial_report.txt
   sys
   log | tail -200
   bt
   ps
   kmem -i
   exit
   EOF
   ```

4. **记录环境文档:**
   - 内核版本
   - 硬件配置
   - 工作负载特征
   - 复现步骤 (如果已知)

---

## 获取帮助 (Getting Help)

当陷入困境时，收集以下信息以获取支持:

1. **Crash 环境:**
   ```bash
   crash --version
   file vmlinux
   file vmcore
   ```

2. **基本分析输出:**
   ```bash
   crash> sys
   crash> log | tail -100
   crash> bt
   ```

3. **系统信息:**
   - 发行版和版本
   - 内核版本
   - 硬件平台
   - 工作负载描述

4. **确切的错误消息:**
   - 截图或复制完整的错误文本
   - 包含上下文 (导致错误的命令)