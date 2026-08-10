import type { OutputLanguage } from "../config/types"

/**
 * 伏羲提示词中「已知问题关联检索」相关片段（神农 opt-in）。
 *
 * 设计要点（与旧版 buildFuxiPlanGeneration 一致）：神农未启用时，这些片段**全部塌缩为空串**，
 * 伏羲提示词里不出现任何神农/知识库字样，完全按原流程跑；启用时才把
 * 「第一·五步 + 门禁 + 第五步提示 + Kuafu 交接段 + diag-0 Todo」一并注入。
 *
 * 占位符定义在 prompts/fuxi.md 与 fuxi.en.md 中，由 prompt-loader 做替换。
 */

export const KNOWN_ISSUE_PLACEHOLDERS = [
  "KNOWN_ISSUE_LOOKUP",
  "KNOWN_ISSUE_HINT",
  "KNOWN_ISSUE_HANDOFF_TASKLINE",
  "KNOWN_ISSUE_HANDOFF_NOTE",
  "KNOWN_ISSUE_TODO",
] as const

export type KnownIssuePlaceholder = (typeof KNOWN_ISSUE_PLACEHOLDERS)[number]

/** 第一·五步：已知问题关联检索（中文）。 */
const LOOKUP_ZH = `
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  **第一·五步：已知问题关联检索 (Known-Issue Lookup) —— 必做前置证据采集**

  完成第一步分类后，**立即**调用已知问题分析子 Agent 检索知识库中"已处理过的相似案例"，**随后由你（伏羲）读取案例文件、从案例正文中提炼出历史命中的故障模式**，作为后续推断的证据输入。**此步骤在第二~五步之前完成，其产出供后续步骤参考。**

  - **第 1 动作 — 调用神农检索**：创建神农 (Shennong) 子 Agent 进行检索：
    \`task(subagent_type="shennong", run_in_background=false, prompt="针对故障画像（现象/故障模式/组件/错误码/时间窗口/关键日志：{填入已采集到的信息}）检索知识库中已处理过的相似案例，回传命中案例文件路径 cases_file 以及每条案例的 id 与名称列表。")\`
  - **神农的返回契约（重要）**：神农**只回传** \`cases_file\`（命中案例**原文**落盘的 markdown 文件**绝对路径**）+ 每条命中案例的 \`id\` 与 \`name\`（成对的案例 id 列表与案例名列表）；**它不归纳、也不回传"故障模式"**。案例正文（含现象/调用栈/错误码/根因等）在 \`cases_file\` 文件里，**不在神农的回复文本中**。
  - **第 2 动作 — 读取案例文件并提炼故障模式（本步骤的关键）**：
    - 若神农回传的 \`cases_file\` **非空**：你**必须用 \`Read\` 工具读取该文件**（这是 1.4 故障模式构建阶段、为提炼故障模式而读，属本阶段**唯一被允许**读取的文件；与 1.1 场景识别阶段"严禁打开日志/读取本地文件"是不同阶段、不冲突）。
    - 从案例正文（各案例的 \`content\` / \`content_after_preprocess\`）中**提炼出每个相关案例对应的【故障模式】（组件 + 现象）**，与当前故障画像比对，得到一份"**历史命中的故障模式列表**"。
    - **只为提炼故障模式而读**：**禁止**把案例正文原文成段复制/内联进《诊断排查方案》的任何章节；方案里只出现你提炼后的故障模式名 + 指向 \`cases_file\` 的指针。
  - **结果用途（关键 —— 提炼出的历史故障模式须实质参与本次故障模式集构建）**：
    把你从 \`cases_file\` 提炼出的【历史故障模式】视为与本次推断**同等的「证据级输入」**，按下列路径**合并进**第 4 节故障模式列表（而非仅作事后印证）：

    - **路径 A（用户已明确给出故障模式 → 触发第三步短路）**：
      故障模式列表**仍以用户给出的为准**，知识库**不得新增、删除或拆分**用户给出的模式。
      但若命中案例指向**同一故障模式的不同子场景 / 触发条件**，将其作为该 task 的取证侧重写入对应 \`known_issue_refs\`；**不改变模式条目本身**。

    - **路径 B（仅故障现象 → 进入第五步假设推断）**：
      **优先用命中案例的历史故障模式直接组成候选集**，再用常见模式补足。即历史故障模式不是"候选之一"，而是"**首选来源**"——有几个相关历史模式就**先放几个**，与推断结果**合并去重**后仍受 **Top 3 上限**约束。

    - **路径 C（与第二步 \`fault-model\` 关联补齐交叉）**：
      命中案例的故障模式与 \`fault-model\` 关联补齐结果**取并集（去重）**，共同决定最终列表；二者相互印证，不互相删减。
  - **写入任务元数据（写指针 + 你提炼的关联，不内联正文）**：\`cases_file\` 是神农回传的案例原文文件绝对路径，\`case_ids\`/\`case_names\` 是案例的 id 与名称列表。你已在第 2 动作读过该文件用于提炼故障模式，但**禁止**把案例正文成段写进方案；元数据里只放**指针 + 案例 id + 案例名**，供下游 Kuafu 再读正文。按 \`failure_mode\` 对应关系，写入第 5 节任务元数据中对应 task 的 \`known_issue_refs\` 字段：
    - 形如 \`{ "cases_file": "<神农给的绝对路径，逐字原样>", "case_ids": ["<与该 failure_mode 相关的案例 id>", ...], "case_names": ["<对应案例名>", ...] }\`。
    - \`cases_file\` 对同一次检索的所有 task 相同；\`case_ids\` 与 \`case_names\` 各 task 只挑与自己 \`failure_mode\` 相关的案例，且**一一对应、顺序一致**（第 k 个 id 对应第 k 个 name）。
    - 某个 task 无相关历史案例时，**省略**其 \`known_issue_refs\` 字段（不写空对象）。
    - 该字段是**历史参考指针**，会经 Dayu 透传给 Kuafu（Kuafu 再读 \`cases_file\` 正文）；**严禁**把案例当作本次诊断的根因结论写入方案其他章节。
  - **底线（不可破）**：历史故障模式虽实质参与构建（路径 B/C），但**不改变**第三步的强制短路规则——用户已明确给出故障模式时（路径 A）仍以用户为准，历史案例**不得**用于派生子模式、覆盖用户判定或将列表强行扩展超过 Top 3 上限；**一个故障模式仍只对应一个 task**，不得因命中多个案例而拆分任务。
  - **优雅降级**：若神农返回"无相关案例 / 知识库不可用"，照常进入第二步，按原流程推断（所有 task 省略 \`known_issue_refs\`），不要中断、不要报错、不要因此反复追问用户。

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⛔️ **【进入第二步前的强制门禁 - 不可跳过】**

  在你准备进入"第二步：关联规则补齐"之前，**必须**先在心中明确回答下面三问，任一不满足都**禁止**进入第二步：

  1. **我本轮是否已真正调用过神农子 Agent（\`task(subagent_type="shennong", ...)\`）？**
     - 若**从未调用** → 这是**违规跳过**，立即回到第一·五步先调用神农，**不得**直接进入第二步、更不得假设"无命中"。
  2. **神农返回的 \`cases_file\` 是空还是非空？**
     - 非空但我**尚未用 \`Read\` 读取** → 立即 \`Read\` 并完成故障模式提炼后，再进入第二步。
  3. **"无命中 / 知识库不可用"这个结论，是否来自神农的真实返回，而不是我跳过检索后的默认假设？**
     - 若是我自己跳过得出的"无命中" → 视为违规，回到第 1 问。

  **唯一放行条件**：① 已真实调用神农，且 ②（\`cases_file\` 为空/不可用）或（已 \`Read\` 并完成提炼）二者之一成立。满足后方可进入第二步。
`

