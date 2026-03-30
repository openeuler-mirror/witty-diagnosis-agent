#!/usr/bin/env bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="./fs_diagnosis_report_${TIMESTAMP}.md"
SCENE_CONF="/tmp/fs_diagnosis_scene.conf"
ANALYSIS_FILES=""
ENV_CONF="/tmp/fs_diagnosis_env.conf"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)    OUTPUT_FILE="$2";   shift 2 ;;
        --scene)     SCENE_CONF="$2";    shift 2 ;;
        --analysis)  ANALYSIS_FILES="$2"; shift 2 ;;
        --config)    ENV_CONF="$2";      shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [[ -f "$ENV_CONF" ]]; then source "$ENV_CONF"; fi
LOG_DIR="${LOG_DIR:-.}"

SCENE="UNKNOWN"
CONFIDENCE="UNKNOWN"
if [[ -f "$SCENE_CONF" ]]; then
    source "$SCENE_CONF"
fi

read_log() {
    local log_name="$1"
    local file_path="$LOG_DIR/$log_name"
    if [[ -f "$file_path" ]]; then
        head -100 "$file_path"
    fi
}

{
    cat <<EOF
# 存储诊断报告（磁盘硬件 & 文件系统）

> 生成时间：$(date)
> 日志目录：$LOG_DIR
> 场景标签：$SCENE（置信度：$CONFIDENCE）

---

## 1. Executive Summary（故障摘要）

| 字段 | 内容 |
|------|------|
| 故障场景 | $SCENE（置信度：$CONFIDENCE） |
| 根本原因 | ⚠️ **待填写** — 请在下方 §3 中根据分析结果填写 |
| 修复建议 | ⚠️ **待填写** — 请在下方 §4 中填写 |

---

## 2. Technical Analysis（技术分析）

### 2.1 日志文件概览

EOF

    echo "| 日志目录 | 文件 | 状态 |"
    echo "|----------|------|------|"
    
    for sub_dir in "ibmc_logs" "infocollect_logs" "messages"; do
        DIR_PATH="$LOG_DIR/$sub_dir"
        if [[ -d "$DIR_PATH" ]]; then
            for file in "$DIR_PATH"/*; do
                if [[ -f "$file" ]]; then
                    filename=$(basename "$file")
                    lines=$(wc -l < "$file" 2>/dev/null || echo "0")
                    echo "| $sub_dir/ | $filename | ✅ $lines 行 |"
                fi
            done
        fi
    done
    echo ""

    cat <<'EOF'

### 2.2 故障现象（Symptom）

> 描述用户观察到的故障现象。示例：
> - 文件系统损坏：系统启动时报 EXT4-fs error，无法挂载 /data 分区
> - 挂载失败：systemd 启动时报 Failed to mount /dev/sdb1
> - 空间不足：系统报 No space left on device

**（请根据实际情况填写）**

### 2.3 故障机理（Failure Mechanism）

> 描述故障是如何发生的。示例：
> - 文件系统损坏：异常断电导致正在写入的 inode 元数据未完整落盘，造成文件系统不一致
> - 挂载失败：/etc/fstab 中配置的 UUID 与实际设备 UUID 不匹配
> - 空间不足：日志文件持续增长占满磁盘空间

**（请根据分析结果填写）**

### 2.4 证据链（Evidence Chain）

EOF

    if [[ -n "$ANALYSIS_FILES" ]]; then
        IFS=',' read -ra FILES <<< "$ANALYSIS_FILES"
        idx=1
        for f in "${FILES[@]}"; do
            f_trim=$(echo "$f" | xargs)
            if [[ -f "$f_trim" ]]; then
                echo "#### E${idx}：$(basename "$f_trim")"
                echo '```'
                cat "$f_trim"
                echo '```'
                echo ""
                ((idx++))
            fi
        done
    else
        cat <<'EOF'
请按以下格式填写每条证据：

**E1：[证据标题，如：文件系统损坏证据]**
- 日志文件：messages/messages 或 infocollect_logs/system/dmesg.txt
- 关键信息：`EXT4-fs error (device sdb1): ext4_find_entry: inode #12345: reading directory`
- 结论：EXT4 文件系统 /dev/sdb1 的 inode #12345 目录项损坏

**E2：[证据标题，如：挂载失败证据]**
- 日志文件：messages/messages
- 关键信息：`mount: wrong fs type, bad option, bad superblock on /dev/sdb1`
- 结论：/dev/sdb1 挂载失败，可能是文件系统类型不匹配或超级块损坏

（继续添加 E3、E4... 直到证据链完整）
EOF
    fi

    cat <<'EOF'

---

## 3. Root Cause（根本原因）

> ⚠️ 根因必须包含：具体设备、具体错误类型、具体影响。
> "磁盘坏了" / "文件系统错误" 等笼统描述视为分析不足，禁止作为最终根因。

**Direct Cause（直接原因）：**

```
（示例：/dev/sdb1 的 EXT4 文件系统超级块损坏，导致内核无法识别文件系统，
 systemd 挂载失败，错误信息为 "mount: wrong fs type, bad option, bad superblock"）
```

**Root Cause（根本原因）：**

```
（示例：系统异常断电导致正在写入的文件系统元数据未完整落盘，
 造成超级块损坏。系统未配置 UPS 或未启用文件系统日志保护机制）
```

**5 Whys 分析：**

1. **为什么挂载失败？** →
2. **为什么会发生这种情况？** →
3. **为什么存在这种条件？** →
4. **为什么被允许发生？** →
5. **为什么设计中可能出现这种情况？** →

---

## 4. Recommendations（修复建议）

| 类型 | 建议措施 | 预计完成时间 |
|------|----------|--------------|
| **立即** | （示例：使用 fsck -y /dev/sdb1 修复文件系统） | 立即 |
| **短期** | （示例：检查并更换故障磁盘） | 本周 |
| **中期** | （示例：配置 UPS 或启用文件系统日志保护） | 本月 |
| **长期** | （示例：建立文件系统监控告警机制） | 下季度 |

---

## 5. 风险评估

| 风险类型 | 描述 | 应对措施 |
|----------|------|----------|
| 数据丢失风险 | （评估修复过程中数据丢失的可能性） | （备份策略） |
| 服务中断风险 | （评估修复过程中服务中断时间） | （应急预案） |
| 复发风险 | （评估问题再次发生的可能性） | （预防措施） |

---

## 6. 最终验证清单

在宣布诊断完成之前，确认以下项目：

- [ ] 能向其他工程师解释清楚故障原因
- [ ] 解释能涵盖所有日志中的异常观察结果
- [ ] 确定了故障发生的第一个点
- [ ] 根因具体到设备名、错误类型
- [ ] 提议的修复方案能防止此类问题再次发生
- [ ] 检查了系统中其他设备是否存在相同问题
- [ ] 根因陈述避免了笼统描述
- [ ] 已排除硬件故障因素（检查 SMART、SEL 日志）

**若有任何未勾选项，必须继续深入分析。**

---

## 7. 附录

### 7.1 关键日志片段

EOF

    for sub_dir in "ibmc_logs" "infocollect_logs" "messages"; do
        DIR_PATH="$LOG_DIR/$sub_dir"
        if [[ -d "$DIR_PATH" ]]; then
            for file in "$DIR_PATH"/*; do
                if [[ -f "$file" ]]; then
                    filename=$(basename "$file")
                    if [[ "$filename" =~ \.(txt|log|messages|syslog|dmesg)$ ]] || [[ "$filename" == "messages" ]] || [[ "$filename" == "syslog" ]] || [[ "$filename" == "dmesg" ]]; then
                        echo "#### $sub_dir/$filename（前 50 行）"
                        echo '```'
                        head -50 "$file"
                        echo '```'
                        echo ""
                    fi
                fi
            done
        fi
    done

    cat <<'EOF'

### 7.2 相关命令参考（建议在原系统上执行）

```bash
# 文件系统检查
fsck -y /dev/sdX

# 查看 SMART 信息
smartctl -a /dev/sdX

# 查看磁盘布局
lsblk -f

# 查看挂载状态
mount | column -t

# 查看磁盘使用
df -h
df -i

# 查看文件系统类型
blkid
```

**⚠️ 注意：以上命令仅供参考，需在原故障系统上执行，本 Skill 仅进行离线日志分析。**

---

*报告由 generate_report.sh 自动生成框架，请补充具体分析内容。*
*本报告基于离线日志分析，所有修复建议需在原系统上验证后执行。*
EOF

} > "$OUTPUT_FILE"

echo "================================================================"
echo "✅ 存储诊断报告框架已生成：$OUTPUT_FILE"
echo ""
echo "  下一步："
echo "  1. 用文本编辑器打开报告，填写 §2.2、§2.3、§2.4、§3、§4"
echo "  2. 确保每个结论都有日志数据作为佐证"
echo "  3. 用 §6 最终验证清单检查分析是否足够深入"
echo "================================================================"
