#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_sm2.py — 希捷 SM2 / FARM 级遥测日志:多盘健康分析(8 类故障部位)

输入:一个目录,可包含【一块盘】或【一台服务器的多块盘】的 SM2 日志。
脚本递归扫描,按文件名里的序列号(SN)把文件分组成多块盘;每块盘的文件:
  - 整盘级: <SN>_SMART_<ts>_SLog.txt
  - 逐磁头: <SN>_SMART_<ts>_head0.txt ... headN.txt
每个文件是 CSV 时间序列(常见 1000 条记录),首行表头,逗号分隔。

输出:
  1) 机群(服务器)汇总表 —— 每块盘一行,按健康度从差到好排序;
  2) 每块盘的逐类(8 类故障部位)分析 + 逐磁头明细 + 结论与处置。

8 类故障部位(对照标准 SMART;映射与覆盖度见 references/field_reference.md):
  1 盘片表面/坏扇区   2 磁头/读写通道/ECC   3 机械/马达/伺服   4 接口/传输
  5 温度/环境/振动    6 寿命/工况           7 固件/服务区      8 SSD(本类HDD不适用)

关键纪律(踩过的坑):记录按 poh(累计上电计数)排序,poh 最大=最新。多数导出是倒序
(record 0=最新)。趋势一律按 旧->新 解读,否则"持续增长"会被读成"自愈下降",结论反掉。
本脚本统一按 poh 升序计算。

用法:
  python analyze_sm2.py <目录>            # 单盘或多盘都可
  python analyze_sm2.py <目录> --json     # 追加机器可读 JSON
