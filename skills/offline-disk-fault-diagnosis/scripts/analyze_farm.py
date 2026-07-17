#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_farm.py — 希捷 FARM (ATA/SATA) 日志:多盘健康分析(8 类故障部位)

输入:一个目录,其下按 IP(或任意子目录)存放每块盘的 FARM 日志。每块盘有两种来源:
  - <SN>_FARM_<ts>_<ip>_<dev>.json           openSeaChest_LogParser 导出,字段最全(权威)
  - <SN>_FARM_disktool_<ts>_<ip>_<dev>.txt    华为 disktool 导出,只有关键字段(约 40%)
脚本默认 JSON 优先、TXT 兜底;同盘两者都在时只用 JSON,并在报告中标注数据源与覆盖度。

与时间序列型的 SM2 日志不同:FARM 日志是【单帧快照】(只有一份 copy 0),没有 poh 趋势可读。
因此本脚本不做"旧->新方向"判定,改用三条研判轴:
  (a) 绝对阈值          —— 坏道/不可恢复读/温度/CTO 等是否越界
  (b) 种群相对(逐头)   —— 同盘各磁头横向互比,挑离群头(沿用 SM2 方法论)
  (c) 整盘<->逐头对账   —— 用逐头数定位到具体磁头;逐头全 0 而整盘很大时,标注"无法定位到头"
活跃度近似:Reallocated Candidate Sectors > 0 视为"退化进行中"(有坏道待处理),否则"暂稳"。

8 类故障部位(映射与覆盖度见 references/farm_field_reference.md):
  1 盘片表面/坏扇区   2 磁头/读写通道/ECC   3 机械/马达/伺服   4 接口/传输
  5 温度/环境/振动    6 寿命/工况           7 固件/服务区      8 SSD(本类HDD不适用)

冷存储故障根因定界(R 码)层 —— 本技能(offline-disk-fault-diagnosis)专有:
  在 8 类"部位层"之上,按用户定义《故障根因分类表》(references/root_cause_rules.md)
  执行 R1-R16 根因定界的 FARM 侧量化判定:
    R1 磁头信号退化 / R2 磁头飞行异常 / R3 盘片介质退化 / R4 振动致伤 /
    R5a 固件异常(FARM 可定界) / R6 机械电机退化 / R7 链路故障(FARM 全健康提示)
  核心量化口径:DOS WR 倍率(refresh/threshold, 50×/200×/1000× 分级)、梯度比(10×/3×)、
  VO(30/100/500)、Shock(1K/10K/50K)、FAFH 绝对偏离(200/500)、Depop 占比分级(25%/50%)。
  脚本只给出【FARM 侧候选 R 码 + 判定依据 + OS 侧待交叉验证清单】;
  最终 R 码须由分析人结合 OS/iBMC 日志(SMART/dmesg/messages)交叉验证后闭环。

用法:
  python3 analyze_farm.py <目录>                 # 默认 json 优先, txt 兜底
  python3 analyze_farm.py <目录> --source json   # 只用 json(无 json 的盘跳过)
  python3 analyze_farm.py <目录> --source txt    # 强制只用 txt(测试降级路径)
  python3 analyze_farm.py <目录> --json          # 追加机器可读 JSON
