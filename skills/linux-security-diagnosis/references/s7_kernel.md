# S7 — 内核与系统漏洞：诊断参考

## 1. 内核版本与CVE快速映射（常见提权漏洞）

| CVE | 漏洞名 | 影响版本 | 类型 |
|-----|--------|---------|------|
| CVE-2016-5195 | Dirty COW | < 4.8.3 | 本地提权 |
| CVE-2019-14287 | sudo bypass | sudo < 1.8.28 | 提权 |
| CVE-2021-3156 | sudo heap overflow | sudo < 1.9.5p2 | 提权 |
| CVE-2021-4034 | PwnKit (pkexec) | 所有版本 | 本地提权 |
| CVE-2022-0847 | Dirty Pipe | 5.8-5.16.10 | 本地写任意文件 |
| CVE-2022-2588 | route4_change | < 5.18.14 | 本地提权 |

```bash
# 检查sudo版本
sudo --version | head -1

# 检查pkexec版本（CVE-2021-4034）
pkexec --version 2>/dev/null
rpm -q polkit 2>/dev/null || dpkg -l policykit-1 2>/dev/null
```

## 2. 内核安全参数最佳实践

```bash
# 查看当前vs推荐值
declare -A PARAMS=(
    ["kernel.randomize_va_space"]="2"        # ASLR全开
    ["kernel.kptr_restrict"]="2"             # 隐藏内核符号
    ["kernel.dmesg_restrict"]="1"            # 普通用户不能读dmesg
    ["kernel.perf_event_paranoid"]="3"       # 禁止普通用户perf
    ["kernel.yama.ptrace_scope"]="1"         # 限制ptrace
    ["fs.suid_dumpable"]="0"                 # SUID程序不产生core dump
    ["fs.protected_hardlinks"]="1"           # 防硬链接攻击
    ["fs.protected_symlinks"]="1"            # 防符号链接攻击
    ["net.ipv4.conf.all.rp_filter"]="1"      # 反向路径过滤
    ["net.ipv4.tcp_syncookies"]="1"          # SYN flood防护
)

for param in "${!PARAMS[@]}"; do
    current=$(sysctl -n "$param" 2>/dev/null)
    expected="${PARAMS[$param]}"
    if [ "$current" != "$expected" ]; then
        echo "⚠️  $param = $current (建议: $expected)"
    else
        echo "✓   $param = $current"
    fi
done
```

## 3. 内核模块安全检查

```bash
# 检查异常内核模块（rootkit检测基础）
# 对比lsmod输出与/sys/module目录
diff <(lsmod | awk 'NR>1{print $1}' | sort) \
     <(ls /sys/module/ | sort) 2>/dev/null | grep "^<" | awk '{print "lsmod有但/sys/module无:", $2}'

# 检查模块来源（是否签名）
for mod in $(lsmod | awk 'NR>1{print $1}'); do
    sig=$(modinfo "$mod" 2>/dev/null | grep "^signer:")
    if [ -z "$sig" ]; then
        echo "未签名模块: $mod"
    fi
done 2>/dev/null | head -20

# 禁止加载新内核模块（运行时保护）
# echo 1 > /proc/sys/kernel/modules_disabled  # 慎用！不可逆
```

## 4. dmesg 错误快速分类

```bash
# 按错误类型统计
dmesg 2>/dev/null | grep -iE "error|warn|oops|BUG|panic" | \
    sed 's/\[.*\] //' | \
    awk '{print $1,$2}' | sort | uniq -c | sort -rn | head -20

# 关注的内核错误类型
# "kernel BUG at"          → 内核bug，可能导致panic
# "Oops: "                 → 内核空指针或非法访问
# "UBSAN: "                → 未定义行为检测（安全相关）
# "stack smashing detected" → 栈溢出保护触发（可能有攻击）
# "audit: possible RCE"   → 远程代码执行尝试
```

## 5. Spectre/Meltdown 状态解读

```bash
# 读取漏洞状态
for vuln in /sys/devices/system/cpu/vulnerabilities/*; do
    name=$(basename $vuln)
    status=$(cat $vuln 2>/dev/null)
    case "$status" in
        *"Not affected"*)    echo "✓  $name: 不受影响" ;;
        *"Mitigation"*)      echo "✓  $name: 已缓解 ($status)" ;;
        *"Vulnerable"*)      echo "⚠️  $name: 存在漏洞！" ;;
        *)                   echo "?  $name: $status" ;;
    esac
done
```