const HINT_ZH =
  "，以及**第一·五步已知问题关联检索返回的历史故障模式**（若检索到相关历史案例，**先用这些命中的历史故障模式直接组成候选集**——它们是首选来源而非候选之一，再用下列常见模式补足到 ≤ Top 3，与推断结果合并去重；无结果或不可用则退化为纯推断）"

const HANDOFF_TASKLINE_ZH =
  "[KNOWN-ISSUE]: {对应 task 的 known_issue_refs.cases_file 绝对路径 + case_ids + case_names；无则写“无”}。[KNOWN-ISSUE-策略]: 若上面为“无”→ 按常规流程执行（优先检索调用相关 skill）；若非“无”→ **先用 Read 读取该 cases_file（历史案例原文，全文参考）**，对照当前故障现象判断能否据此快速定位/验证根因，可据此优先取证；**若历史案例不足以定位，再走常规 skill 检索流程**。无论哪种，历史案例都只是参考，最终结论必须有本次实际取证支撑。"

const HANDOFF_NOTE_ZH = `
> **\`[KNOWN-ISSUE]\` 段说明**：若对应 task 的 \`known_issue_refs\` 非空，把其中的 \`cases_file\` 绝对路径与 \`case_names\` 注入此段；Kuafu 应**先 Read cases_file 参考历史案例尝试快速诊断，不足时再调 skill**。历史案例是**参考而非结论**，仍需实际取证验证。为空时 Kuafu 按常规流程（优先 skill 检索）执行。
`

const TODO_ZH =
  '\n  { id: "diag-0", content: "调用神农检索知识库 + Read cases_file 提炼历史故障模式（第一·五步，无知识库时即降级跳过）", status: "pending" },'

