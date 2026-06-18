#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Write timing.json / eval_metadata.json / grading.json for iteration-1 runs."""
import json, os

IT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "iteration-1")

# (eval_id, prompt, timing per config) ; durations(ms)/tokens from task notifications
TIMING = {
    "full-analysis":  {"with_skill": (48353, 242253), "without_skill": (43449, 245123)},
    "keep-or-replace":{"with_skill": (37088, 106215), "without_skill": (40492, 224375)},
    "which-head":     {"with_skill": (27368,  48912), "without_skill": (26484,  81741)},
}

PROMPTS = {
    "full-analysis":  "帮我分析下这块希捷盘的 SM2 日志，判断磁盘健康情况、定位是哪个磁头有问题，给出根因和处理建议。日志目录在 C:\\temp\\sm2_eval\\sm2_log",
    "keep-or-replace":"C:\\temp\\sm2_eval\\sm2_log 这块盘的日志你看下，它现在还能继续用吗？需要换盘吗？为什么？",
    "which-head":     "C:\\temp\\sm2_eval\\sm2_log 这批 per-head 日志里，哪个磁头的飞高(FAFH)和增长缺陷表(g_list)异常？只要结论。",
}

# Assertions per eval (text). which-head is a "conclusion-only" task -> fewer.
ASSERT = {
    "full-analysis": [
        "定位 H10 为唯一异常磁头",
        "报告 H10 的 g_list 达到约 1100",
        "时间方向正确：判定为增长/活跃退化，而非自愈下降",
        "指出其余 17 个磁头健康（种群相对法）",
        "正确处理 OTFErr=26728 为常量并忽略，未把它当错误计数",
        "给出磁头级降级或换盘建议（非'健康可继续用'）",
        "识别盘身份 WYD0N5WX / 18磁头 / Mach.2 双致动器",
    ],
    "keep-or-replace": [
        "结论为不能简单留用 / 需降级或换盘",
        "定位 H10 为退化磁头",
        "时间方向正确：g_list 0->1100 增长（活跃），未误判为已自愈到0",
        "依据包含 vis_rd_err>0 或命令超时等活跃退化证据",
    ],
    "which-head": [
        "指出异常磁头为 H10",
        "FAFH 较同族偏高（约 +30%）",
        "g_list 达到约 1100",
        "时间方向正确：增长而非下降",
    ],
}

# Grading: per eval -> per config -> list of (passed, evidence) aligned to ASSERT order
GRADES = {
 "full-analysis": {
   "with_skill":    [(True,"明确 H10 唯一离群"),(True,"g_list 1100"),(True,"按 poh 升序确认 0->1100 增长，非自愈"),(True,"其余17头干净"),(True,"脚本/报告将 OTFErr=26728 标为常量忽略"),(True,"建议磁头级降级或换盘"),(True,"WYD0N5WX/18磁头/Mach.2")],
   "without_skill": [(True,"定位 H10"),(True,"g_list 1100"),(True,"判定仍在攀升未收敛"),(True,"其余17头读错误/缺陷近0"),(True,"剔除恒定字段 OTFErr=26728"),(True,"建议更换/RMA"),(False,"提到18磁头但未点明 Mach.2 双致动器；且把逐记录读错误当累计求和(48302)，有数值口径偏差")],
 },
 "keep-or-replace": {
   "with_skill":    [(True,"必须降级/换盘"),(True,"H10"),(True,"复核 poh 后确认 0->1100 增长"),(True,"vis_rd_err=181 且命令超时 0->6")],
   "without_skill": [(True,"结论为更换"),(True,"head10"),(True,"0->1100 单调增长"),(False,"误称 command_timeout 未累积(实为 0->6 累积)，并以 g_list'撞固件上限'为主要推断")],
 },
 "which-head": {
   "with_skill":    [(True,"H10"),(True,"+31% 超离群阈值"),(True,"g_list 1100"),(True,"按 poh 升序校正为增长")],
   "without_skill": [(True,"head10"),(True,"均值~995 远高于同族"),(True,"0->1100"),(True,"持续累积/接近饱和")],
 },
}

def main():
    for eid, cfgs in TIMING.items():
        # eval_metadata.json
        meta = {"eval_id": eid, "eval_name": eid, "prompt": PROMPTS[eid],
                "assertions": ASSERT[eid]}
        with open(os.path.join(IT, f"eval-{eid}", "eval_metadata.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        for cfg, (tok, dur) in cfgs.items():
            rd = os.path.join(IT, f"eval-{eid}", cfg)
            with open(os.path.join(rd, "timing.json"), "w", encoding="utf-8") as f:
                json.dump({"total_tokens": tok, "duration_ms": dur,
                           "total_duration_seconds": round(dur/1000, 1)}, f, indent=2)
            exps = [{"text": ASSERT[eid][i], "passed": p, "evidence": ev}
                    for i, (p, ev) in enumerate(GRADES[eid][cfg])]
            passed = sum(1 for e in exps if e["passed"])
            with open(os.path.join(rd, "grading.json"), "w", encoding="utf-8") as f:
                json.dump({"eval_id": eid, "config": cfg, "expectations": exps,
                           "passed": passed, "total": len(exps)}, f, ensure_ascii=False, indent=2)
    print("wrote eval_metadata/timing/grading for", len(TIMING), "evals")

if __name__ == "__main__":
    main()
