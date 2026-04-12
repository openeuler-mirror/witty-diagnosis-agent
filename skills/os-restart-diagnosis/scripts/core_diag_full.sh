#!/bin/bash
# Core Diagnostic Feature Extraction (V5 Full Dimensions) - Time-Enhanced Edition

show_help() {
    echo "Usage: $0 [OPTION]"
    echo "执行全量信息收集，提取五大维度的特征及时间背景，用于初步场景分类。"
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then show_help; exit 0; fi

echo "=== [REBOOT_DIAG_V5_FEATURES] ==="

# --- 维度 0: 时间上下文 (Time Context) ---
# 逻辑：提供当前与重启的时间基准，用于判定证据的时效性
echo "[V0_Time_Context]"
echo "Current_Time: $(date "+%Y-%m-%d %H:%M:%S")"
echo "System_Boot_Time: $(uptime -s)"
echo "Uptime_Duration: $(uptime -p)"

# --- 维度 1: 外部供电与物理环境 ---
echo -e "\n[V1_Power_Infra]"
if command -v ipmitool &> /dev/null; then
    PSU=$(ipmitool sdr type "Power Supply" 2>/dev/null | grep -v "ns" | awk -F'|' '{print $1,$3}' | tr '\n' ';' || echo "N/A")
    CHASSIS=$(ipmitool chassis status 2>/dev/null | grep "Last Power Event" | cut -d: -f2 || echo "N/A")
    echo "PSU_Status: $PSU"
    echo "Chassis_Power_Event: $CHASSIS"
else
    echo "Power_Data: IPMI_NOT_FOUND"
fi

# --- 维度 2: 人为与计划内操作 ---
echo -e "\n[V2_Human_Action]"
# 增加历史文件修改时间，辅助判定“刚才”是否有人敲过命令
HIST_MODIFY=$(stat -c %y /root/.bash_history 2>/dev/null | cut -d. -f1)
SHUTDOWN_USER=$(ausearch -m system_shutdown -i 2>/dev/null | grep "acct=" | tail -n 1)
[ -z "$SHUTDOWN_USER" ] && SHUTDOWN_USER=$(grep "reboot" /var/log/auth.log 2>/dev/null | tail -n 1 | awk '{print $NF}')
echo "Last_Shutdown_User: ${SHUTDOWN_USER:-Unknown}"
echo "Bash_History_Modify: ${HIST_MODIFY:-N/A}"
echo "Reboot_History: $(last -x reboot shutdown | head -n 2 | tr '\n' ';')"

# --- 维度 3: 内核自保策略 (Kernel Self-Guard) ---
# 判定方法论：资源耗尽触发的强制重启，必须对齐发生时刻
echo -e "\n[V3_Kernel_Self_Guard]"
# 1. 提取上一次启动最后发生的 OOM 时间点
OOM_LOG=$(journalctl --boot=-1 -k --no-pager 2>/dev/null | grep -iE "Out of memory|Killed process" | tail -n 1)
OOM_TIME=$(echo "$OOM_LOG" | awk '{print $1,$2,$3}')
OOM_COUNT=$(journalctl --boot=-1 -k 2>/dev/null | grep -ci "OOM-killer" || echo "0")

# 2. 提取上一次启动最后发生的 Softlockup 时间点
SOFT_LOG=$(journalctl --boot=-1 -k --no-pager 2>/dev/null | grep -i "soft lockup" | tail -n 1)
SOFT_TIME=$(echo "$SOFT_LOG" | awk '{print $1,$2,$3}')
SOFT_COUNT=$(journalctl --boot=-1 -k 2>/dev/null | grep -ci "soft lockup" || echo "0")

echo "OOM_Events_Found: $OOM_COUNT"
echo "Latest_OOM_Time: ${OOM_TIME:-None}"
echo "Softlockup_Events: $SOFT_COUNT"
echo "Latest_Softlockup_Time: ${SOFT_TIME:-None}"
echo "Panic_Policies: oom=$(sysctl -n vm.panic_on_oom), softlockup=$(sysctl -n kernel.softlockup_panic 2>/dev/null || echo 0)"

# --- 维度 4: 内核崩溃与 Panic ---
echo -e "\n[V4_Kernel_Crash]"
if [ -d /var/crash ]; then
    COUNT=$(find /var/crash -maxdepth 1 -type d -name "20*" | wc -l)
    LATEST=$(ls -dt /var/crash/20* 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
    # 物理修改时间，精确到秒
    LATEST_MTIME=$(stat -c %y /var/crash/$LATEST 2>/dev/null | cut -d. -f1)
    
    echo "Kdump_Dir: EXISTS($COUNT files)"
    echo "Latest_Crash_Folder: ${LATEST:-None}"
    echo "Latest_Crash_Mtime: ${LATEST_MTIME:-None}"
else
    echo "Kdump_Dir: MISSING"
fi
PANIC_SIG=$(journalctl --boot=-1 -k --no-pager 2>/dev/null | grep -Ei "panic|oops|invalid opcode" | tail -n 1)
echo "Panic_Signature: ${PANIC_SIG:-Clean}"

# --- 维度 5: 硬件底层异常 ---
echo -e "\n[V5_Hardware_Fault]"
MCE_ERRS=0
[ -d /sys/devices/system/machinecheck ] && MCE_ERRS=$(dmesg | grep -ci "Machine Check Exception" || echo "0")
echo "MCE_Runtime_Errors: $MCE_ERRS"

echo -e "\n=== [END_OF_FEATURES] ==="