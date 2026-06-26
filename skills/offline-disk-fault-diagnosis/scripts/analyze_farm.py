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

8 类故障部位(映射与覆盖度见 references/field_reference.md):
  1 盘片表面/坏扇区   2 磁头/读写通道/ECC   3 机械/马达/伺服   4 接口/传输
  5 温度/环境/振动    6 寿命/工况           7 固件/服务区      8 SSD(本类HDD不适用)

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

# ---- 已知标记/常量值(见 field_reference.md)----
MARK_FFFF = 65535   # 0xFFFF 满量程/溢出:磁头开路或传感器饱和(故障)
MARK_DEAD = 57005   # 0xDEAD 固件"未校准/无效数据"

# ---- 阈值(集中在此,换机型可调)----
TEMP_WARN, TEMP_CRIT = 50.0, 60.0       # FARM 给出 Specified Max=60℃,故 50 关注 / 60 临界
SHOCK_WARN = 100000                     # Over-Limit Shock 事件累计(经验关注线)
HUMID_WARN = 80.0
CTO_WARN = 1                            # 命令超时累计 >=1 即关注(单帧无趋势,保守取关注)
OUTLIER_HI = 2.00          # 种群相对:abs(delta) > 中位 × 2.0 视为偏高离群(FAFH 飞高偏移用)
HEAD_REALLOC_WARN = 1      # 逐头重分配 >=1 即记为坏道

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
def discover_disks(root, source):
    """扫描 root,按目录(IP)+SN 分盘,选定每盘的数据源文件。
    返回 list[dict(sn, dirpath, json, txt, use, ip)]。use ∈ {'json','txt'}。"""
    pat = re.compile(
        r"(?P<sn>[^_/\\]+)_FARM_(?:(?P<disktool>disktool)_)?"
        r"(?P<ts>\d{8}T\d{6})_(?P<ip>[\d.]+)_(?P<dev>[^.]+)\.(?P<ext>json|txt)$",
        re.I)
    # group by (dirpath, sn)
    groups = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            m = pat.match(name)
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
        "h_dos_refresh": [to_int(x) for x in hf.get("DOS Write Refresh Count", [None] * n)],
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
        # a "#Title" with no value but per-head rows follow (e.g. fly height delta)
        mt = re.match(r"^#\s*(.+?)\s*$", ln)
        if mt and ("per head" in mt.group(1).lower() or "by head" in mt.group(1).lower()):
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
        "h_dos_refresh": [to_int(x) for x in (harr("DOS Write Refresh") or [None] * n)],
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
    return cats, surf, chan, fafh_med


def classify(m, cats, surf, chan):
    n = m["heads"]
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
            "bad_heads": bad, "active": active, "weight": weight,
            "top_cat": ("%d %s" % (top["cat"], top["name"])) if top["severity"] > 0 else "-"}


# --------------------------------------------------------------------------- per-disk
def analyze_disk(g):
    m = load_json(g["json"]) if g["use"] == "json" else load_txt(g["txt"])
    m["sn"] = m.get("sn") or g["sn"]
    m["ip"] = g["ip"]
    cats, surf, chan, fafh_med = categorize(m)
    summary = classify(m, cats, surf, chan)
    return {"m": m, "cats": cats, "surf": surf, "chan": chan,
            "fafh_med": fafh_med, "summary": summary}


# --------------------------------------------------------------------------- render
def render(root, results):
    L = ["# 希捷 FARM 多盘健康分析报告", "",
         "扫描目录: `%s`  共发现 **%d** 块盘" % (root, len(results)), ""]
    order = sorted(results, key=lambda r: (-r["summary"]["severity"], -r["summary"]["weight"], r["m"]["sn"]))
    L += ["## 机群汇总(按健康度 差→好)", "",
          "| IP | 盘SN | 型号 | 固件 | 磁头 | 数据源 | 总评级 | 故障模式 | 主要类别 | 受影响磁头 | 处置 |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in order:
        m, sm = r["m"], r["summary"]
        bh = ("H" + ", H".join(map(str, sm["bad_heads"]))) if sm["bad_heads"] else "-"
        L.append("| %s | %s | %s | %s | %s | %s | **%s** | %s | %s | %s | %s |" % (
            m.get("ip", "-"), m["sn"], m.get("model") or "-", m.get("firmware") or "-",
            m["heads"], m["source"], SEV_LABEL[sm["severity"]], sm["mode"],
            sm["top_cat"], bh, sm["action"]))
    L.append("")

    for r in order:
        m, sm = r["m"], r["summary"]
        mach2 = "  [Mach.2双致动器]" if m["heads"] == 18 else ""
        L += ["---", "", "## 盘 %s (IP %s) —— %s / %s%s" % (
            m["sn"], m.get("ip", "-"), SEV_LABEL[sm["severity"]], sm["mode"], mach2), ""]
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
        if any(v is not None for v in m["h_realloc"]) or any(v is not None for v in m["h_fafh_od"]):
            L += ["| Head | 表面 | 通道 | 重分配 | 候选 | 不可恢复读(uniq) | FAFH(O/M/I) | MRR | DOS刷新 | TMD |",
                  "|---|---|---|---|---|---|---|---|---|---|"]
            for i in range(m["heads"]):
                fafh = "%s/%s/%s" % (m["h_fafh_od"][i], m["h_fafh_md"][i], m["h_fafh_id"][i])
                L.append("| H%d | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                    i, SEV_LABEL[r["surf"][i]], SEV_LABEL[r["chan"][i]],
                    m["h_realloc"][i] if m["h_realloc"][i] is not None else "-",
                    m["h_cand"][i] if m["h_cand"][i] is not None else "-",
                    m["h_cum_uniq"][i] if m["h_cum_uniq"][i] is not None else "-",
                    fafh, m["h_mrr"][i] if m["h_mrr"][i] is not None else "-",
                    m["h_dos_refresh"][i] if m["h_dos_refresh"][i] is not None else "-",
                    m["h_tmd"][i] if m["h_tmd"][i] is not None else "-"))
            if r["fafh_med"]:
                L.append("\n_FAFH 同族中位偏移≈%.0f;离群阈值=中位×%.1f_" % (r["fafh_med"], OUTLIER_HI))
        else:
            L.append("_本数据源无逐头明细(TXT 仅含部分逐头块);逐头定位见类1发现_")

        L += ["", "### 结论",
              "- 故障模式: **%s**  健康判定: **%s**  活跃度: %s" % (
                  sm["mode"], sm["verdict"], "退化进行中" if sm["active"] else "暂稳/无活跃坏道"),
              ("- 受影响磁头: H%s" % ", H".join(map(str, sm["bad_heads"])) if sm["bad_heads"] else "- 受影响磁头: 无(或未定位到头)"),
              "- 处理建议: %s" % sm["action"]]

    L += ["", "> 说明:FARM 为磁盘内部单帧遥测,无 poh 时间序列;活跃度以'重分配候选数'近似,关联业务影响需结合主机内核日志(dmesg/messages)。",
          "> 数据源:JSON(openSeaChest,最全) 优先,TXT(华为 disktool,约40%字段) 兜底;TXT 来源的盘第2/7类及逐头明细会降级。",
          "> 第3类部分覆盖;第7类 TXT 降级;第8类(SSD)对 HDD 不适用。"]
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
        print(json.dumps([{"summary": r["summary"], "model": r["m"]} for r in results],
                         ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    main()