"""

import argparse
import csv
import json
import os
import re
import statistics
import sys

# ---- 已知标记/常量值(见 field_reference.md)----
MARK_FFFF = 65535   # 0xFFFF 满量程/溢出:磁头开路或传感器饱和(故障)
MARK_DEAD = 57005   # 0xDEAD 固件"未校准/无效数据"
MARK_OTF  = 26728   # 0x6868 本类盘 OTFErr 固定常量,非真实计数,忽略

# ---- 阈值(集中在此,换机型可调)----
TEMP_WARN, TEMP_CRIT = 60.0, 70.0
V5_LO, V5_HI = 4.75, 5.25
V12_LO, V12_HI = 11.40, 12.60
RV_WARN, RV_CRIT = 40, 80
HUMID_WARN = 80.0
OUTLIER_HI = 1.20          # 种群相对:> 中位 × 1.20 视为偏高离群
OUTLIER_LO = 0.80          # < 中位 × 0.80 视为偏低离群(用于信号幅度)

SEV_LABEL = {0: "健康", 1: "关注", 2: "退化", 3: "失效"}
COV_FULL, COV_PART, COV_NA = "可分析(≥标准SMART)", "部分可分析", "不适用"


# --------------------------------------------------------------------------- utils
def to_float(x, d=None):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d


def to_int(x, d=None):
    f = to_float(x)
    return int(f) if f is not None else d


def read_csv(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        return [r for r in csv.DictReader(f) if any((v or "").strip() for v in r.values())]


def by_poh(rows):
    """按 poh 升序:索引 0=最旧,末尾=最新。"""
    return sorted(rows, key=lambda r: to_float(r.get("poh"), 0.0))


def cmax(rows, k):
    v = [to_float(r.get(k)) for r in rows]; v = [x for x in v if x is not None]
    return max(v) if v else None


def cmin(rows, k):
    v = [to_float(r.get(k)) for r in rows]; v = [x for x in v if x is not None]
    return min(v) if v else None


def cmean(rows, k, drop_zero=False):
    v = [to_float(r.get(k)) for r in rows]; v = [x for x in v if x is not None]
    if drop_zero:
        v = [x for x in v if x != 0]
    return statistics.mean(v) if v else None


def trend(rows, k):
    seq = [to_float(r.get(k)) for r in rows if to_float(r.get(k)) is not None]
    if len(seq) < 2:
        return (None, None, "n/a")
    o, n = seq[0], seq[-1]
    return (o, n, "grow" if n > o else ("shrink" if n < o else "flat"))


def has_col(rows, k):
    return bool(rows) and k in rows[0]


def family_outliers(values, ratio, direction="hi"):
    """种群相对离群:values=[(idx,val)],返回离群 idx 列表 + 中位。"""
    vals = [v for _, v in values if v is not None]
    if len(vals) < 3:
        return [], None
    med = statistics.median(vals)
    out = []
    for idx, v in values:
        if v is None:
            continue
        if direction == "hi" and med and v > med * ratio:
            out.append(idx)
        if direction == "lo" and med and v < med * ratio:
            out.append(idx)
    return out, med


# --------------------------------------------------------------------------- discover
def discover_disks(root):
    """递归扫描,按 SN 把文件分组成多块盘。返回 {sn: {slog, heads{idx:path}, ts}}。"""
    disks = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if not name.lower().endswith(".txt"):
                continue
            m = re.match(r"(?P<sn>[^_]+)_SMART_(?P<ts>\d{8}T\d{6})_(?P<kind>SLog|head\d+)\.txt$", name, re.I)
            if not m:
                continue
            sn = m.group("sn")
            d = disks.setdefault(sn, {"slog": None, "heads": {}, "ts": m.group("ts")})
            full = os.path.join(dirpath, name)
            if m.group("kind").lower() == "slog":
                d["slog"] = full
            else:
                d["heads"][int(re.search(r"\d+", m.group("kind")).group())] = full
    return disks


# --------------------------------------------------------------------------- per-head
def head_metrics(idx, path):
    rows = by_poh(read_csv(path))
    if not rows:
        return None
    new = rows[-1]
    fafh_col = "fafh_passclr_od" if has_col(rows, "fafh_passclr_od") else (
        "fafh_applied_od" if has_col(rows, "fafh_applied_od") else None)
    h = {"head": idx, "records": len(rows), "fafh_col": fafh_col}
    h["glist_max"] = cmax(rows, "g_list")
    h["glist_new"] = to_int(new.get("g_list"))
    _, _, h["glist_dir"] = trend(rows, "g_list")
    h["vis_rd_err"] = cmax(rows, "vis_rd_err")
    h["hid_rd_err"] = cmax(rows, "hid_rd_err")
    h["init_rd_err"] = cmax(rows, "initial_rd_err")
    h["arre"] = cmax(rows, "arre")
    h["fafh_mean"] = cmean(rows, fafh_col, drop_zero=True) if fafh_col else None
    h["fafh_zero"] = sum(1 for r in rows if to_float(r.get(fafh_col)) == 0) if fafh_col else 0
    h["hres_min"], h["hres_max"] = cmin(rows, "head_resistance"), cmax(rows, "head_resistance")
    h["mr2_min"], h["mr2_max"] = cmin(rows, "mr2_head_resistance"), cmax(rows, "mr2_head_resistance")
    h["iter_mean"] = max(x for x in [cmean(rows, "iterOD"), cmean(rows, "iterMD"), cmean(rows, "iterID")] if x is not None) \
        if any(has_col(rows, c) for c in ("iterOD", "iterMD", "iterID")) else None
    h["amp_mean"] = min(x for x in [cmean(rows, "ampOD"), cmean(rows, "ampMD"), cmean(rows, "ampID")] if x is not None) \
        if any(has_col(rows, c) for c in ("ampOD", "ampMD", "ampID")) else None
    h["oc_max"] = max([x for x in [cmax(rows, "oc_limit4"), cmax(rows, "oc_limit9"), cmax(rows, "oc_limit14")] if x is not None] or [0])
    h["bad_sample"] = cmax(rows, "bad_sample")
    h["berp"] = cmax(rows, "berp_rec_error")
    h["sector_rd_new"] = to_int(new.get("sector_rd"))
    h["sector_wt_new"] = to_int(new.get("sector_wt"))
    # 标记值
    marks = []
    for col in ("head_resistance", "mr2_head_resistance", fafh_col):
        if not col:
            continue
        if cmax(rows, col) == MARK_FFFF or cmin(rows, col) == MARK_FFFF:
            marks.append(f"{col}=0xFFFF")
        if any(to_int(r.get(col)) == MARK_DEAD for r in rows):
            marks.append(f"{col}=0xDEAD")
    h["marks"] = sorted(set(marks))
    return h


# --------------------------------------------------------------------------- 8 categories
def categorize(slog, heads):
    """返回 list[dict(cat, name, coverage, severity, findings[])],并在 heads 上标注 surface/channel 严重度。"""
    cats = []
    fafh_pairs = [(h["head"], h["fafh_mean"]) for h in heads]
    iter_pairs = [(h["head"], h["iter_mean"]) for h in heads]
    amp_pairs = [(h["head"], h["amp_mean"]) for h in heads]
    fafh_out, fafh_med = family_outliers(fafh_pairs, OUTLIER_HI, "hi")
    iter_out, iter_med = family_outliers(iter_pairs, OUTLIER_HI, "hi")
    amp_out, amp_med = family_outliers(amp_pairs, OUTLIER_LO, "lo")

    # ---- 1 盘片表面 / 坏扇区 ----
    f, sev = [], 0
    for h in heads:
        hs = 0
        if h["glist_max"] and h["glist_max"] > 0:
            tip = {"grow": "持续增长(活跃)", "shrink": "下降", "flat": "稳定"}.get(h["glist_dir"], "")
            f.append(f"H{h['head']} g_list 峰值 {int(h['glist_max'])}/最新 {h['glist_new']}({tip})")
            hs = 2 if (h["glist_dir"] == "grow" or (h["glist_new"] or 0) > 0) else 1
        if h["vis_rd_err"] and h["vis_rd_err"] > 0:
            f.append(f"H{h['head']} vis_rd_err(不可恢复读) {int(h['vis_rd_err'])} (应为0)")
            hs = max(hs, 2)
        if h["marks"]:
            hs = max(hs, 3)
        h["surf_sev"] = hs
        sev = max(sev, hs)
    if slog and slog.get("rsvd_zone_scan") and slog["rsvd_zone_scan"] > 0:
        f.append(f"盘级 rsvd_zone_scan_count={slog['rsvd_zone_scan']}")
    cats.append({"cat": 1, "name": "盘片表面/坏扇区", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["全部磁头 g_list=0、无不可恢复读错误"]})

    # ---- 2 磁头 / 读写通道 / ECC ----
    f, sev = [], 0
    for h in heads:
        hs, r = 0, []
        if h["marks"]:
            r.append("标记值 " + ",".join(h["marks"]) + "(磁头开路/无效)"); hs = 3
        if h["head"] in fafh_out and fafh_med:
            pct = (h["fafh_mean"] / fafh_med - 1) * 100
            r.append(f"飞高FAFH {h['fafh_mean']:.0f}>中位{fafh_med:.0f}(+{pct:.0f}%)"); hs = max(hs, 2)
        if h["fafh_zero"] and h["fafh_zero"] > 5:
            r.append(f"FAFH=0 瞬态{h['fafh_zero']}次(TFC中断)"); hs = max(hs, max(1, hs))
        if h["head"] in iter_out and iter_med:
            r.append(f"译码迭代 {h['iter_mean']:.1f}>中位{iter_med:.1f}(低SNR吃力)"); hs = max(hs, 2)
        if h["head"] in amp_out and amp_med:
            r.append(f"读信号幅度 {h['amp_mean']:.0f}<中位{amp_med:.0f}(信号弱)"); hs = max(hs, 2)
        if h["hid_rd_err"] and h["hid_rd_err"] > 0:
            r.append(f"内部恢复读错误 hid_rd_err {int(h['hid_rd_err'])}"); hs = max(hs, 2)
        if h["berp"] and h["berp"] > 0:
            r.append(f"berp_rec_error {int(h['berp'])}"); hs = max(hs, max(1, hs))
        h["chan_sev"] = hs
        if r:
            f.append(f"H{h['head']}: " + ";".join(r))
        sev = max(sev, hs)
    cats.append({"cat": 2, "name": "磁头/读写通道/ECC", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["逐头飞高/MRR/译码迭代/信号幅度均在同族区间,无读错误"]})

    # ---- 3 机械 / 马达 / 伺服 ----
    f, sev = [], 0
    oc_pairs = [(h["head"], float(h["oc_max"] or 0)) for h in heads]
    oc_out, _ = family_outliers(oc_pairs, OUTLIER_HI, "hi")
    nz_oc = [h["head"] for h in heads if (h["oc_max"] or 0) > 0]
    if nz_oc:
        f.append(f"执行器过流限幅触发 oc_limit>0 的磁头: H{', H'.join(map(str, nz_oc))}")
        sev = max(sev, 2 if oc_out else 1)
    if slog and slog.get("motor_power") is not None:
        f.append(f"主轴马达功率 motor_power={slog['motor_power']}")
    if slog and slog.get("power_cycle") is not None:
        f.append(f"上电次数 power_cycle={slog['power_cycle']}")
    cats.append({"cat": 3, "name": "机械/马达/伺服", "coverage": COV_PART, "severity": sev,
                 "findings": f or ["马达功率/伺服/执行器过流无明显异常(注:无spin-up/retry/LUL计数)"]})

    # ---- 4 接口 / 传输 ----
    f, sev = [], 0
    if slog:
        if slog.get("cmd_timeout_new"):
            if slog.get("cmd_timeout_dir") == "grow":
                f.append(f"命令超时(≈SMART188)新发累积 {int(slog['cmd_timeout_old'] or 0)}->{int(slog['cmd_timeout_new'])}")
                sev = max(sev, 2)
            else:
                f.append(f"命令超时当前 {int(slog['cmd_timeout_new'])}")
                sev = max(sev, 1)
        if (slog.get("host_reset") or 0) > 0 or (slog.get("hard_reset") or 0) > 0:
            f.append(f"复位计数 host={slog.get('host_reset')} hard={slog.get('hard_reset')}")
            sev = max(sev, 1)
    cats.append({"cat": 4, "name": "接口/传输", "coverage": COV_PART, "severity": sev,
                 "findings": f or ["命令超时为0、无主机/硬复位(SAS盘无UDMA CRC项)"]})

    # ---- 5 温度 / 环境 / 振动 ----
    f, sev = [], 0
    if slog:
        if slog.get("temp_max") is not None:
            if slog["temp_max"] >= TEMP_CRIT:
                f.append(f"温度过高 max {slog['temp_max']:.1f}℃"); sev = max(sev, 2)
            elif slog["temp_max"] >= TEMP_WARN:
                f.append(f"温度偏高 max {slog['temp_max']:.1f}℃"); sev = max(sev, 1)
            else:
                f.append(f"温度 {slog.get('temp_min')}~{slog['temp_max']}℃ 正常")
        if slog.get("rv_max") is not None and slog["rv_max"] >= RV_WARN:
            f.append(f"旋转振动偏高 rv_max {slog['rv_max']}"); sev = max(sev, 2 if slog['rv_max'] >= RV_CRIT else 1)
        if slog.get("humid_max") is not None and slog["humid_max"] >= HUMID_WARN:
            f.append(f"湿度偏高 {slog['humid_max']}%"); sev = max(sev, 1)
    cats.append({"cat": 5, "name": "温度/环境/振动", "coverage": COV_FULL, "severity": sev,
                 "findings": f or ["温度/振动/湿度均正常"]})

    # ---- 6 寿命 / 工况(信息为主)----
    f = []
    if slog:
        f.append(f"上电计数 poh={slog.get('poh')}  上电次数={slog.get('power_cycle')}")
    f.append(f"全盘最新累计读扇区≈{int(slog.get('sum_sector_rd') or 0)}  写扇区≈{int(slog.get('sum_sector_wt') or 0)}")
    cats.append({"cat": 6, "name": "寿命/工况", "coverage": COV_FULL, "severity": 0, "findings": f})

    # ---- 7 固件 / 服务区 ----
    f, sev = [], 0
    tot_glist = sum(int(h["glist_max"] or 0) for h in heads)
    if slog and slog.get("cmd_timeout_dir") == "grow" and tot_glist > 0:
        f.append(f"命令超时增长 且 逐头 g_list 合计 {tot_glist} → 可能服务区/转换表压力(SMART188 深层指向)")
        sev = max(sev, 2)
    if slog and slog.get("rsvd_zone_scan") and slog["rsvd_zone_scan"] > 0:
        f.append(f"保留区扫描 rsvd_zone_scan_count={slog['rsvd_zone_scan']}")
        sev = max(sev, 1)
    if slog and slog.get("bms_unlock") not in (None, 0, "0"):
        f.append(f"bms_smart_unlock_status={slog['bms_unlock']}")
    f.append("注:本类 CSV 不含离散的服务区/translator/固件assert事件记录,需原厂工具解析深度事件日志")
    cats.append({"cat": 7, "name": "固件/服务区", "coverage": COV_PART, "severity": sev, "findings": f})

    # ---- 8 SSD ----
    cats.append({"cat": 8, "name": "SSD磨损(本盘为HDD)", "coverage": COV_NA, "severity": 0,
                 "findings": ["本盘有磁头/飞高/主轴,判定为机械硬盘,SSD 磨损类不适用"]})
    return cats, fafh_med


def classify(slog, heads, cats):
    bad = [h for h in heads if max(h.get("surf_sev", 0), h.get("chan_sev", 0)) >= 2]
    marked = [h for h in heads if h.get("marks")]
    tfc_fail = [h for h in heads if h.get("fafh_zero", 0) > 5]
    ct_new = (slog or {}).get("cmd_timeout_new") or 0
    ct_grow = (slog or {}).get("cmd_timeout_dir") == "grow"

    top = max((c for c in cats if c["cat"] != 8), key=lambda c: c["severity"])
    if len(marked) >= 2 or (len(tfc_fail) >= 2 and ct_new > 0 and ct_grow):
        mode = "固件死锁/多磁头TFC失效"; verdict = "失效:盘可能无响应"; sev = 3
        action = "带外(IPMI)重启恢复;延寿低,建议换盘并排查固件"
    elif len(bad) >= 2:
        mode = "多磁头介质退化"; verdict = "严重:多盘面退化"; sev = 3
        action = "抢救数据+xfs_repair;倾向换盘"
    elif len(bad) == 1:
        h = bad[0]
        active = h["glist_dir"] == "grow" or (h["glist_new"] or 0) > 0 or (h["vis_rd_err"] or 0) > 0 or ct_new > 0
        mode = f"单磁头退化(H{h['head']})"; sev = 2
        if active:
            verdict = f"退化进行中:仅 H{h['head']} 异常且仍恶化"
            action = f"RAID冗余下优先磁头级降级禁用 H{h['head']}(损约{100.0/max(len(heads),1):.1f}%)或换盘"
        else:
            verdict = f"单头退化但暂稳:仅 H{h['head']} 异常"
            action = f"强化监控 H{h['head']} g_list/FAFH;RAID 兜底可中期留用"
    elif top["severity"] >= 2:
        mode = f"{top['name']}异常"; verdict = f"严重:{top['name']}"; sev = 2
        action = "按该类别处置(见逐类明细)"
    elif any(c["severity"] == 1 for c in cats):
        mode = "轻度异常/早期预警"; verdict = "亚健康:有关注项"; sev = 1
        action = "纳入加密监控,关注趋势"
    else:
        mode = "无异常"; verdict = "健康"; sev = 0
        action = "常规监控"
    return {"mode": mode, "verdict": verdict, "severity": sev, "action": action,
            "bad_heads": [h["head"] for h in bad],
            "top_cat": f"{top['cat']} {top['name']}" if top["severity"] > 0 else "-"}


# --------------------------------------------------------------------------- per-disk
def analyze_disk(sn, files):
    slog = None
    if files["slog"]:
        rows = by_poh(read_csv(files["slog"]))
        if rows:
            new = rows[-1]
            o, n, d = trend(rows, "command_timeout_9")
            slog = {
                "sn": new.get("serial_number") or sn, "firmware": new.get("firmware"),
                "head_cnt": to_int(new.get("head_cnt")), "sector_size": to_int(new.get("sector_size")),
                "poh": new.get("poh"), "power_cycle": to_int(new.get("power_cycle_cnt")),
                "host_reset": to_int(new.get("host_reset")), "hard_reset": to_int(new.get("hard_reset")),
                "temp_min": cmin(rows, "temperature"), "temp_max": cmax(rows, "temperature"),
                "v5_min": cmin(rows, "volt_5"), "v5_max": cmax(rows, "volt_5"),
                "v12_min": cmin(rows, "volt_12"), "v12_max": cmax(rows, "volt_12"),
                "rv_max": cmax(rows, "rv_max") or cmax(rows, "rv"),
                "humid_max": cmax(rows, "humidity_max") or cmax(rows, "humidity"),
                "motor_power": (cmax(rows, "motor_power")),
                "rsvd_zone_scan": cmax(rows, "rsvd_zone_scan_count"),
                "bms_unlock": new.get("bms_smart_unlock_status"),
                "cmd_timeout_old": o, "cmd_timeout_new": n, "cmd_timeout_dir": d,
            }
    heads = [head_metrics(i, files["heads"][i]) for i in sorted(files["heads"])]
    heads = [h for h in heads if h]
    if slog is None:
        slog = {"sn": sn, "head_cnt": len(heads)}
    # 全盘读写扇区合计(供 cat6)
    slog["sum_sector_rd"] = sum(int(h["sector_rd_new"] or 0) for h in heads)
    slog["sum_sector_wt"] = sum(int(h["sector_wt_new"] or 0) for h in heads)

    cats, fafh_med = categorize(slog, heads)
    summary = classify(slog, heads, cats)
    return {"sn": slog.get("sn"), "slog": slog, "heads": heads, "cats": cats,
            "fafh_med": fafh_med, "summary": summary, "ts": files.get("ts")}


# --------------------------------------------------------------------------- render
def render(root, results):
    L = ["# SM2 多盘健康分析报告", "", f"扫描目录: `{root}`  共发现 **{len(results)}** 块盘", ""]
    # 机群汇总(差->好)
    order = sorted(results, key=lambda r: (-r["summary"]["severity"], r["sn"]))
    L += ["## 机群汇总(按健康度 差→好)", "",
          "| 盘SN | 固件 | 磁头 | 总评级 | 故障模式 | 主要问题类别 | 受影响磁头 | 处置 |",
          "|---|---|---|---|---|---|---|---|"]
    for r in order:
        s, sm = r["slog"], r["summary"]
        bh = ("H" + ", H".join(map(str, sm["bad_heads"]))) if sm["bad_heads"] else "-"
        L.append(f"| {r['sn']} | {s.get('firmware','-')} | {s.get('head_cnt','-')} | "
                 f"**{SEV_LABEL[sm['severity']]}** | {sm['mode']} | {sm['top_cat']} | {bh} | {sm['action']} |")
    L.append("")

    for r in order:
        s, sm = r["slog"], r["summary"]
        L += ["---", "", f"## 盘 {r['sn']}  ——  {SEV_LABEL[sm['severity']]} / {sm['mode']}", ""]
        L.append(f"- 固件 {s.get('firmware')}  磁头 {s.get('head_cnt')}  扇区 {s.get('sector_size')}B  "
                 f"上电计数 {s.get('poh')}  上电次数 {s.get('power_cycle')}")
        L.append(f"- 温度 {s.get('temp_min')}~{s.get('temp_max')}℃  "
                 f"5V {s.get('v5_min')}~{s.get('v5_max')}  12V {s.get('v12_min')}~{s.get('v12_max')}  "
                 f"rv_max {s.get('rv_max')}  命令超时 {s.get('cmd_timeout_old')}→{s.get('cmd_timeout_new')}({s.get('cmd_timeout_dir')})")
        # 8 类表
        L += ["", "### 逐类(故障部位)分析", "",
              "| # | 故障部位 | 覆盖度 | 评级 | 关键发现 |", "|---|---|---|---|---|"]
        for c in r["cats"]:
            L.append(f"| {c['cat']} | {c['name']} | {c['coverage']} | {SEV_LABEL[c['severity']]} | "
                     f"{'；'.join(c['findings'])} |")
        # 逐头明细表
        L += ["", "### 逐磁头明细", "",
              "| Head | 表面 | 通道 | g_list(峰/新/向) | vis_rd | hid_rd | FAFH | 迭代 | HRes | 标记 |",
              "|---|---|---|---|---|---|---|---|---|---|"]
        for h in r["heads"]:
            fafh = ("%.0f" % h["fafh_mean"]) if h["fafh_mean"] is not None else "-"
            it = ("%.1f" % h["iter_mean"]) if h["iter_mean"] is not None else "-"
            L.append(f"| H{h['head']} | {SEV_LABEL[h.get('surf_sev',0)]} | {SEV_LABEL[h.get('chan_sev',0)]} | "
                     f"{int(h['glist_max'] or 0)}/{h['glist_new']}/{h['glist_dir']} | {int(h['vis_rd_err'] or 0)} | "
                     f"{int(h['hid_rd_err'] or 0)} | {fafh} | {it} | "
                     f"{h['hres_min']}-{h['hres_max']} | {','.join(h['marks']) if h['marks'] else '-'} |")
        if r["fafh_med"]:
            L.append(f"\n_FAFH 同族中位≈{r['fafh_med']:.0f};离群阈值=中位×{OUTLIER_HI}_")
        L += ["", "### 结论", f"- 故障模式: **{sm['mode']}**  健康判定: **{sm['verdict']}**",
              (f"- 受影响磁头: H{', H'.join(map(str, sm['bad_heads']))}" if sm["bad_heads"] else "- 受影响磁头: 无"),
              f"- 处理建议: {sm['action']}"]
    L += ["", "> 说明:SM2 仅反映盘体内部遥测,不含文件系统/业务影响;关联 I/O 错误/卷宕机需结合主机内核日志(dmesg/messages)。",
          "> 第3/4/7类为部分覆盖(无 spin-up/retry/LUL、UDMA CRC、离散服务区事件);第8类(SSD)对 HDD 不适用。"]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description="希捷 SM2/FARM 多盘健康分析(8类故障部位)")
    ap.add_argument("path", help="目录:单盘 sm2_log,或一台服务器多盘的父目录")
    ap.add_argument("--json", action="store_true", help="追加机器可读 JSON")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

    disks = discover_disks(args.path)
    if not disks:
        print(f"错误:在 {args.path} 未找到 SM2 日志(*_SMART_*_SLog.txt / _headN.txt)", file=sys.stderr)
        sys.exit(2)
    results = [analyze_disk(sn, files) for sn, files in disks.items()]
    print(render(args.path, results))
    if args.json:
        print("\n<<<JSON>>>")
        print(json.dumps(results, ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    main()