"""

import argparse
import json
import os
import re
import statistics
import sys

# ---- 已知标记/常量值(见 references/farm_field_reference.md)----
MARK_FFFF = 65535   # 0xFFFF 满量程/溢出:磁头开路或传感器饱和(故障)
MARK_DEAD = 57005   # 0xDEAD 固件"未校准/无效数据"

# ---- 阈值(集中在此,换机型可调)----
TEMP_WARN, TEMP_CRIT = 50.0, 60.0       # FARM 给出 Specified Max=60℃,故 50 关注 / 60 临界
SHOCK_WARN = 100000                     # Over-Limit Shock 事件累计(经验关注线)
HUMID_WARN = 80.0
CTO_WARN = 1                            # 命令超时累计 >=1 即关注(单帧无趋势,保守取关注)
OUTLIER_HI = 2.00          # 种群相对:abs(delta) > 中位 × 2.0 视为偏高离群(FAFH 飞高偏移用)
HEAD_REALLOC_WARN = 1      # 逐头重分配 >=1 即记为坏道
VELOBS_WARN = 200                       # 逐头 Velocity Observer > 200 视为该头组件退化
DOS_THRESH_MULT = 1000                  # 逐头 DOS Write Refresh Count > 1000×该头 Threshold 视为组件退化
HEAD_DEGRADE_RATIO_CRIT = 0.5           # 组件退化磁头占比 >= 该值 -> 终态判"损坏"(覆盖其它类别结论)

# ---- 冷存储故障根因定界(R 码)阈值 —— 源自用户定义《故障根因分类表》----
#      (完整规则、仲裁逻辑与 OS 侧交叉验证标准见 references/root_cause_rules.md)
DOSWR_HEALTHY = 50.0     # DOS WR 倍率(= DOS Write Refresh Count / Threshold) < 50× = 健康
DOSWR_ALERT = 200.0      # 50×-200× 正常老化(个别磁头,持续监控);> 200× 退化告警(Depop 候选)
DOSWR_SEVERE = 1000.0    # > 1000× 严重退化(强烈建议 Depop)
VO_NORMAL = 30           # 所有磁头 VO <= 30 → 正常(排除 R2);30-100 监控区
VO_ABN = 100             # VO > 100 → 飞行异常(R2 判据;亦是 R4 异常头口径之一)
VO_HEAVY = 500           # VO > 500 → 重度 R2
FAFH_ABN = 200.0         # |FAFH clearance delta| > 200(任一区域) → 飞高偏离(R2)
FAFH_HEAVY = 500.0       # |delta| > 500 → 重度
GRAD_R1 = 10.0           # 梯度比 = 最差磁头DOS WR倍率/最佳磁头DOS WR倍率;>10× 显著梯度 → R1 特征
GRAD_R4 = 3.0            # 梯度比 < 3× 且异常磁头占比 > 50% → 无梯度 → R4 特征
ABN_RATIO_R4 = 0.5       # R4 异常磁头占比门限(异常 = DOS WR倍率>200× 或 VO>100)
SHOCK_R4 = 10000         # Over-Limit Shock > 10,000 → 振动异常(R4 判据之一)
SHOCK_EXTREME = 50000    # > 50,000 → 极端振动(确认 R4)
SHOCK_CLEAR = 1000       # < 1,000 → 排除 R4(亦是 R7"FARM 全健康"的盘体口径之一)
H2SAT_ITER_ABN = 6       # H2SAT 收敛迭代次数 > 6 → 读侧退化
H2SAT_BER_ABN = 300.0    # BER > 300 → 读侧退化(字段常缺失,缺失时静默跳过)
PENDING_EARLY_R3 = 500   # Realloc=0 时 Candidate(Pending) > 500 → 早期介质退化(R3 候选积累型)
REALLOC_SPREAD_R3 = 0.25 # Realloc 跨 > 25% 磁头分布 → R3 特征;集中 <= 25% 磁头 → R1 特征
DEPOP_OK = 0.25          # 异常磁头占比 <= 25% → Depop 可行
DEPOP_MARGINAL = 0.50    # 25% < 占比 <= 50% → 边际(需评估剩余容量);> 50% → 不推荐,换盘

SEV_LABEL = {0: "健康", 1: "关注", 2: "退化", 3: "失效"}
COV_FULL, COV_PART, COV_NA = "可分析(≥标准SMART)", "部分可分析", "不适用"


# --------------------------------------------------------------------------- utils
def to_float(x, d=None):
    if x is None:
        return d
    if isinstance(x, str):
        x = x.strip()
        if x == "":
            return d
        if x.lower().startswith("0x"):
            try:
                return float(int(x, 16))
            except ValueError:
                return d
    try:
        return float(x)
    except (TypeError, ValueError):
        return d


def to_int(x, d=None):
    f = to_float(x)
    return int(f) if f is not None else d


def hex_to_int(x):
    """十六进制字符串 -> int;非十六进制返回 None。"""
    if isinstance(x, str) and x.strip().lower().startswith("0x"):
        try:
            return int(x.strip(), 16)
        except ValueError:
            return None
    return None


def median(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


# --------------------------------------------------------------------------- discover & pair
# 两种在实际现场观察到的文件名格式,顺序即匹配优先级(先到先得,命中第一个就不再试第二个):
#   A) 标准格式(采集脚本 step8_batch_collect_seagate_farm 系列产出,现场多数目录用这种):
#      <SN>_FARM_[disktool_]<ts>_<ip>_<dev>.{json,txt}
#   B) 时间戳前置格式(个别目录/工具产出,disktool 标记挪到文件名末尾而非紧跟 FARM_):
#      <ts>_<SN>_FARM_<ip>_<dev>[_disktool].{json,txt}
FARM_NAME_PATTERNS = [
    re.compile(
        r"(?P<sn>[^_/\\]+)_FARM_(?:(?P<disktool>disktool)_)?"
        r"(?P<ts>\d{8}T\d{6})_(?P<ip>[\d.]+)_(?P<dev>[^.]+)\.(?P<ext>json|txt)$",
        re.I),
    re.compile(
        r"(?P<ts>\d{8}T\d{6})_(?P<sn>[^_/\\]+)_FARM_(?P<ip>[\d.]+)_"
        r"(?P<dev>[^.]+?)(?:_(?P<disktool>disktool))?\.(?P<ext>json|txt)$",
        re.I),
]


def _match_farm_name(name):
    for pat in FARM_NAME_PATTERNS:
        m = pat.match(name)
        if m:
            return m
    return None


def discover_disks(root, source):
    """扫描 root,按目录(IP)+SN 分盘,选定每盘的数据源文件。
    返回 list[dict(sn, dirpath, json, txt, use, ip)]。use ∈ {'json','txt'}。
    文件名依次尝试 FARM_NAME_PATTERNS 中的每种格式(见其注释),兼容现场不同采集工具的命名差异。"""
    # group by (dirpath, sn)
    groups = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            m = _match_farm_name(name)
            if not m:
                continue
            key = (dirpath, m.group("sn"))
            g = groups.setdefault(key, {"sn": m.group("sn"), "dirpath": dirpath,
                                        "ip": m.group("ip"), "json": None, "txt": None})
            full = os.path.join(dirpath, name)
            if m.group("ext").lower() == "json":
                g["json"] = full
            elif m.group("disktool"):           # disktool TXT = 华为关键信息
                g["txt"] = full
            elif g["txt"] is None:              # 其它 txt 作为后备
                g["txt"] = full
    disks = []
    for g in groups.values():
        if source == "json":
            use = "json" if g["json"] else None
        elif source == "txt":
            use = "txt" if g["txt"] else None
        else:  # auto: json 优先
            use = "json" if g["json"] else ("txt" if g["txt"] else None)
        if use:
            g["use"] = use
            disks.append(g)
    return disks


# --------------------------------------------------------------------------- loaders -> common model
def _heads_from_flat(section, n_heads):
    """把 'Xxx by Head N' / 'Xxx for Head N' 扁平字段反聚合成 {metric: [v0..vN-1]}。"""
    out = {}
    rx = re.compile(r"^(?P<metric>.+?)\s+(?:by|for)\s+Head\s+(?P<idx>\d+)\s*$", re.I)
    for k, v in section.items():
        m = rx.match(k)
        if not m:
            continue
        metric = m.group("metric").strip()
        idx = int(m.group("idx"))
        arr = out.setdefault(metric, [None] * max(n_heads, idx + 1))
        if idx >= len(arr):
            arr.extend([None] * (idx + 1 - len(arr)))
        arr[idx] = v
    return out


def _hf_pick(hf, n_heads, *names):
    """在反聚合结果 hf 中按多个候选字段名(原始拼写可能不同)依次尝试取逐头数组,取第一个命中的。"""
    for name in names:
        arr = hf.get(name)
        if arr and any(v is not None for v in arr):
            return arr
    return [None] * n_heads


def load_json(path):
    """openSeaChest JSON -> 通用模型 dict。"""
    with open(path, "r", encoding="utf-8-sig") as f:
        d = json.load(f)

    def sect(name):
        return d.get(name + " From Farm Log copy 0") or d.get(name + " Log From Farm Log copy 0") or {}

    di = d.get("Drive Information From Farm Log copy 0", {})
    wl = d.get("Work Load From Farm Log copy 0", {})
    ei = d.get("Error Information Log From Farm Log copy 0", {})
    env = d.get("Environment Information From Farm Log copy 0", {})
    rel = d.get("Reliability Information From Farm Log copy 0", {})
    hi = d.get("Head Information From Farm Log copy 0", {})
    n = to_int(di.get("Number of heads")) or 0

    hf = _heads_from_flat(hi, n)
    # per-head Cum Lifetime Unrecoverable (sub-dicts in Error log)
    cum_uniq = [None] * n
    cum_rep = [None] * n
    for i in range(n):
        sub = ei.get("Cum Lifetime Unrecoverable by head %d" % i)
        if isinstance(sub, dict):
            cum_uniq[i] = to_int(sub.get("Cum Lifetime Unrecoverable Read Unique"))
            cum_rep[i] = to_int(sub.get("Cum Lifetime Unrecoverable Read Repeating"))

    m = {
        "source": "JSON", "coverage": COV_FULL,
        "sn": di.get("Serial Number"), "model": di.get("Model Number"),
        "firmware": di.get("Firmware Rev"), "interface": di.get("Device Interface"),
        "heads": n, "rec_type": di.get("Drive Recording Type"),
        "depopped": di.get("Has Drive been Depopped"),
        "depop_mask": to_int(di.get("Depopulation Head Mask")),
        "poh": to_int(di.get("Power on Hour")),
        "power_cycle": to_int(di.get("Power Cycle count")),
        "hw_reset": to_int(di.get("Hardware Reset count")),
        "head_load": to_int(di.get("Head Load Events")),
        "spin_up_time": to_int(di.get("Spin-up Time")),
        "workload_pct": to_int(wl.get("Rated Workload Percentaged")),
        "read_cmds": to_int(wl.get("Total Number of Read Commands")),
        "write_cmds": to_int(wl.get("Total Number of Write Commands")),
        "lba_written": to_int(wl.get("Logical Sectors Written")),
        "lba_read": to_int(wl.get("Logical Sectors Read")),
        # error
        "unrec_read": to_int(ei.get("Unrecoverable Read Errors")),
        "unrec_write": to_int(ei.get("Unrecoverable Write Errors")),
        "realloc": to_int(ei.get("Number of Reallocated Sectors")),
        "realloc_cand": to_int(ei.get("Number of Reallocated Candidate Sectors")),
        "read_recov": to_int(ei.get("Number of Read Recovery Attempts")),
        "mech_start_fail": to_int(ei.get("Number of Mechanical Start Failures")),
        "asr_events": to_int(ei.get("Number of ASR Events")),
        "crc_err": to_int(ei.get("Number of Interface CRC Errors")),
        "spin_retry": to_int(ei.get("Spin Retry Count")),
        "ioedc": to_int(ei.get("Number of IOEDC Errors (Raw)")),
        "cto_total": to_int(ei.get("CTO Count Total")),
        "cto_5s": to_int(ei.get("CTO Count Over 5s")),
        "cto_75s": to_int(ei.get("CTO Count Over 7.5s")),
        "flash_led": to_int(ei.get("Total Flash LED (Assert) Events")),
        "uncorrectable": to_int(ei.get("Uncorrectable errors")),
        # environment
        "temp_cur": to_float(env.get("Current Temperature (Celsius)")),
        "temp_max": to_float(env.get("Highest Temperature")),
        "temp_min": to_float(env.get("Lowest Temperature")),
        "time_over_temp": to_int(env.get("Time In Over Temperature")),
        "spec_max_temp": to_float(env.get("Specified Max Operating Temperature")),
        "shock": to_int(env.get("Over-Limit Shock Events Count(Raw)")),
        "hfw": to_int(env.get("High Fly Write Count (Raw)")),
        "humidity": to_float(env.get("Current Relative Humidity")),
        "motor_power": to_float(env.get("Current Motor Power")),
        # reliability
        "helium_trip": to_int(rel.get("Helium Pressure Threshold Tripped")),
        "servo_status": to_int(rel.get("Servo Status")),
        "lbas_by_isp": to_int(rel.get("Number of LBAs Corrected by ISP")),
        "rv_mean": to_int(rel.get("RV Absolute Mean")),
        "rv_max": to_int(rel.get("Max RV Absolute Mean")),
        "high_prio_unload": to_int(rel.get("High Priority Unload Events")),
        # per-head arrays (None where absent)
        "h_realloc": [to_int(x) for x in hf.get("Number of Reallocated Sectors", [None] * n)],
        "h_cand": [to_int(x) for x in hf.get("Number of Reallocation Candidate Sectors", [None] * n)],
        "h_cum_uniq": cum_uniq,
        "h_cum_rep": cum_rep,
        "h_mrr": [to_int(x) for x in hf.get("MR Head Resistance from", [None] * n)],
        "h_mrr2": [to_int(x) for x in hf.get("Second MR Head Resistance", [None] * n)],
        "h_fafh_od": [to_float(x) for x in hf.get("Fly height clearance delta outer", [None] * n)],
        "h_fafh_md": [to_float(x) for x in hf.get("Fly height clearance delta middle", [None] * n)],
        "h_fafh_id": [to_float(x) for x in hf.get("Fly height clearance delta inner", [None] * n)],
        "h_h2sat_amp": [to_int(x) for x in hf.get("Current H2SAT amplitude", [None] * n)],
        # H2SAT 读侧退化判定用逐头字段(R 码定界;部分固件不填充,缺失时静默降级)
        "h_h2sat_iter": [to_float(x) for x in _hf_pick(
            hf, n, "Current H2SAT iterations to converge", "Current H2SAT iterations")],
        "h_h2sat_asym": [to_float(x) for x in _hf_pick(hf, n, "Current H2SAT asymmetry")],
        "h_h2sat_cw": [to_float(x) for x in _hf_pick(
            hf, n, "Current H2SAT percentage of codewords at iteration level",
            "Current H2SAT percent of codewords", "Current H2SAT bits in error")],
        "h_ber": [to_float(x) for x in _hf_pick(hf, n, "Bit Error Rate", "Bit Error Rate of Zone 0")],
        "h_disc_slip": [to_float(x) for x in _hf_pick(hf, n, "Disc Slip in micro-inches", "Disc Slip")],
        "h_dos_refresh": [to_int(x) for x in hf.get("DOS Write Refresh Count", [None] * n)],
        "h_dos_thresh": [to_int(x) for x in _hf_pick(
            hf, n, "DOS Write Count Threshold", "DOS Write Refresh Count Threshold", "DOS Write Threshold")],
        "h_tmd": [to_int(x) for x in hf.get("Number of TMD", [None] * n)],
        "h_velobs": [to_int(x) for x in hf.get("Velocity Observer", [None] * n)],
    }
    return m


def load_txt(path):
    """华为 disktool TXT -> 通用模型 dict(字段子集)。"""
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    lines = text.splitlines()
    scalar = {}            # "#Key" -> value
    headblk = {}           # block-title -> [v0, v1, ...]
    cur_block = None
    for ln in lines:
        if ln.startswith("==="):
            cur_block = None
            continue
        mh = re.match(r"^\s*head(\d+)\s*:\s*(.+?)\s*$", ln)
        if mh and cur_block:
            idx = int(mh.group(1))
            arr = headblk.setdefault(cur_block, [])
            while len(arr) <= idx:
                arr.append(None)
            arr[idx] = mh.group(2).strip()
            continue
        ms = re.match(r"^#\s*(.+?)\s*:\s*(.*?)\s*$", ln)
        if ms:
            key, val = ms.group(1).strip(), ms.group(2).strip()
            scalar[key] = val
            # a "#Title by Head" line opens a per-head block
            cur_block = key if re.search(r"by (Drive )?Head", key) else None
            continue
        # a "#Title" with NO colon/value is always a block header in disktool TXT; the
        # following "headN : v" rows attach to it. Some real blocks (如 "#DOS Write Refresh
        # Count") don't spell out "by Head", so open on any value-less #Title, not just those.
        mt = re.match(r"^#\s*(.+?)\s*$", ln)
        if mt:
            cur_block = mt.group(1).strip()

    def sc(key, default=None):
        for k in scalar:
            if k == key:
                return scalar[k]
        return default

    def find(substr):
        for k, v in scalar.items():
            if substr.lower() in k.lower():
                return v
        return None

    def harr(substr):
        for k, v in headblk.items():
            if substr.lower() in k.lower():
                return v
        return None

    n = to_int(find("Number of Heads")) or 0
    humid_raw = to_float(find("Current Relative Humidity"))  # in .1%
    m = {
        "source": "TXT", "coverage": "部分(约40%字段,无逐头通道/H2SAT/逐头不可恢复读)",
        "sn": find("Serial Number"), "model": None,
        "firmware": (find("Firmware Revision") or "").strip() or None,
        "interface": find("Device Interface"),
        "heads": n, "rec_type": None, "depopped": None, "depop_mask": None,
        "poh": to_int(find("Power-on Hours")),
        "power_cycle": to_int(find("Power Cycle Count")),
        "hw_reset": to_int(find("Hardware Reset Count")),
        "head_load": to_int(find("Head Load Events")),
        "spin_up_time": to_int(find("Spin-Up time")),
        "workload_pct": to_int(find("Rated Workload Percentage")),
        "read_cmds": to_int(find("Total Number of Read Commands")),
        "write_cmds": to_int(find("Total Number of Write Commands")),
        "lba_written": to_int(find("Logical Sectors Written")),
        "lba_read": to_int(find("Logical Sectors Read")),
        "unrec_read": to_int(find("Number of Unrecoverable Read Errors")),
        "unrec_write": to_int(find("Number of Unrecoverable Write Errors")),
        "realloc": to_int(find("Number of Reallocated Sectors")),
        "realloc_cand": to_int(find("Number of Reallocated Candidate Sectors")),
        "read_recov": to_int(find("Number of Read Recovery Attempts")),
        "mech_start_fail": to_int(find("Mechanical Start Failures")),
        "asr_events": to_int(find("Number of ASR Events")),
        "crc_err": to_int(find("Interface CRC Errors")),
        "spin_retry": to_int(find("Spin Retry Count (Most recent")),
        "ioedc": to_int(find("IOEDC Errors")),
        "cto_total": to_int(find("CTO Count Total")),
        "cto_5s": to_int(find("CTO Count Over 5s")),
        "cto_75s": to_int(find("CTO Count Over 7.5s")),
        "flash_led": to_int(find("Flash LED (Assert) Events")),
        "uncorrectable": None,
        "temp_cur": to_float(find("Current Temperature")),
        "temp_max": to_float(find("Highest Temperature")),
        "temp_min": to_float(find("Lowest Temperature")),
        "time_over_temp": to_int(find("Time In Over Temperature")),
        "spec_max_temp": to_float(find("Specified Max Operating Temperature")),
        "shock": to_int(find("Over-Limit Shock Events")),
        "hfw": to_int(find("High Fly Write Count")),
        "humidity": (humid_raw / 10.0) if humid_raw is not None else None,
        "motor_power": to_float(find("Current Motor Power")),
        "helium_trip": None, "servo_status": to_int(find("Servo Status")),
        "lbas_by_isp": to_int(find("LBAs Corrected by ISP")),
        "rv_mean": None, "rv_max": None,
        "high_prio_unload": to_int(find("High Priority Unload")),
        # per-head: TXT has realloc? usually NOT per-head -> all None
        "h_realloc": [None] * n, "h_cand": [None] * n,
        "h_cum_uniq": [None] * n, "h_cum_rep": [None] * n,
        "h_mrr": [to_int(x) for x in (harr("MR Head Resistance") or [None] * n)],
        "h_mrr2": [None] * n,
        "h_fafh_od": [to_float(x) for x in (harr("Diameter 0-Outer") or [None] * n)],
        "h_fafh_md": [to_float(x) for x in (harr("Diameter 2-Middle") or [None] * n)],
        "h_fafh_id": [to_float(x) for x in (harr("Diameter 1-Inner") or [None] * n)],
        "h_h2sat_amp": [None] * n,
        # TXT 不含 H2SAT/BER/Disc Slip 逐头字段 → R 码读侧判据降级(建议索取 json)
        "h_h2sat_iter": [None] * n, "h_h2sat_asym": [None] * n, "h_h2sat_cw": [None] * n,
        "h_ber": [None] * n, "h_disc_slip": [None] * n,
        "h_dos_refresh": [to_int(x) for x in (harr("DOS Write Refresh") or [None] * n)],
        "h_dos_thresh": [to_int(x) for x in (
            harr("DOS Write Count Threshold") or harr("DOS Write Refresh Count Threshold")
            or harr("DOS Write Threshold") or [None] * n)],
        "h_tmd": [to_int(x) for x in (harr("Number of TMD") or [None] * n)],
        "h_velobs": [to_int(x) for x in (harr("Velocity Observer over") or [None] * n)],
    }
    return m


# --------------------------------------------------------------------------- per-head outliers
def fafh_outliers(m):
    """FAFH 飞高 clearance delta:取每头 OD/MD/ID 的最大绝对偏移,做种群相对离群。"""
    n = m["heads"]
    pairs = []
    for i in range(n):
        vals = [abs(v) for v in (m["h_fafh_od"][i], m["h_fafh_md"][i], m["h_fafh_id"][i]) if v is not None]
        pairs.append((i, max(vals) if vals else None))
    present = [v for _, v in pairs if v is not None]
    if len(present) < 3:
        return set(), None
    med = statistics.median(present)
    out = {i for i, v in pairs if v is not None and med and v > med * OUTLIER_HI}
    return out, med


def component_degraded_heads(m):
    """磁头/组件退化判据(用户规则,归入类3 机械/马达/伺服):
    逐头满足以下任一即判该头组件退化 —— (a) Velocity Observer > VELOBS_WARN;
    (b) 该头 DOS Write Count Threshold 非0,且 DOS Write Refresh Count > DOS_THRESH_MULT × Threshold。
    返回退化磁头下标列表;磁盘级占比由调用方(classify)按此结果 ÷ 总头数计算。"""
    n = m["heads"]
    bad = []
    for i in range(n):
        v = m["h_velobs"][i]
        velobs_bad = v is not None and v > VELOBS_WARN
        t, r = m["h_dos_thresh"][i], m["h_dos_refresh"][i]
        dos_bad = t not in (None, 0) and r is not None and r > DOS_THRESH_MULT * t
        if velobs_bad or dos_bad:
            bad.append(i)
    return bad


# --------------------------------------------------------------------------- 冷存储根因定界(R 码)
# 各 R 码的 OS 侧待交叉验证清单(源自《故障根因分类表》"OS侧交叉验证"标准;
# 脚本只看 FARM,这些项须由分析人在 messages/dmesg/SMART/hiraidadm 中核验后闭环 R 码)
RCODE_OS_CHECKS = {
    "R1": ["SMART Attr5/187/197/198 Raw:从0变为≥1 → 告警;两次采集间增加≥1 → 持续退化",
           "dmesg:\"medium error\"/\"I/O error\" 是否集中在特定 LBA 范围(R1 特征:集中)",
           "messages:晚期可能记录 \"XFS shutdown\"",
           "SMART Attr195:若固件为 SN02 且 Normalized VALUE≤011,须做 R1 vs R5c 仲裁——以 FARM DOS WR 是否同步异常为准(DOS WR<50× → R5c 固件统计Bug;>200× → R1 真实退化)"],
    "R2": ["SMART Attr194 G-Sense Error Rate:较基线增长 → 伴随振动",
           "dmesg:\"read retry\" 日志出现",
           "iostat:间歇性高延迟(svctm 波动大)",
           "冷存储 L/P 斜坡磨损:SMART Attr192/193 > 同批次中位数×2 → L/P 磨损/频次预警"],
    "R3": ["SMART Attr5 Raw 跨多磁头区域增长",
           "dmesg:\"medium error\" 分布在多个不连续 LBA 范围(R3 特征:分散)",
           "iostat:多区域读写延迟异常"],
    "R4": ["SMART 总体状态是否 FAILED",
           "SMART Attr194 G-Sense Error Rate 是否大幅高于同型号基线",
           "dmesg:是否硬件错误风暴(多条 medium error 密集出现)",
           "messages:同机柜是否多盘同步异常(是 → 机柜级 RV;单盘 → 盘级冲击)"],
    "R5a": ["messages:\"sense code: 0x04 0x01\"(逻辑单元通信失败)/\"0x06 0x29\"(Power on/Reset)",
            "dmesg:\"link reset\"/\"I/O timeout\"/\"device reset\"/\"resetting host\"",
            "hiraidadm:盘状态是否异常(Unconfigured Bad / Offline)"],
    "R6": ["SMART Attr10 Spin Retry Raw ≥ 1 → 主轴启旋异常",
           "SMART Attr3 Spin-Up Time:> 同型号同批次中位数×2 或持续增长 → 轴承磨损",
           "dmesg:\"spin-up timeout\"/\"spin-up retry\"/\"drive not ready\"",
           "iostat:全盘(非特定 LBA 区域)性能下降"],
    "R7": ["dmesg:mpt3sas 链路降速(如 12.0→6.0 Gbps)/DID_TRANSPORT_DISRUPTED/DID_NO_CONNECT/log_info PL层(如 0x31120324)",
           "messages:\"sas: phy(...): link reset\"/链路速率变化记录;hiraidadm phy 状态",
           "SAS PHY 误码:/sys/class/sas_phy/phy-X invalid_dword_count 月度增量>10、loss_of_dword_sync>5、running_disparity>10",
           "SMART 应全健康(PASSED、Attr5/187/197/198=0)——与 FARM 盘体健康互证;若 FS 损坏且无链路错误 → 转查 R15(独立 FS 损坏)"],
}

# R 码 → 处置建议(源自《故障根因分类表》"故障修复措施"+"说明"列)
ACTION_R1 = ("带内:badblocks 触发重映射 + fsck/xfs_repair 修复FS;带外:Depop 隔离退化磁头延寿"
             "(适用性见判定,占比≤25%可行/≤50%边际/>50%换盘);晚期:换盘。\n"
             "DEPOP 隔离参考命令:\n"
             "# 设备待机、磁头归位\nseachest_power --standbyImmediate -d /dev/sdX\n"
             "# 休眠锁磁头\nseachest_power --sleepImmediate -d /dev/sdX\n"
             "⚠️ Depop 前先迁移待隔离磁头区域数据、限制单次读取量(弱读磁头大规模读取可能彻底失效);"
             "相邻磁头同时异常≥2对时降级为边际可行。umount+mount 仅临时恢复FS/带外重启均不修复磁头退化")
ACTION_R2_LIGHT = "轻度R2:监控 + 定期 FARM 复采;须经 OS 侧确认无读写错误(dmesg 无 medium error、Attr5/197/198=0)后维持观察"
ACTION_R2_HEAVY = "重度R2:Depop 隔离(异常头占比≤25%)或换盘(>25%);若已演变出重分配/读写错误按 R1 处置(R2 标注为并发加速因子)"
ACTION_R3 = ("带内:badblocks + fsck/xfs_repair(临时措施);物理坏道不可修复仅能隔离;"
             "退化集中≤25%磁头可试 Depop,跨>25%磁头 Depop 效果有限;晚期换盘")
ACTION_R4 = ("换盘 + 机柜级 RV 治理(同机柜多盘同步异常→机柜级;单盘→盘级冲击);"
             "Depop 不适用(多头退化占比>50%无\"好头\"可保留,且振动为持续外力);umount+mount/带外重启均不可修复")
ACTION_R5A = "厂家固件修复工具/固件升级;umount+mount 不可修复;R5a/R5c 带外重启亦不可修复(仅 R5b 可通过 link reset/带外上下电恢复)"
ACTION_R6 = "换盘(机械退化不可修复);盘停转可尝试带外重启临时恢复(重新 spin-up);冷存储避免高频 Spin-up/down、低温(<10℃)预热后上电"
ACTION_R7HINT = ("FARM 盘体侧健康 → 结合 OS 日志定界:dmesg/messages 有链路错误(降速/DID_NO_CONNECT/PL层log_info)→ R7,"
                 "首选 umount+mount 或 hiraidadm link reset(set phy func=disable/hardreset/linkreset),严重时换线缆/背板;"
                 "仅 FS 损坏 → R15(先只读挂载备份再 fsck/xfs_repair);OS 均无异常 → 硬盘侧健康")


# R 码 → 故障域 · 范围(源自用户《故障根因分类表》故障域/范围两列)
RCODE_DOMAIN = {
    "R1": ("硬盘域", "硬盘本体(磁头/介质/机械/固件)"),
    "R2": ("硬盘域", "硬盘本体(磁头/介质/机械/固件)"),
    "R3": ("硬盘域", "硬盘本体(磁头/介质/机械/固件)"),
    "R4": ("硬盘域", "硬盘本体(磁头/介质/机械/固件)"),
    "R5": ("硬盘域", "硬盘本体(磁头/介质/机械/固件)"),
    "R6": ("硬盘域", "硬盘本体(磁头/介质/机械/固件)"),
    "R7": ("链路域", "互联链路(PCIe + SAS/SATA)"),
    "R8": ("链路域", "互联链路(PCIe + SAS/SATA)"),
    "R9": ("RAID域", "RAID卡(硬件/固件/驱动)"),
    "R10": ("RAID域", "RAID卡(硬件/固件/驱动)"),
    "R11": ("EXP域", "EXP背板(硬件/固件)"),
    "R12": ("EXP域", "EXP背板(硬件/固件)"),
    "R13": ("OS域", "操作系统/文件系统/内核"),
    "R14": ("OS域", "操作系统/文件系统/内核"),
    "R15": ("OS域", "操作系统/文件系统/内核"),
    "R16": ("OS域", "操作系统/文件系统/内核"),
}


def domain_of(rcode):
    """从候选 R 码解析故障域 · 范围。R7?/R1+F4/R1/R3? 等形态取首个 R 编号;
    盘体全健康但方向未定(如仅 R7?)时仍归其候选域;待定界/数据不足 → 待定界域。"""
    if not rcode or rcode in ("待定界", "数据不足", "-"):
        return ("待定界", "—(数据不全或未命中明确 R 码)")
    m = re.match(r"(R\d+)", rcode)
    if m and m.group(1) in RCODE_DOMAIN:
        dom, scope = RCODE_DOMAIN[m.group(1)]
        # 方向性提示(带 ?)标注为"候选"
        if rcode.endswith("?"):
            return (dom + "(候选)", scope)
        return (dom, scope)
    return ("待定界", "—(未识别 R 码)")


def _num(v):
    """标记值清洗:0xFFFF(开路/饱和)/0xDEAD(未校准)不作为数值参与 R 码判定。"""
    return None if v in (None, MARK_FFFF, MARK_DEAD) else v


def rcode_assess(m):
    """按《故障根因分类表》做 FARM 侧 R 码定界。
    返回 dict(rcode, decisive, mode, verdict, severity, action, rationale[], os_checks[],
             depop, abn_heads[], dos_mult[], gradient, notes[])。
    decisive=True 表示 FARM 侧已命中明确 R 码(仍须 OS 侧交叉验证清单闭环);
    decisive=False 表示仅提示方向(如 R7/盘体健康),最终结论取决于 OS 侧证据。"""
    n = m["heads"]
    rc = {"rcode": "-", "decisive": False, "mode": None, "verdict": None, "severity": 0,
          "action": None, "rationale": [], "os_checks": [], "depop": "-", "abn_heads": [],
          "dos_mult": [None] * n, "gradient": None, "notes": [], "weight": 0}
    why, notes = rc["rationale"], rc["notes"]
    if n == 0:
        rc.update(rcode="数据不足", verdict="无磁头数,无法执行 R 码定界")
        return rc

    # ---- 逐头量化指标 ----
    dos_mult = [None] * n
    for i in range(n):
        t, rf = _num(m["h_dos_thresh"][i]), _num(m["h_dos_refresh"][i])
        if t not in (None, 0) and rf is not None:
            dos_mult[i] = rf / float(t)
    rc["dos_mult"] = dos_mult
    vo = [_num(v) for v in m["h_velobs"]]
    has_dos = any(v is not None for v in dos_mult)
    has_vo = any(v is not None for v in vo)
    fafh_abs = []
    for i in range(n):
        vals = [abs(v) for v in (m["h_fafh_od"][i], m["h_fafh_md"][i], m["h_fafh_id"][i]) if v is not None]
        fafh_abs.append(max(vals) if vals else None)
    has_fafh = any(v is not None for v in fafh_abs)
    # H2SAT 读侧退化(逐头): %codewords≠0 / 迭代>6 / BER>300
    h2_bad = []
    for i in range(n):
        r = []
        cw, it, ber = _num(m["h_h2sat_cw"][i]), _num(m["h_h2sat_iter"][i]), _num(m["h_ber"][i])
        if cw not in (None, 0):
            r.append("codewords=%s≠0" % cw)
        if it is not None and it > H2SAT_ITER_ABN:
            r.append("迭代=%s>%d" % (it, H2SAT_ITER_ABN))
        if ber is not None and ber > H2SAT_BER_ABN:
            r.append("BER=%s>%d" % (ber, int(H2SAT_BER_ABN)))
        if r:
            h2_bad.append((i, "; ".join(r)))
    h2_heads = [i for i, _ in h2_bad]

    # ---- 盘级量化指标 ----
    # 异常磁头(定界口径):DOS WR 倍率>200× 或 VO>100
    abn = [i for i in range(n)
           if (dos_mult[i] is not None and dos_mult[i] > DOSWR_ALERT)
           or (vo[i] is not None and vo[i] > VO_ABN)]
    abn_ratio = len(abn) / n
    dm = [v for v in dos_mult if v is not None]
    gradient = None
    if len(dm) >= 2:
        worst, best = max(dm), min(dm)
        if worst > 0:
            gradient = (worst / best) if best > 0 else float("inf")
    rc["gradient"] = gradient
    shock = m["shock"]
    realloc_heads = [i for i in range(n) if (m["h_realloc"][i] or 0) > 0]
    has_h_realloc = any(v is not None for v in m["h_realloc"])
    fafh_abn_heads = [i for i in range(n) if fafh_abs[i] is not None and fafh_abs[i] > FAFH_ABN]
    disc_slip = any((_num(v) or 0) > 0 for v in m["h_disc_slip"])
    r5a = (m["flash_led"] or 0) > 0

    # ---- 数据覆盖度声明 ----
    if not has_dos:
        notes.append("本盘无 DOS Write Count Threshold 数据(JSON 部分盘缺/TXT 普遍缺)→ DOS WR 倍率与梯度比不可评,写侧判据降级为 VO/Realloc/H2SAT")
    if m["source"] == "TXT":
        notes.append("TXT 数据源:无逐头重分配/不可恢复读/H2SAT → R1/R3 定位与仲裁受限,结论关键时应索取该盘 json 复采")
    if (m["firmware"] or "").upper().find("SN02") >= 0:
        notes.append("固件为 SN02:OS 侧须核对 SMART Attr195(VALUE≤011 且 FARM DOS WR<50× → R5c 固件统计Bug,勿误判 R1)")

    def depop_of(ratio):
        if ratio <= DEPOP_OK:
            return "✅ 可行(异常头占比 %.1f%% ≤ 25%%)" % (ratio * 100)
        if ratio <= DEPOP_MARGINAL:
            return "🟡 边际(占比 %.1f%%,需评估剩余容量与服役寿命)" % (ratio * 100)
        return "❌ 不推荐(占比 %.1f%% > 50%%,建议换盘)" % (ratio * 100)

    def grad_txt():
        if gradient is None:
            return "梯度比不可评(有效 DOS WR 倍率头数<2)"
        return "梯度比=%s" % ("∞" if gradient == float("inf") else "%.1f×" % gradient)

    def finish(rcode, mode, verdict, sev, action, decisive=True, depop="-", heads=None, weight=0):
        rc.update(rcode=rcode, mode=mode, verdict=verdict, severity=sev, action=action,
                  decisive=decisive, depop=depop, abn_heads=heads or [], weight=weight)
        base = rcode.split("+")[0].rstrip("?")
        rc["os_checks"] = list(RCODE_OS_CHECKS.get(base, []))
        return rc

    # ================= 定界决策(顺序即优先级) =================
    # ① R4 振动致伤:Shock>10K + 异常头占比>50% + 无梯度(<3×)三条同时满足
    if shock is not None and shock > SHOCK_R4 and abn_ratio > ABN_RATIO_R4 \
            and (gradient is not None and gradient < GRAD_R4):
        why.append("Shock=%d>%d(%s)" % (shock, SHOCK_R4, "极端振动,确认级" if shock > SHOCK_EXTREME else "振动异常"))
        why.append("异常磁头占比 %d/%d=%.0f%%>50%%(异常=DOS WR>200× 或 VO>100): H%s" % (
            len(abn), n, abn_ratio * 100, ", H".join(map(str, abn))))
        why.append(grad_txt() + "<3×(各头退化程度相近,无单头主导)")
        return finish("R4", "R4 振动致伤(多磁头同步退化)", "损坏(外力致多头退化,换盘+机柜治理)",
                      3, ACTION_R4, depop="❌ 不适用(多头>50%无好头可保留,振动为持续外力)",
                      heads=abn, weight=9_000_000 + len(abn))
    # ①' R4 补充形态:极端冲击 + 全/多数磁头飞高异常(机械冲击致全磁头飞高异常形态)
    if shock is not None and shock > SHOCK_EXTREME and has_fafh \
            and n and len(fafh_abn_heads) / n > ABN_RATIO_R4:
        why.append("Shock=%d>%d(极端振动,确认级)" % (shock, SHOCK_EXTREME))
        why.append("飞高|delta|>%.0f 的磁头占比 %d/%d=%.0f%%>50%%(冲击致全磁头飞高异常形态)" % (
            FAFH_ABN, len(fafh_abn_heads), n, len(fafh_abn_heads) / n * 100))
        return finish("R4", "R4 振动致伤(冲击致全磁头飞高异常)", "损坏(极端冲击史+全头飞高异常,换盘+机柜治理)",
                      3, ACTION_R4, depop="❌ 不适用", heads=fafh_abn_heads,
                      weight=9_000_000 + len(fafh_abn_heads))

    # ② R1(+F4):有振动史但退化仍集中少数头(梯度>10×) → 振动为加速因子非根因
    vib_note = ""
    if shock is not None and shock > SHOCK_R4 and gradient is not None and gradient >= GRAD_R1:
        vib_note = "+F4(Shock=%d>10K 但%s>10×,振动为加速因子非根因)" % (shock, grad_txt())

    # ③ R1 磁头信号退化:写侧 DOS WR 倍率超标(200×)且有磁头选择性
    r1_dos_heads = [i for i in range(n) if dos_mult[i] is not None and dos_mult[i] > DOSWR_ALERT]
    if r1_dos_heads and abn_ratio <= ABN_RATIO_R4:
        worst = max(dos_mult[i] for i in r1_dos_heads)
        tier = "严重退化(>1000×,强烈建议Depop)" if worst > DOSWR_SEVERE else "退化告警(200×-1000×,Depop候选)"
        why.append("写侧退化: " + "; ".join("H%d DOS WR=%.0f×" % (i, dos_mult[i]) for i in r1_dos_heads))
        why.append("%s → 显著梯度(R1 特征,磁头选择性)" % grad_txt())
        if h2_bad:
            why.append("读侧退化(H2SAT): " + "; ".join("H%d(%s)" % (i, s) for i, s in h2_bad))
        if realloc_heads:
            why.append("逐头重分配: " + "; ".join("H%d=%d" % (i, m["h_realloc"][i]) for i in realloc_heads))
        if shock is not None and shock < SHOCK_R4:
            why.append("Shock=%d<10K → 排除 R4" % shock)
        vo_hi = [i for i in r1_dos_heads if vo[i] is not None and vo[i] > VO_ABN]
        mode_extra = "(R2 并发加速因子:VO>100)" if vo_hi else ""
        ratio = len(set(r1_dos_heads) | set(realloc_heads)) / n
        sev = 3 if worst > DOSWR_SEVERE else 2
        return finish("R1" + ("+F4" if vib_note else ""),
                      "R1 磁头信号退化%s%s" % (mode_extra, vib_note),
                      "%s;受累磁头 H%s" % (tier, ", H".join(map(str, r1_dos_heads))),
                      sev, ACTION_R1, depop=depop_of(ratio), heads=sorted(set(r1_dos_heads) | set(realloc_heads)),
                      weight=5_000_000 if sev == 3 else 2_000_000)

    # ④ Realloc 存在时:R1 vs R3 仲裁(相关性 + 分布广度 + H2SAT 磁头选择性)
    if realloc_heads:
        spread = len(realloc_heads) / n
        with_dos = [i for i in realloc_heads if dos_mult[i] is not None]
        corr_r1 = corr_r3 = None
        if with_dos:
            hi = sum(1 for i in with_dos if dos_mult[i] > DOSWR_ALERT)
            lo = sum(1 for i in with_dos if dos_mult[i] < DOSWR_HEALTHY)
            corr_r1 = hi / len(with_dos) >= 0.5
            corr_r3 = lo / len(with_dos) >= 0.5
        why.append("逐头重分配: " + "; ".join("H%d=%d" % (i, m["h_realloc"][i]) for i in realloc_heads)
                   + "(跨 %d/%d=%.0f%% 磁头)" % (len(realloc_heads), n, spread * 100))
        if corr_r3 and spread > REALLOC_SPREAD_R3:
            why.append("Realloc 与 DOS WR 不相关(≥50%% Realloc 头 DOS WR<50×)且分布跨>%.0f%%磁头 → 介质本身缺陷" % (REALLOC_SPREAD_R3 * 100))
            if disc_slip:
                why.append("Disc Slip > 0(盘片物理位移/损伤)")
            return finish("R3", "R3 盘片介质退化", "退化(介质缺陷,分布广)", 2, ACTION_R3,
                          depop="🟡 有限适用(跨>25%磁头,效果有限)" if spread > DEPOP_OK else depop_of(spread),
                          heads=realloc_heads, weight=1_500_000)
        # 集中 ≤25% 磁头(或与高 DOS WR 相关) → R1 特征
        if spread <= REALLOC_SPREAD_R3 or corr_r1:
            why.append("Realloc 集中在 ≤25%% 磁头%s → R1 特征(磁头选择性)" % ("且与高 DOS WR 相关" if corr_r1 else ""))
            if h2_bad:
                sel = [i for i in h2_heads if i in realloc_heads]
                why.append("H2SAT 读侧%s: %s" % ("集中于损伤磁头(仲裁→R1)" if sel else "异常",
                                                 "; ".join("H%d(%s)" % (i, s) for i, s in h2_bad)))
            if not has_dos:
                why.append("注:无 DOS WR 数据,R1 判定基于 Realloc 集中度+读侧证据(降级判定)")
            if shock is not None and shock < SHOCK_R4:
                why.append("Shock=%d<10K → 排除 R4" % shock)
            return finish("R1" + ("+F4" if vib_note else ""), "R1 磁头信号退化(介质损伤集中型)%s" % vib_note,
                          "退化;受累磁头 H%s" % ", H".join(map(str, realloc_heads)),
                          2, ACTION_R1, depop=depop_of(spread), heads=realloc_heads, weight=2_000_000)
        # 介于两者之间:R1/R3 待仲裁
        why.append("Realloc 分布 %.0f%% 且相关性不确定 → R1/R3 待 H2SAT 磁头选择性与 OS 侧仲裁" % (spread * 100))
        rc["os_checks"] = RCODE_OS_CHECKS["R1"] + RCODE_OS_CHECKS["R3"]
        rc.update(rcode="R1/R3?", decisive=False, severity=2,
                  mode="介质损伤,R1/R3 待仲裁", verdict="退化(根因待 OS 侧仲裁)",
                  action=ACTION_R3, depop=depop_of(spread), abn_heads=realloc_heads, weight=1_200_000)
        return rc

    # ⑤ R2 磁头飞行异常:写侧未见退化(<50×)、无介质损伤,但 VO>100 或 FAFH>200
    vo_abn_heads = [i for i in range(n) if vo[i] is not None and vo[i] > VO_ABN]
    if (vo_abn_heads or fafh_abn_heads) and (m["realloc"] or 0) == 0 and (m["unrec_read"] or 0) == 0 \
            and all(v is None or v < DOSWR_HEALTHY for v in dos_mult):
        heavy = any(vo[i] > VO_HEAVY for i in vo_abn_heads) or \
                any(fafh_abs[i] is not None and fafh_abs[i] > FAFH_HEAVY for i in fafh_abn_heads)
        if vo_abn_heads:
            why.append("飞行异常: " + "; ".join("H%d VO=%s>100" % (i, vo[i]) for i in vo_abn_heads))
        if fafh_abn_heads:
            why.append("飞高偏离: " + "; ".join("H%d |FAFH|=%.0f>200" % (i, fafh_abs[i]) for i in fafh_abn_heads))
        why.append("所有磁头 DOS WR<50×、Realloc=0、无不可恢复读 → 排除 R1 主导(纯 R2,尚未演变)")
        heads = sorted(set(vo_abn_heads) | set(fafh_abn_heads))
        ratio = len(heads) / n
        return finish("R2", "R2 磁头飞行异常(%s)" % ("重度" if heavy else "轻度候选"),
                      "%s;受累磁头 H%s" % ("重度R2(VO>500或FAFH>500)" if heavy else "轻度R2候选(待OS侧确认无读写错误)",
                                           ", H".join(map(str, heads))),
                      2 if heavy else 1, ACTION_R2_HEAVY if heavy else ACTION_R2_LIGHT,
                      depop=depop_of(ratio) if heavy else "-", heads=heads,
                      weight=800_000 if heavy else 100_000)

    # ⑥ R3 早期(候选积累型):Realloc=0 但 Pending 候选 > 500
    if (m["realloc"] or 0) == 0 and (m["realloc_cand"] or 0) > PENDING_EARLY_R3:
        why.append("Realloc=0 但候选(Pending)=%d>%d → 早期介质退化(候选积累型)" % (m["realloc_cand"], PENDING_EARLY_R3))
        return finish("R3", "R3 盘片介质退化(早期,候选积累型)", "早期退化(退化进行中,持续监控候选增长)",
                      2, ACTION_R3, heads=[], weight=1_000_000)

    # ⑦ R5a:固件主动断言(无物理退化信号时作为主定界)
    if r5a:
        why.append("FARM Flash LED (Assert) Events=%d>0 → 固件主动标记异常(R5a 可 FARM 定界)" % m["flash_led"])
        return finish("R5a", "R5a 硬盘固件异常(固件Assert)", "失效(固件级)", 3, ACTION_R5A,
                      weight=6_000_000)

    # ⑧ R6 候选:主轴启旋异常且无磁头选择性
    if (m["spin_retry"] or 0) >= 1 and not abn:
        why.append("Spin Retry=%d≥1 且无磁头选择性退化 → R6 机械电机退化候选" % m["spin_retry"])
        return finish("R6?", "R6 机械电机退化(候选)", "退化候选(待 OS 侧 Attr3/Attr10 同批次比对确认)",
                      2, ACTION_R6, decisive=False, weight=900_000)

    # ⑨ FARM 盘体全健康 → R7/OS 域提示(非终态,取决于 OS 侧)
    body_ok = ((m["realloc"] or 0) == 0 and (m["realloc_cand"] or 0) == 0 and (m["unrec_read"] or 0) == 0
               and all(v is None or v < DOSWR_HEALTHY for v in dos_mult)
               and all(v is None or v <= VO_NORMAL for v in vo) and not h2_bad
               and (shock is None or shock < SHOCK_CLEAR))
    if body_ok:
        cov = "" if (has_dos or has_vo) and m["source"] == "JSON" else "(逐头数据不全,盘体健康为降级判定,建议补采 json)"
        why.append("所有磁头 DOS WR<50×、VO≤30、H2SAT 无异常、Realloc/候选/不可恢复读=0、Shock<1,000 → 盘体完全健康%s" % cov)
        iface = []
        if (m["crc_err"] or 0) > 0:
            iface.append("接口 CRC=%d" % m["crc_err"])
        if (m["cto_total"] or 0) > 0:
            iface.append("CTO=%d" % m["cto_total"])
        if iface:
            why.append("但接口计数异常(%s) → 强化 R7 链路方向" % ", ".join(iface))
        rc.update(rcode="R7?", decisive=False, severity=0,
                  mode="FARM 盘体全健康(R7 链路/OS 域候选)",
                  verdict="盘体健康——若 OS 侧有链路错误则定界 R7;若仅 FS 损坏则 R15;OS 亦无异常则为健康盘",
                  action=ACTION_R7HINT, weight=50_000 if iface else 0)
        rc["os_checks"] = list(RCODE_OS_CHECKS["R7"])
        return rc

    # ⑩ 未命中明确 R 码:输出中间形态供人工研判
    if abn:
        why.append("异常磁头 H%s(占比 %.0f%%)但未同时满足任一 R 码全部判据(如 3×-10× 梯度中间区,需结合 Shock/OS 侧研判)" % (
            ", H".join(map(str, abn)), abn_ratio * 100))
    rc.update(rcode="待定界", decisive=False, severity=1 if abn else 0,
              mode="FARM 侧未命中明确 R 码", verdict="待定界(结合 OS 侧证据或补采数据)",
              action="按 references/root_cause_rules.md 决策树人工研判;数据不全时补采 FARM(json)+OS 日志",
              abn_heads=abn, weight=200_000 if abn else 0)
    rc["os_checks"] = RCODE_OS_CHECKS["R1"][:2] + RCODE_OS_CHECKS["R7"][:1]
    return rc


# --------------------------------------------------------------------------- 8 categories
def categorize(m):
    n = m["heads"]
    cats = []
    fafh_out, fafh_med = fafh_outliers(m)
    # per-head severity accumulators (surface, channel)
    surf = [0] * n
    chan = [0] * n

    # ---- 1 盘片表面 / 坏扇区 ----
    f, sev = [], 0
    if (m["realloc"] or 0) > 0:
        f.append("整盘重分配扇区 Reallocated=%d" % m["realloc"])
        sev = max(sev, 2)
    if (m["realloc_cand"] or 0) > 0:
        f.append("重分配候选 Candidate=%d(有坏道待处理→退化进行中)" % m["realloc_cand"])
        sev = max(sev, 2)
    if (m["unrec_read"] or 0) > 0:
        f.append("不可恢复读错误 UnrecRead=%d(已上抛主机,应为0)" % m["unrec_read"])
        sev = max(sev, 2)
    if (m["unrec_write"] or 0) > 0:
        f.append("不可恢复写错误 UnrecWrite=%d" % m["unrec_write"])
        sev = max(sev, 2)
    # per-head localization
    loc = []
    for i in range(n):
        hs = 0
        if (m["h_realloc"][i] or 0) >= HEAD_REALLOC_WARN:
            loc.append("H%d重分配=%d" % (i, m["h_realloc"][i]))
            hs = 2
        if (m["h_cand"][i] or 0) > 0:
            loc.append("H%d候选=%d" % (i, m["h_cand"][i]))
            hs = max(hs, 2)
        if (m["h_cum_uniq"][i] or 0) > 0:
            loc.append("H%d不可恢复读Unique=%d" % (i, m["h_cum_uniq"][i]))
            hs = max(hs, 2)
        surf[i] = hs
    if loc:
        f.append("逐头定位: " + "; ".join(loc))
    elif (m["realloc"] or 0) > 0 and all((m["h_realloc"][i] or 0) == 0 for i in range(n)):
        f.append("注:整盘重分配>0 但逐头数全为0(本帧未填充逐头分布,无法定位到具体磁头)")
    cats.append({"cat": 1, "name": "盘片表面/坏扇区", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["重分配=0、无不可恢复读错误"]})

    # ---- 2 磁头 / 读写通道 / ECC ----
    # FAFH 飞高 clearance delta 是出厂校准量,逐头天然差异大(中位 43~323 不等),单独离群只算"关注";
    # 唯有与同头介质损伤(类1:重分配/不可恢复读)共振,才升级为"退化"(物理因果链:飞高偏移→读错误→坏道)。
    f, sev = [], 0
    for i in range(n):
        r, hs = [], 0
        if m["h_mrr"][i] in (MARK_FFFF,) or m["h_mrr2"][i] in (MARK_FFFF,):
            r.append("MRR=0xFFFF(磁头开路/硬故障)")
            hs = 3
        if (m["h_h2sat_amp"][i] or 0) == MARK_DEAD:
            r.append("H2SAT幅度=0xDEAD(无效)")
        if i in fafh_out and fafh_med:
            mx = max(abs(v) for v in (m["h_fafh_od"][i], m["h_fafh_md"][i], m["h_fafh_id"][i]) if v is not None)
            co = surf[i] >= 2  # 同头是否已有介质损伤
            r.append("飞高FAFH偏移|%.0f|>中位%.0f×%.1f%s" % (
                mx, fafh_med, OUTLIER_HI, "(且同头有坏道→退化)" if co else "(校准离群,关注)"))
            hs = max(hs, 2 if co else 1)
        if r:
            f.append("H%d: %s" % (i, "; ".join(r)))
        chan[i] = hs
        sev = max(sev, hs)
    cats.append({"cat": 2, "name": "磁头/读写通道/ECC", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["逐头飞高/MRR在同族区间,无磁头开路/无效标记"]})

    # ---- 3 机械 / 马达 / 伺服 ----
    f, sev = [], 0
    if (m["mech_start_fail"] or 0) > 0:
        f.append("机械启动失败 %d" % m["mech_start_fail"]); sev = max(sev, 2)
    if (m["spin_retry"] or 0) > 0:
        f.append("主轴重试 SpinRetry=%d" % m["spin_retry"]); sev = max(sev, 2)
    if (m["helium_trip"] or 0) > 0:
        f.append("氦气压力阈值触发(氦气盘泄漏)"); sev = max(sev, 3)
    if (m["servo_status"] or 0) > 0:
        f.append("伺服状态码 servo_status=%d" % m["servo_status"]); sev = max(sev, 1)
    if m["motor_power"] is not None:
        f.append("主轴马达功率 motor_power=%s" % m["motor_power"])
    comp_bad = component_degraded_heads(m)
    if comp_bad:
        ratio = len(comp_bad) / n if n else 0.0
        detail = []
        for i in comp_bad:
            v = m["h_velobs"][i]
            t, r = m["h_dos_thresh"][i], m["h_dos_refresh"][i]
            reasons = []
            if v is not None and v > VELOBS_WARN:
                reasons.append("VelocityObserver=%s>%d" % (v, VELOBS_WARN))
            if t not in (None, 0) and r is not None and r > DOS_THRESH_MULT * t:
                reasons.append("DOSWriteRefresh=%s>%d×Threshold(%s)" % (r, DOS_THRESH_MULT, t))
            detail.append("H%d(%s)" % (i, "; ".join(reasons)))
        f.append("磁头/组件退化判据触发,占比 %d/%d=%.0f%%: %s" % (
            len(comp_bad), n, ratio * 100, "; ".join(detail)))
        sev = max(sev, 3 if ratio >= HEAD_DEGRADE_RATIO_CRIT else 2)
    cats.append({"cat": 3, "name": "机械/马达/伺服", "coverage": COV_PART, "severity": sev,
                 "findings": f or ["主轴/伺服/机械启动无明显异常"]})

    # ---- 4 接口 / 传输 ----
    f, sev = [], 0
    if (m["crc_err"] or 0) > 0:
        f.append("接口 CRC 错误 %d(线缆/背板/HBA 可疑)" % m["crc_err"]); sev = max(sev, 2)
    if (m["cto_total"] or 0) >= CTO_WARN:
        det = "CTO命令超时累计=%d" % m["cto_total"]
        if (m["cto_75s"] or 0) > 0 or (m["cto_5s"] or 0) > 0:
            det += "(其中>5s:%d, >7.5s:%d)" % (m["cto_5s"] or 0, m["cto_75s"] or 0)
            sev = max(sev, 2)
        else:
            sev = max(sev, 1)
        f.append(det)
    if (m["hw_reset"] or 0) > 0:
        f.append("硬件复位计数 hw_reset=%d" % m["hw_reset"]); sev = max(sev, max(sev, 1) if (m["crc_err"] or 0) else 0)
    cats.append({"cat": 4, "name": "接口/传输", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["CRC=0、CTO超时为0(ATA FARM 含 CRC,优于 SAS)"]})

    # ---- 5 温度 / 环境 / 振动 ----
    f, sev = [], 0
    if m["temp_max"] is not None:
        if m["temp_max"] >= TEMP_CRIT:
            f.append("温度过高 max %.0f℃" % m["temp_max"]); sev = max(sev, 2)
        elif m["temp_max"] >= TEMP_WARN:
            f.append("温度偏高 max %.0f℃" % m["temp_max"]); sev = max(sev, 1)
        else:
            f.append("温度 %s~%.0f℃ 正常" % (m["temp_min"], m["temp_max"]))
    if (m["time_over_temp"] or 0) > 0:
        f.append("累计超温时长 time_over_temp=%d" % m["time_over_temp"]); sev = max(sev, 1)
    if (m["shock"] or 0) >= SHOCK_WARN:
        f.append("过限冲击事件 shock=%d(机柜振动/搬运冲击偏多)" % m["shock"]); sev = max(sev, 1)
    if m["humidity"] is not None and m["humidity"] >= HUMID_WARN:
        f.append("湿度偏高 %.0f%%" % m["humidity"]); sev = max(sev, 1)
    cats.append({"cat": 5, "name": "温度/环境/振动", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["温度/冲击/湿度均正常"]})

    # ---- 6 寿命 / 工况(信息为主)----
    f = ["上电 poh=%s 小时  上电次数=%s  额定负载=%s%%" % (m["poh"], m["power_cycle"], m["workload_pct"])]
    f.append("累计读命令=%s  写命令=%s" % (m["read_cmds"], m["write_cmds"]))
    cats.append({"cat": 6, "name": "寿命/工况", "coverage": COV_FULL, "severity": 0, "findings": f})

    # ---- 7 固件 / 服务区 ----
    f, sev = [], 0
    if (m["flash_led"] or 0) > 0:
        f.append("Flash LED (固件Assert) 事件=%d(固件异常断言)" % m["flash_led"]); sev = max(sev, 2)
    if m["depopped"] in (True, "True"):
        f.append("磁盘已 Depop(磁头屏蔽降级),掩码=%s" % m["depop_mask"]); sev = max(sev, 1)
    if (m["uncorrectable"] or 0) > 0:
        f.append("Uncorrectable errors=%d" % m["uncorrectable"]); sev = max(sev, 2)
    if m["source"] == "TXT":
        f.append("注:TXT 不含 Flash LED 事件明细/Depop 状态,本类判定降级")
    cats.append({"cat": 7, "name": "固件/服务区", "coverage": (COV_PART if m["source"] == "JSON" else "降级(TXT)"),
                 "severity": sev, "findings": f or ["无固件 Assert 事件、未 Depop"]})

    # ---- 8 SSD ----
    cats.append({"cat": 8, "name": "SSD磨损(本盘为HDD)", "coverage": COV_NA, "severity": 0,
                 "findings": ["本盘有磁头/飞高/主轴,判定为机械硬盘,SSD 磨损类不适用"]})
    return cats, surf, chan, fafh_med, comp_bad


ACTION_COMPONENT_SCRAP = "不建议修复,建议备份数据后报废更换硬盘。"
ACTION_COMPONENT_DEPOP = (
    "1.建议重新挂载硬盘:\n"
    "# 按设备名卸载\n"
    "umount /dev/sdx\n"
    "# 重新挂载 mount,格式:mount 设备路径 挂载目录\n"
    "mount /dev/sdx /mnt/data\n"
    "2.建议将退化的磁头通过DEPOP隔离:\n"
    "# 设备待机、磁头归位\n"
    "seachest_power --standbyImmediate -d /dev/sdb\n"
    "# 休眠锁磁头\n"
    "seachest_power --sleepImmediate -d /dev/sdb")


def classify(m, cats, surf, chan, comp_bad, rc):
    n = m["heads"]
    active_cand = (m["realloc_cand"] or 0) > 0 or any((m["h_cand"][i] or 0) > 0 for i in range(n))
    # ========== 【HARD-LOCK】用户定义的磁头/组件退化确定性规则 ==========
    # 规则(源自用户,严禁改判):
    #   逐头:Velocity Observer > 200,或(DOS Write Count Threshold 非0 且
    #        DOS Write Refresh Count > 1000 × Threshold)→ 判该头"组件退化"
    #   盘级:退化磁头占比 ≥ 50% → 终态"损坏"(备份后报废换盘,固定文案)
    #        退化磁头占比 <  50% → 终态"健康"(重新挂载 + DEPOP 隔离,固定文案)
    # 关键约束:
    #   1. 本规则**优先于/覆盖** R 码定界与所有 8 类部位层发现——即使同盘并存重分配/
    #      候选扇区/不可恢复读/固件不可纠正错误,只要占比<50%,健康判定就仍是"健康",
    #      处置仍是"重新挂载 + DEPOP 隔离",**不得**因这些现象升级为"损坏 / P1"。
    #   2. R 码(R1 磁头信号退化)仍作为并发根因描述保留在报告 R 码定界段,但
    #      "健康判定 / 故障模式 / 处置建议"三项一律取本规则输出。
    #   3. 决策路径必须在 rc["decisive"] 之前,避免 R1 抢先返回而绕过本规则。
    if comp_bad:
        ratio = len(comp_bad) / n if n else 0.0
        rcode_ctx = rc["rcode"] if rc["rcode"] not in ("-", "待定界") else "组件退化"
        if ratio >= HEAD_DEGRADE_RATIO_CRIT:
            mode = "磁头/组件退化【确定性规则】:占比 %d/%d=%.0f%%≥50%% (并发 %s)" % (
                len(comp_bad), n, ratio * 100, rcode_ctx)
            return {"mode": mode, "verdict": "损坏", "severity": 3, "action": ACTION_COMPONENT_SCRAP,
                    "bad_heads": comp_bad, "active": True, "rcode": rc["rcode"],
                    "weight": 10_000_000 + len(comp_bad), "top_cat": "3 机械/马达/伺服",
                    "det_rule": True, "det_ratio": ratio}
        else:
            mode = "磁头/组件退化【确定性规则】:占比 %d/%d=%.0f%%<50%% (并发 %s)" % (
                len(comp_bad), n, ratio * 100, rcode_ctx)
            # 注意:健康判定=健康,不受候选/URE/固件不可纠正错误影响(用户规则硬约束)
            return {"mode": mode, "verdict": "健康", "severity": 0, "action": ACTION_COMPONENT_DEPOP,
                    "bad_heads": comp_bad, "active": False, "rcode": rc["rcode"],
                    "weight": 100 + len(comp_bad), "top_cat": "3 机械/马达/伺服",
                    "det_rule": True, "det_ratio": ratio}
    # ========== 【HARD-LOCK 结束】以下为常规 R 码/8 类判定 ==========
    # 冷存储 R 码定界规则(用户定义《故障根因分类表》,references/root_cause_rules.md):
    # FARM 侧命中明确 R 码时,故障模式/健康判定/处置建议由规则表直接给出;
    # 8 类部位层结论仍保留在逐类明细中;最终 R 码须经 OS 侧交叉验证清单闭环。
    if rc["decisive"]:
        return {"mode": rc["mode"], "verdict": rc["verdict"], "severity": rc["severity"],
                "action": rc["action"], "bad_heads": rc["abn_heads"], "active": active_cand,
                "weight": rc["weight"], "top_cat": "R码定界", "rcode": rc["rcode"],
                "det_rule": False}
    # "退化磁头"判据:有介质损伤(类1 surf>=2)或磁头硬故障(通道 sev3,如 MRR 开路)。
    # 仅 FAFH 校准离群(chan==1)不算退化头,避免把出厂校准差异误判成失效。
    bad = [i for i in range(n) if surf[i] >= 2 or chan[i] >= 3]
    marked = [i for i in range(n) if (m["h_mrr"][i] == MARK_FFFF or m["h_mrr2"][i] == MARK_FFFF)]
    # 活跃度近似:候选重分配 > 0(整盘或任一头)即"退化进行中"
    active = (m["realloc_cand"] or 0) > 0 or any((m["h_cand"][i] or 0) > 0 for i in range(n))
    top = max((c for c in cats if c["cat"] != 8), key=lambda c: c["severity"])

    if (m["flash_led"] or 0) > 0 or (m["helium_trip"] or 0) > 0 or len(marked) >= 2:
        cause = "氦气泄漏" if (m["helium_trip"] or 0) > 0 else (
            "固件Assert" if (m["flash_led"] or 0) > 0 else "多磁头开路")
        mode = "固件/硬件级失效(%s)" % cause; verdict = "失效"; sev = 3
        action = "带外(IPMI)处理+备份+换盘;排查固件"
    elif len(bad) >= 2:
        mode = "多磁头介质退化"; verdict = "严重:多盘面退化"; sev = 3
        action = "立即抢救数据并换盘"
    elif len(bad) == 1:
        i = bad[0]; sev = 2
        mode = "单磁头退化(H%d)" % i
        if active:
            verdict = "退化进行中:仅 H%d 异常且有候选坏道待处理" % i
            action = "RAID冗余下优先磁头级降级禁用 H%d(损约%.1f%%)或换盘" % (i, 100.0 / max(n, 1))
        else:
            verdict = "单头退化但暂稳:仅 H%d 异常、无候选坏道" % i
            action = "强化监控 H%d;RAID 兜底可中期留用" % i
    elif (m["realloc"] or 0) > 0 and not bad:
        # 整盘有坏道但无法定位到头(逐头全0)
        sev = 2; mode = "整盘介质退化(未定位到磁头)"
        verdict = "%s:整盘重分配%d" % ("退化进行中" if active else "退化(暂稳)", m["realloc"])
        action = "备份数据;%s" % ("有候选坏道在涨,倾向换盘" if active else "加强监控,RAID兜底可观察")
    elif top["severity"] >= 2:
        sev = 2; mode = "%s异常" % top["name"]; verdict = "严重:%s" % top["name"]
        action = "按该类别处置(见逐类明细)"
    elif any(c["severity"] == 1 for c in cats):
        sev = 1; mode = "轻度异常/早期预警"; verdict = "亚健康:有关注项"
        action = "纳入加密监控"
    else:
        sev = 0; mode = "无异常"; verdict = "健康"; action = "常规监控"
    # 同评级下的排序权重:不可恢复读 + 整盘重分配 + 候选 + 活跃 + 退化头数,越大越差
    weight = ((m["unrec_read"] or 0) + (m["realloc"] or 0) + (m["realloc_cand"] or 0) * 10
              + len(bad) * 1000 + (5000 if active else 0))
    return {"mode": mode, "verdict": verdict, "severity": sev, "action": action,
            "bad_heads": bad, "active": active, "weight": weight, "rcode": rc["rcode"],
            "top_cat": ("%d %s" % (top["cat"], top["name"])) if top["severity"] > 0 else "-",
            "det_rule": False}


# --------------------------------------------------------------------------- per-disk
def analyze_disk(g):
    m = load_json(g["json"]) if g["use"] == "json" else load_txt(g["txt"])
    m["sn"] = m.get("sn") or g["sn"]
    m["ip"] = g["ip"]
    cats, surf, chan, fafh_med, comp_bad = categorize(m)
    rc = rcode_assess(m)
    summary = classify(m, cats, surf, chan, comp_bad, rc)
    return {"m": m, "cats": cats, "surf": surf, "chan": chan,
            "fafh_med": fafh_med, "comp_bad": comp_bad, "rc": rc, "summary": summary}


# --------------------------------------------------------------------------- render
def render(root, results):
    L = ["# 希捷 FARM 多盘健康分析报告", "",
         "扫描目录: `%s`  共发现 **%d** 块盘" % (root, len(results)), ""]
    order = sorted(results, key=lambda r: (-r["summary"]["severity"], -r["summary"]["weight"], r["m"]["sn"]))
    # 【HARD-LOCK】用户确定性规则触发盘的顶部横幅——多盘报告中让 agent 一眼看到
    det_disks = [r for r in results if r["summary"].get("det_rule")]
    if det_disks:
        L += ["## ⛔ 用户确定性规则触发提示(所有 agent 必读)", "",
              "以下磁盘命中**用户定义的确定性规则**(逐头 VO>200 或 DOS Write Refresh>1000×Threshold),",
              "健康判定 / 故障模式 / 处置建议**必须逐字采用脚本输出**,不得因同盘伴随的 Realloc / URE /",
              "Pending / 固件不可纠正错误 / SMART FAILED / XFS shutdown 等现象将结论改判为损坏/换盘/P1。",
              "",
              "| SN | 磁头数 | 组件退化头 | 占比 | 终态健康判定 | 固定处置 |",
              "|---|---|---|---|---|---|"]
        for r in det_disks:
            sm, mo = r["summary"], r["m"]
            ratio = sm.get("det_ratio", 0.0)
            verdict = "**损坏**(≥50%)" if ratio >= HEAD_DEGRADE_RATIO_CRIT else "**健康**(<50%)"
            action = "备份→报废换盘" if ratio >= HEAD_DEGRADE_RATIO_CRIT else "重新挂载 + DEPOP 隔离"
            L.append("| %s | %d | H%s | %.0f%% | %s | %s |" % (
                mo["sn"], mo["heads"], ", H".join(map(str, sm["bad_heads"])),
                ratio * 100, verdict, action))
        L.append("")

    L += ["## 机群汇总(按健康度 差→好)", "",
          "| IP | 盘SN | 型号 | 固件 | 磁头 | 数据源 | 总评级 | 故障域 | R码定界(FARM侧) | 故障模式 | 主要类别 | 受影响磁头 | 处置 |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in order:
        m, sm = r["m"], r["summary"]
        bh = ("H" + ", H".join(map(str, sm["bad_heads"]))) if sm["bad_heads"] else "-"
        act_cell = sm["action"].replace("\n", "<br>")  # 多行处置命令在表格单元格内需转 <br>,避免破坏 markdown 表格
        dom, _scope = domain_of(sm.get("rcode", "-"))
        L.append("| %s | %s | %s | %s | %s | %s | **%s** | **%s** | **%s** | %s | %s | %s | %s |" % (
            m.get("ip", "-"), m["sn"], m.get("model") or "-", m.get("firmware") or "-",
            m["heads"], m["source"], SEV_LABEL[sm["severity"]], dom, sm.get("rcode", "-"), sm["mode"],
            sm["top_cat"], bh, act_cell))
    L.append("")

    for r in order:
        m, sm = r["m"], r["summary"]
        mach2 = "  [Mach.2双致动器]" if m["heads"] == 18 else ""
        dom, scope = domain_of(sm.get("rcode", "-"))
        L += ["---", "", "## 盘 %s (IP %s) —— [%s] %s / %s%s" % (
            m["sn"], m.get("ip", "-"), dom, SEV_LABEL[sm["severity"]], sm["mode"], mach2), ""]
        # 【HARD-LOCK】用户确定性规则触发时,报告最上方强制展示锁定信息,防止 agent
        # 被同盘的重分配/URE/Pending 等现象带偏改判(参照 seagate 技能"反例踩坑"约束)。
        if sm.get("det_rule"):
            ratio = sm.get("det_ratio", 0.0)
            if ratio >= HEAD_DEGRADE_RATIO_CRIT:
                L += ["> [!CAUTION]",
                      "> **⛔ 用户确定性规则触发【健康判定 = 损坏】**",
                      "> 组件退化磁头 H%s,占比 %.0f%% ≥ 50%%——按用户定义规则终态为**损坏**。" %
                      (", H".join(map(str, sm["bad_heads"])), ratio * 100),
                      "> **处置固定文案**:`%s`" % ACTION_COMPONENT_SCRAP,
                      "> **硬约束**:即使同盘伴随重分配/URE/Pending/固件不可纠正错误,agent 报告的"
                      "健康判定 / 故障级别 / 处置建议三项**必须逐字复制脚本输出**,不得改写。",
                      ""]
            else:
                L += ["> [!CAUTION]",
                      "> **⛔ 用户确定性规则触发【健康判定 = 健康】**",
                      "> 组件退化磁头 H%s,占比 %.0f%% < 50%%——按用户定义规则终态为**健康**,处置为"
                      "**重新挂载 + DEPOP 隔离**。" % (", H".join(map(str, sm["bad_heads"])), ratio * 100),
                      "> **硬约束**:**即使**同盘伴随 Realloc/Candidate/URE > 0、Pending Sector 高、"
                      "固件不可纠正错误 > 0、SMART FAILED、XFS shutdown 等现象,agent **不得**将"
                      "健康判定升级为损坏/退化/亚健康,不得改写处置为换盘/更换硬件/P1 Critical。"
                      "候选扇区/URE/Pending 只能写入"
                      "\"关键发现\"用于描述现象,**不参与**本规则的健康判定。",
                      "> **处置固定文案**(逐字复制):",
                      "> ```",
                      "> " + ACTION_COMPONENT_DEPOP.replace("\n", "\n> "),
                      "> ```",
                      ""]
        L.append("- 型号 %s  固件 %s  接口 %s  磁头 %s  记录方式 %s  数据源 %s(%s)" % (
            m.get("model") or "-", m.get("firmware") or "-", m.get("interface") or "-",
            m["heads"], m.get("rec_type") or "-", m["source"], m["coverage"]))
        L.append("- 上电 %s 小时  上电次数 %s  温度 %s~%s℃  冲击 %s  湿度 %s%%  额定负载 %s%%" % (
            m["poh"], m["power_cycle"], m["temp_min"], m["temp_max"],
            m["shock"], m["humidity"], m["workload_pct"]))
        L.append("- 不可恢复读 %s  整盘重分配 %s  重分配候选 %s  CRC %s  CTO %s  FlashLED %s" % (
            m["unrec_read"], m["realloc"], m["realloc_cand"], m["crc_err"], m["cto_total"], m["flash_led"]))

        L += ["", "### 逐类(故障部位)分析", "",
              "| # | 故障部位 | 覆盖度 | 评级 | 关键发现 |", "|---|---|---|---|---|"]
        for c in r["cats"]:
            L.append("| %d | %s | %s | %s | %s |" % (
                c["cat"], c["name"], c["coverage"], SEV_LABEL[c["severity"]], "；".join(c["findings"])))

        # 逐头明细(仅 JSON 有完整逐头;TXT 标注)
        L += ["", "### 逐磁头明细", ""]
        if (any(v is not None for v in m["h_realloc"]) or any(v is not None for v in m["h_fafh_od"])
                or any(v is not None for v in m["h_velobs"]) or any(v is not None for v in m["h_dos_thresh"])):
            comp_set = set(r["comp_bad"])
            rc_set = set(r["rc"]["abn_heads"])
            dosm = r["rc"]["dos_mult"]
            L += ["| Head | 表面 | 通道 | 重分配 | 候选 | 不可恢复读(uniq) | FAFH(O/M/I) | MRR | DOS刷新 | DOS阈值 | DOS倍率 | VelObs | 组件退化 | R码异常头 |",
                  "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
            for i in range(m["heads"]):
                fafh = "%s/%s/%s" % (m["h_fafh_od"][i], m["h_fafh_md"][i], m["h_fafh_id"][i])
                L.append("| H%d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                    i, SEV_LABEL[r["surf"][i]], SEV_LABEL[r["chan"][i]],
                    m["h_realloc"][i] if m["h_realloc"][i] is not None else "-",
                    m["h_cand"][i] if m["h_cand"][i] is not None else "-",
                    m["h_cum_uniq"][i] if m["h_cum_uniq"][i] is not None else "-",
                    fafh, m["h_mrr"][i] if m["h_mrr"][i] is not None else "-",
                    m["h_dos_refresh"][i] if m["h_dos_refresh"][i] is not None else "-",
                    m["h_dos_thresh"][i] if m["h_dos_thresh"][i] is not None else "-",
                    ("%.0f×" % dosm[i]) if dosm[i] is not None else "-",
                    m["h_velobs"][i] if m["h_velobs"][i] is not None else "-",
                    "是" if i in comp_set else "否",
                    "⚠" if i in rc_set else "-"))
            if r["fafh_med"]:
                L.append("\n_FAFH 同族中位偏移≈%.0f;离群阈值=中位×%.1f_" % (r["fafh_med"], OUTLIER_HI))
            if r["comp_bad"]:
                L.append("\n_组件退化判据:VelObs>%d,或 DOS阈值非0 且 DOS刷新>%d×阈值_" % (VELOBS_WARN, DOS_THRESH_MULT))
            L.append("\n_DOS倍率=DOS刷新/DOS阈值;R码口径:<50×健康 / 50-200×老化 / 200-1000×退化告警 / >1000×严重退化_")
        else:
            L.append("_本数据源无逐头明细(TXT 仅含部分逐头块);逐头定位见类1发现_")

        # 冷存储根因定界(R 码,FARM 侧)
        rc = r["rc"]
        L += ["", "### 冷存储根因定界(R码,FARM侧)", "",
              "- **故障域: %s** · 范围: %s" % (dom, scope),
              "- **候选R码: %s**(%s)" % (rc["rcode"],
                                         "FARM侧已命中判据,待OS侧交叉验证闭环" if rc["decisive"]
                                         else "方向性提示,最终定界取决于OS侧证据"),
              "- 梯度比: %s  异常磁头: %s" % (
                  ("∞" if rc["gradient"] == float("inf") else
                   ("%.1f×" % rc["gradient"] if rc["gradient"] is not None else "不可评")),
                  ("H" + ", H".join(map(str, rc["abn_heads"]))) if rc["abn_heads"] else "无"),
              "- Depop适用性: %s" % rc["depop"]]
        if rc["rationale"]:
            L.append("- 判定依据:")
            L += ["  - %s" % w for w in rc["rationale"]]
        if rc["notes"]:
            L.append("- 数据覆盖度/特别提示:")
            L += ["  - %s" % w for w in rc["notes"]]
        if rc["os_checks"]:
            L.append("- OS侧交叉验证清单(在 messages/dmesg/SMART/hiraidadm 中核验后闭环):")
            L += ["  - [ ] %s" % w for w in rc["os_checks"]]

        L += ["", "### 结论",
              "- 故障域: **%s** · 范围: %s" % (dom, scope),
              "- 候选R码: **%s**  故障模式: **%s**  健康判定: **%s**  活跃度: %s" % (
                  sm.get("rcode", "-"), sm["mode"], sm["verdict"],
                  "退化进行中" if sm["active"] else "暂稳/无活跃坏道"),
              ("- 受影响磁头: H%s" % ", H".join(map(str, sm["bad_heads"])) if sm["bad_heads"] else "- 受影响磁头: 无(或未定位到头)"),
              "- 处理建议: %s" % sm["action"]]

    L += ["", "> 说明:FARM 为磁盘内部单帧遥测,无 poh 时间序列;活跃度以'重分配候选数'近似,关联业务影响需结合主机内核日志(dmesg/messages)。",
          "> 数据源:JSON(openSeaChest,最全) 优先,TXT(华为 disktool,约40%字段) 兜底;TXT 来源的盘第2/7类及逐头明细会降级。",
          "> 第3类部分覆盖;第7类 TXT 降级;第8类(SSD)对 HDD 不适用。",
          "> R码定界:依据用户定义《故障根因分类表》(references/root_cause_rules.md);本脚本仅给出 FARM 侧候选与 OS 侧待验清单,",
          "> 最终 R 码由分析人结合 OS/iBMC 日志交叉验证闭环;R5b(盘不可响应)无法采集 FARM,按'先恢复后诊断'流程恢复后复采。"]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description="希捷 FARM(ATA/SATA) 多盘健康分析(8类故障部位)")
    ap.add_argument("path", help="目录:其下按 IP 子目录存放每盘的 FARM json/txt")
    ap.add_argument("--source", choices=["auto", "json", "txt"], default="auto",
                    help="数据源选择:auto=json优先txt兜底(默认) / json / txt")
    ap.add_argument("--json", action="store_true", help="追加机器可读 JSON")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

    disks = discover_disks(args.path, args.source)
    if not disks:
        print("错误:在 %s 未找到 FARM 日志(*_FARM_*.json / *_FARM_disktool_*.txt)" % args.path, file=sys.stderr)
        sys.exit(2)
    results = [analyze_disk(g) for g in disks]
    print(render(args.path, results))
    if args.json:
        print("\n<<<JSON>>>")
        print(json.dumps([{"domain": domain_of(r["summary"].get("rcode", "-"))[0],
                            "scope": domain_of(r["summary"].get("rcode", "-"))[1],
                            "summary": r["summary"], "rcode": r["rc"], "model": r["m"]} for r in results],
                         ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    main()
