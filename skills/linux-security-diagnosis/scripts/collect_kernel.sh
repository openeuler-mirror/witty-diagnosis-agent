#!/bin/bash
# collect_kernel.sh — 内核安全与系统漏洞信息采集脚本
# 场景：内核安全模块异常、补丁状态检查、dmesg报错、权限提升漏洞
# 用法：bash collect_kernel.sh

echo "════════════════════════════════════════════"
echo " KERNEL/VULNERABILITY DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════"

# ── 1. 内核版本与基础信息 ────────────────────────
echo ""
echo "── [1] 内核版本与系统信息 ──"
echo "[内核版本]"
uname -r
echo "[完整内核信息]"
uname -a
echo "[OS发行版]"
cat /etc/os-release 2>/dev/null
echo "[已安装内核列表]"
rpm -q kernel 2>/dev/null || dpkg -l linux-image* 2>/dev/null | grep "^ii"

# ── 2. 内核参数安全配置 ─────────────────────────
echo ""
echo "── [2] 内核安全参数 ──"
echo "[关键安全参数]"
sysctl kernel.randomize_va_space \
       kernel.kptr_restrict \
       kernel.dmesg_restrict \
       kernel.perf_event_paranoid \
       kernel.yama.ptrace_scope \
       kernel.unprivileged_bpf_disabled \
       net.ipv4.ip_forward \
       fs.suid_dumpable \
       fs.protected_hardlinks \
       fs.protected_symlinks 2>/dev/null

# ── 3. 内核模块状态 ──────────────────────────────
echo ""
echo "── [3] 内核模块状态 ──"
echo "[已加载模块]"
lsmod 2>/dev/null
echo ""
echo "[模块黑名单配置]"
cat /etc/modprobe.d/*.conf 2>/dev/null | grep -i "blacklist\|install.*-" | head -30
echo ""
echo "[内核模块签名验证]"
cat /sys/module/*/parameters/sig_enforce 2>/dev/null | head -5
grep "module.sig_enforce\|lockdown" /proc/cmdline 2>/dev/null

# ── 4. 内核日志异常检测 ──────────────────────────
echo ""
echo "── [4] 内核日志异常（dmesg）──"
echo "[最近内核错误/警告]"
dmesg --since "24 hours ago" 2>/dev/null | grep -iE "error|warn|oops|panic|BUG|segfault|null pointer|protection fault" | tail -40 \
    || dmesg 2>/dev/null | grep -iE "error|warn|oops|panic|BUG|segfault" | tail -40
echo ""
echo "[内核安全事件（SELinux/capabilities/seccomp）]"
dmesg 2>/dev/null | grep -iE "selinux|capability|seccomp|audit" | tail -20
echo ""
echo "[时间范围: 最近dmesg时间戳]"
dmesg 2>/dev/null | tail -3 | awk '{print $1,$2,$3}'

# ── 5. 漏洞相关补丁状态 ─────────────────────────
echo ""
echo "── [5] 补丁与安全更新状态 ──"
echo "[系统最后更新时间]"
rpm -qa --queryformat '%{INSTALLTIME:date}\n' 2>/dev/null | sort | tail -5 \
    || stat /var/lib/apt/periodic/update-success-stamp 2>/dev/null

echo ""
echo "[待更新安全补丁]"
yum check-update --security 2>/dev/null | head -30 \
    || apt-get upgrade --dry-run 2>/dev/null | grep "^Inst" | grep -i security | head -30 \
    || echo "无法检查（需要yum/apt及网络）"

echo ""
echo "[已知高危CVE内核版本检测]"
python3 - <<'PYEOF'
import subprocess, re

try:
    uname = subprocess.check_output(['uname', '-r'], text=True).strip()
    print(f"当前内核版本: {uname}")

    # 简单版本解析
    match = re.match(r'(\d+)\.(\d+)\.(\d+)', uname)
    if match:
        major, minor, patch = int(match.group(1)), int(match.group(2)), int(match.group(3))
        vulns = []
        # Dirty COW: CVE-2016-5195, kernel < 4.8.3
        if major < 4 or (major == 4 and minor < 8) or (major == 4 and minor == 8 and patch < 3):
            vulns.append("CVE-2016-5195 (Dirty COW) - 本地提权")
        # CVE-2022-0847 Dirty Pipe: 5.8 <= kernel < 5.16.11/5.15.25/5.10.102
        if major == 5 and (8 <= minor <= 16):
            if minor < 16 or (minor == 16 and patch < 11):
                vulns.append("CVE-2022-0847 (Dirty Pipe) - 本地提权")
        # CVE-2021-4034 pkexec: 通用提权（用户态，不依赖内核版本）
        vulns.append("CVE-2021-4034 (PwnKit/pkexec) - 需单独检查pkexec版本")

        if vulns:
            print("⚠️ 潜在已知漏洞（需结合实际补丁确认）:")
            for v in vulns:
                print(f"  - {v}")
        else:
            print("基于版本号的粗略检查: 未匹配到主要已知提权CVE（不代表完全安全）")
except Exception as e:
    print(f"漏洞版本检测跳过: {e}")
PYEOF

# ── 6. Spectre/Meltdown 缓解状态 ─────────────────
echo ""
echo "── [6] CPU漏洞缓解状态 ──"
if [ -d /sys/devices/system/cpu/vulnerabilities ]; then
    for f in /sys/devices/system/cpu/vulnerabilities/*; do
        printf "  %-30s %s\n" "$(basename $f):" "$(cat $f 2>/dev/null)"
    done
else
    echo "无法读取CPU漏洞缓解信息"
fi

# ── 7. 内核完整性检查 ────────────────────────────
echo ""
echo "── [7] 内核完整性与启动参数 ──"
echo "[启动参数]"
cat /proc/cmdline
echo ""
echo "[Secure Boot状态]"
mokutil --sb-state 2>/dev/null || bootctl status 2>/dev/null | grep -i "secure boot" | head -3
echo ""
echo "[内核锁定状态]"
cat /sys/kernel/security/lockdown 2>/dev/null || echo "未配置内核锁定"

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 KERNEL COLLECTOR END"
echo "════════════════════════════════════════════"