/** 第一·五步：已知问题关联检索（英文）。 */
const LOOKUP_EN = `
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  **Step 1.5: Known-Issue Lookup — mandatory up-front evidence gathering**

  Right after Step 1 classification, **immediately** call the known-issue analysis sub-agent to retrieve "similar cases already handled" from the knowledge base. **Then you (Fuxi) read the case file and distill the historically hit failure modes from the case bodies**, as evidence input for the later inference. **This step completes before Steps 2–5, and its output feeds them.**

  - **Action 1 — call Shennong**: create the Shennong sub-agent to retrieve:
    \`task(subagent_type="shennong", run_in_background=false, prompt="For this fault profile (symptom / failure mode / component / error code / time window / key logs: {fill in what has been gathered}), retrieve similar already-handled cases from the knowledge base and return the hit case file path cases_file plus the id and name of each case.")\`
  - **Shennong's return contract (important)**: Shennong returns **only** \`cases_file\` (the **absolute path** of the markdown file holding the hit cases' **original bodies**) + each hit case's \`id\` and \`name\` (paired id/name lists). **It does not summarize and does not return "failure modes".** The case bodies (symptoms, stacks, error codes, root causes) are in the \`cases_file\`, **not in Shennong's reply text**.
  - **Action 2 — read the case file and distill failure modes (the crux of this step)**:
    - If the \`cases_file\` returned by Shennong is **non-empty**: you **must read that file with the \`Read\` tool** (this is the 1.4 failure-mode construction stage, reading for the sole purpose of distilling failure modes — the **only** file allowed to be read in this stage; it is a different stage from 1.1 scenario identification where opening logs / reading local files is forbidden, so there is no conflict).
    - From the case bodies (each case's \`content\` / \`content_after_preprocess\`), **distill the [failure mode] (component + symptom) for each relevant case**, compare against the current fault profile, and produce a "**list of historically hit failure modes**".
    - **Read only to distill failure modes**: it is **forbidden** to copy/inline case bodies verbatim into any section of the Diagnostic Plan; the plan carries only your distilled failure-mode names + a pointer to \`cases_file\`.
  - **Use of the result (key — the distilled historical failure modes must substantively participate in building this run's failure-mode set)**:
    Treat the [historical failure modes] you distilled from \`cases_file\` as an **evidence-grade input equal to** this run's inference, and **merge** them into the Section 4 failure-mode list via the paths below (not merely as after-the-fact corroboration):

    - **Path A (user already gave the failure mode → Step 3 short-circuit)**:
      The failure-mode list **still follows the user**; the knowledge base **must not add, delete or split** the user-provided modes.
      But if hit cases point to **different sub-scenarios / trigger conditions of the same failure mode**, write them into that task's \`known_issue_refs\` as evidence-gathering emphasis; **do not change the mode entry itself**.

    - **Path B (symptom only → Step 5 hypothesis inference)**:
      **Prefer forming the candidate set directly from the hit cases' historical failure modes**, then top up with common modes. That is, historical failure modes are not "one of the candidates" but the **first-choice source** — put in as many relevant historical modes as there are, then **merge and de-duplicate** with the inferred ones, still bounded by the **Top 3 ceiling**.

    - **Path C (crossing with Step 2 \`fault-model\` association)**:
      Take the **union (de-duplicated)** of the hit cases' failure modes and the \`fault-model\` association result; the two corroborate each other and never prune each other.
  - **Write task metadata (pointer + your distilled association, no inlined bodies)**: \`cases_file\` is the absolute path Shennong returned; \`case_ids\`/\`case_names\` are the case id and name lists. You already read that file in Action 2 to distill failure modes, but it is **forbidden** to write case bodies into the plan; metadata carries only the **pointer + case ids + case names**, for the downstream Kuafu to read the bodies. Following the \`failure_mode\` correspondence, write the \`known_issue_refs\` field of the matching task in Section 5 task metadata:
    - Shaped as \`{ "cases_file": "<the absolute path from Shennong, verbatim>", "case_ids": ["<case id relevant to this failure_mode>", ...], "case_names": ["<matching case name>", ...] }\`.
    - \`cases_file\` is identical across all tasks of one retrieval; each task picks into \`case_ids\`/\`case_names\` only the cases relevant to its own \`failure_mode\`, kept in **one-to-one, same order** (the k-th id matches the k-th name).
    - When a task has no relevant historical case, **omit** its \`known_issue_refs\` field (do not write an empty object).
    - This field is a **historical reference pointer**, passed through Dayu to Kuafu (which then reads the \`cases_file\` bodies); it is **strictly forbidden** to write cases into other plan sections as this run's root-cause conclusion.
  - **Bottom line (unbreakable)**: although historical failure modes substantively participate (Paths B/C), they **do not change** Step 3's mandatory short-circuit — when the user has explicitly given the failure mode (Path A) the user still wins, and historical cases **must not** be used to derive sub-modes, override the user's judgement, or push the list beyond the Top 3 ceiling; **one failure mode still maps to exactly one task**, and multiple hit cases must not split it.
  - **Graceful degradation**: if Shennong returns "no related case / knowledge base unavailable", proceed to Step 2 as usual and infer via the original flow (omit \`known_issue_refs\` on all tasks) — do not abort, do not error, and do not repeatedly re-question the user because of it.

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⛔️ **[MANDATORY GATE BEFORE STEP 2 — NOT SKIPPABLE]**

  Before you move on to "Step 2: Association Rules", you **must** answer these three questions; failing any of them **forbids** entering Step 2:

  1. **Have I actually called the Shennong sub-agent this round (\`task(subagent_type="shennong", ...)\`)?**
     - If **never called** → this is an **illegal skip**; go back to Step 1.5 and call Shennong first. You **must not** jump to Step 2, and must not assume "no hits".
  2. **Is the \`cases_file\` Shennong returned empty or non-empty?**
     - Non-empty but I have **not yet \`Read\`** it → \`Read\` it now, finish distilling failure modes, then enter Step 2.
  3. **Does the conclusion "no hits / knowledge base unavailable" come from Shennong's real return, rather than being my default assumption after skipping retrieval?**
     - If it is a "no hits" I reached by skipping → treat as a violation and return to question 1.

  **Sole pass condition**: ① Shennong was really called, AND ② either (\`cases_file\` is empty/unavailable) or (it has been \`Read\` and distillation is done). Only then may you enter Step 2.
`

const HINT_EN =
  ", together with **the historical failure modes returned by the Step 1.5 known-issue lookup** (if relevant historical cases were retrieved, **form the candidate set directly from those hit historical failure modes first** — they are the first-choice source rather than one candidate among many — then top up with the common modes below to ≤ Top 3, merging and de-duplicating with the inferred ones; with no result or when unavailable, degrade to pure inference)"

const HANDOFF_TASKLINE_EN =
  ' [KNOWN-ISSUE]: {the matching task\'s known_issue_refs.cases_file absolute path + case_ids + case_names; write "none" if absent}. [KNOWN-ISSUE-STRATEGY]: if the above is "none" → follow the normal flow (prefer retrieving and calling the relevant skill); if not "none" → **first Read that cases_file (historical case bodies, full-text reference)**, judge against the current symptom whether it enables fast localization/verification of the root cause, and gather evidence accordingly; **if the historical cases are insufficient, fall back to the normal skill retrieval flow**. Either way, historical cases are reference only — the final conclusion must be backed by this run\'s actual evidence.'

const HANDOFF_NOTE_EN = `
> **Note on the \`[KNOWN-ISSUE]\` segment**: if the matching task's \`known_issue_refs\` is non-empty, inject its \`cases_file\` absolute path and \`case_names\` into this segment; Kuafu should **first Read cases_file to attempt fast diagnosis from historical cases, and call skills only when that is insufficient**. Historical cases are **reference, not conclusion**, and still require actual evidence. When empty, Kuafu follows the normal flow (skill retrieval first).
`

const TODO_EN =
  '\n  { id: "diag-0", content: "Call Shennong to search the knowledge base + Read cases_file to distill historical failure modes (Step 1.5; degrades to skipped when no knowledge base)", status: "pending" },'

/**
 * 生成占位符替换表。
 *
 * @param enabled 神农是否启用。false 时所有片段为空串 → 伏羲提示词零神农痕迹。
 */
export function knownIssueReplacements(
  enabled: boolean,
  language: OutputLanguage,
): Record<KnownIssuePlaceholder, string> {
  if (!enabled) {
    return {
      KNOWN_ISSUE_LOOKUP: "",
      KNOWN_ISSUE_HINT: "",
      KNOWN_ISSUE_HANDOFF_TASKLINE: "",
      KNOWN_ISSUE_HANDOFF_NOTE: "",
      KNOWN_ISSUE_TODO: "",
    }
  }
  const en = language === "en"
  return {
    KNOWN_ISSUE_LOOKUP: en ? LOOKUP_EN : LOOKUP_ZH,
    KNOWN_ISSUE_HINT: en ? HINT_EN : HINT_ZH,
    KNOWN_ISSUE_HANDOFF_TASKLINE: en ? HANDOFF_TASKLINE_EN : HANDOFF_TASKLINE_ZH,
    KNOWN_ISSUE_HANDOFF_NOTE: en ? HANDOFF_NOTE_EN : HANDOFF_NOTE_ZH,
    KNOWN_ISSUE_TODO: en ? TODO_EN : TODO_ZH,
  }
}
