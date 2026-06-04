#!/usr/bin/env bash
# =============================================================================
# python-memory-leak-analyzer test runner
# Usage:
#   ./run.sh run <global|cache|fragmentation|all>
#   ./run.sh run-stress <scenario|all>
#   ./run.sh prompt <scenario> <minimal|sparse|normal>
#   ./run.sh score <scenario> <report-path>
#   ./run.sh status
#   ./run.sh clean
# =============================================================================

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$ROOT_DIR/../.." && pwd)
SKILL_DIR="$REPO_ROOT/skills/python-memory-leak-analyzer"
OUT_DIR="$ROOT_DIR/out"
MANIFEST="$ROOT_DIR/stress_manifest.json"

STRESS_SCENARIOS="
method_cache_self
callback_registry
closure_capture
thread_local_worker
asyncio_pending_task
unclosed_generator
cycle_finalizer
weakref_finalize
multi_source_mismatch
short_window_inconclusive
live_pid_readonly
"

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

scenario_script() {
  case "$1" in
    global) echo "$ROOT_DIR/fault-injection/global_container_leak.py" ;;
    cache) echo "$ROOT_DIR/fault-injection/lru_cache_unbounded.py" ;;
    fragmentation) echo "$ROOT_DIR/fault-injection/rss_fragmentation_like.py" ;;
    *) return 1 ;;
  esac
}

scenario_summary() {
  case "$1" in
    global) echo "全局 list/dict 容器无界增长，预期 root_kind 指向 module_global:LEAK_BUCKET。" ;;
    cache) echo "lru_cache(maxsize=None) 无界缓存增长，预期 cache_info.currsize 持续增加。" ;;
    fragmentation) echo "短生命周期 bytearray 分配释放，预期 Python 保留对象证据不足，作为 RSS/native/fragmentation 对照。" ;;
    *) return 1 ;;
  esac
}

stress_manifest_value() {
  local scenario="$1"
  local key="$2"
  python - "$MANIFEST" "$scenario" "$key" <<'PY'
import json
import sys

manifest_path, scenario, key = sys.argv[1:4]
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
try:
    value = manifest[scenario][key]
except KeyError:
    raise SystemExit(1)
if isinstance(value, (list, dict)):
    print(json.dumps(value, ensure_ascii=False))
else:
    print(value)
PY
}

write_stress_metadata() {
  local scenario="$1"
  local output="$2"
  python - "$MANIFEST" "$scenario" "$output" <<'PY'
import json
import os
import sys

manifest_path, scenario, output = sys.argv[1:4]
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
payload = dict(manifest[scenario])
payload["scenario"] = scenario
os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
with open(output, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

stress_script() {
  local scenario="$1"
  local rel
  rel=$(stress_manifest_value "$scenario" script) || return 1
  echo "$ROOT_DIR/$rel"
}

stress_summary() {
  stress_manifest_value "$1" summary
}

stress_scenarios() {
  printf '%s\n' $STRESS_SCENARIOS
}

retention_selector_args() {
  local scenario="$1"
  case "$scenario" in
    method_cache_self) echo '--name-contains CachedWorker' ;;
    callback_registry) echo '--name-contains ServiceClient' ;;
    closure_capture) echo '--type-filter builtins.function' ;;
    thread_local_worker) echo '--type-filter builtins.dict' ;;
    asyncio_pending_task) echo '--name-contains Task' ;;
    unclosed_generator) echo '--name-contains generator' ;;
    cycle_finalizer) echo '--name-contains FinalizedNode' ;;
    weakref_finalize) echo '--name-contains Session' ;;
    multi_source_mismatch) echo '--name-contains LargeTenant' ;;
    short_window_inconclusive) echo '--type-filter builtins.dict' ;;
    live_pid_readonly) echo '--type-filter builtins.dict' ;;
    *) echo '--type-filter builtins.dict' ;;
  esac
}

reachability_global_name() {
  local scenario="$1"
  case "$scenario" in
    callback_registry) echo 'LISTENER_REGISTRY' ;;
    closure_capture) echo 'TASK_TABLE' ;;
    asyncio_pending_task) echo 'PENDING_TASKS' ;;
    unclosed_generator) echo 'OPEN_GENERATORS' ;;
    cycle_finalizer) echo 'LEAK_ROOTS' ;;
    weakref_finalize) echo 'FINALIZERS' ;;
    multi_source_mismatch) echo 'LISTENERS' ;;
    short_window_inconclusive) echo 'WARM_CACHE' ;;
    live_pid_readonly) echo 'LIVE_BUCKET' ;;
    *) echo '' ;;
  esac
}

stress_iterations() {
  local scenario="$1"
  case "$scenario" in
    thread_local_worker) echo 400 ;;
    asyncio_pending_task) echo 250 ;;
    cycle_finalizer) echo 300 ;;
    live_pid_readonly) echo 300 ;;
    short_window_inconclusive) echo 256 ;;
    *) echo 600 ;;
  esac
}

write_prompt_files() {
  local scenario="$1"
  local scenario_dir="$2"
  local log="$3"
  local summary
  summary=$(stress_summary "$scenario")
  mkdir -p "$scenario_dir/prompts"
  printf 'python 泄露，请你分析找出原因\n' > "$scenario_dir/prompts/minimal.txt"
  printf '分析 Python 泄漏问题，范围在 %s\n' "$scenario_dir" > "$scenario_dir/prompts/sparse.txt"
  {
    echo "目标 skill: python-memory-leak-analyzer"
    echo "目标 skill 绝对路径: $SKILL_DIR"
    echo "场景: $scenario"
    echo "故障概要: $summary"
    echo "日志绝对路径: $log"
    echo "复现命令: bash ./run.sh run-stress $scenario"
    echo "会话与报告: 本场景必须单独启动一个 Xuanyuan 会话；完成后输出并归档 Markdown 和 HTML 两份 Witty 原流程报告。"
    echo "诊断边界: 离线本地日志诊断，只读，不执行修复、重启、远程登录、attach、ptrace 或配置写入。"
  } > "$scenario_dir/prompts/normal.txt"
}

run_json_step() {
  local label="$1"
  shift
  echo "== $label =="
  "$@"
  local code=$?
  if [ "$code" -ne 0 ]; then
    echo "STEP_STATUS label=$label status=partial exit_code=$code"
  else
    echo "STEP_STATUS label=$label status=success exit_code=0"
  fi
  return 0
}

run_one() {
  local scenario="$1"
  local script
  script=$(scenario_script "$scenario") || {
    echo "ERROR: unknown scenario: $scenario" >&2
    usage
    exit 2
  }
  mkdir -p "$OUT_DIR/$scenario"
  rm -f \
    "$OUT_DIR/$scenario/capabilities.json" \
    "$OUT_DIR/$scenario/discovery.json" \
    "$OUT_DIR/$scenario/discovery.initial.json" \
    "$OUT_DIR/$scenario/discovery.manual.json" \
    "$OUT_DIR/$scenario/object_growth.json" \
    "$OUT_DIR/$scenario/semantic.json" \
    "$OUT_DIR/$scenario/tracemalloc.json" \
    "$OUT_DIR/$scenario/retention.json" \
    "$OUT_DIR/$scenario/reachability_static.json" \
    "$OUT_DIR/$scenario/reachability_counterfactual.json"
  local log="$OUT_DIR/$scenario/${scenario}.log"
  local iterations=800
  [ "$scenario" = "fragmentation" ] && iterations=80

  {
    echo "scenario=$scenario"
    echo "summary=$(scenario_summary "$scenario")"
    echo "workload=$script"
    echo "skill_dir=$SKILL_DIR"
    echo "reproduce=./run.sh run $scenario"
    echo ""
    echo "== detect_capabilities =="
    python "$SKILL_DIR/scripts/detect_capabilities.py" --output "$OUT_DIR/$scenario/capabilities.json"
    echo ""
    echo "== discover_evidence =="
    python "$SKILL_DIR/scripts/discover_evidence.py" "$OUT_DIR/$scenario" "$script" --output "$OUT_DIR/$scenario/discovery.json"
    echo ""
    echo "== object_growth =="
    python "$SKILL_DIR/scripts/object_growth.py" --script "$script" --iterations "$iterations" --output "$OUT_DIR/$scenario/object_growth.json"
    echo ""
    echo "== semantic_probe =="
    python "$SKILL_DIR/scripts/semantic_probe.py" --script "$script" --iterations "$iterations" --output "$OUT_DIR/$scenario/semantic.json"
    echo ""
    echo "== tracemalloc_probe =="
    python "$SKILL_DIR/scripts/tracemalloc_probe.py" --script "$script" --iterations "$iterations" --output "$OUT_DIR/$scenario/tracemalloc.json"
    echo ""
    echo "== retention_chain =="
    case "$scenario" in
      global)
        python "$SKILL_DIR/scripts/retention_chain.py" --script "$script" --iterations "$iterations" --type-filter "builtins.dict" --output "$OUT_DIR/$scenario/retention.json"
        ;;
      cache)
        python "$SKILL_DIR/scripts/retention_chain.py" --script "$script" --iterations "$iterations" --name-contains "str" --output "$OUT_DIR/$scenario/retention.json"
        ;;
      fragmentation)
        python "$SKILL_DIR/scripts/retention_chain.py" --script "$script" --iterations "$iterations" --name-contains "bytearray" --output "$OUT_DIR/$scenario/retention.json" || true
        ;;
    esac
    echo ""
    echo "== reachability_probe static =="
    case "$scenario" in
      global)
        python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" --type-filter "builtins.dict" --output "$OUT_DIR/$scenario/reachability_static.json"
        echo ""
        echo "== reachability_probe sandbox counterfactual =="
        python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" --type-filter "builtins.dict" --global-name LEAK_BUCKET --allow-mutation --output "$OUT_DIR/$scenario/reachability_counterfactual.json"
        ;;
      cache)
        python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" --name-contains "str" --output "$OUT_DIR/$scenario/reachability_static.json"
        echo ""
        echo "== reachability_probe sandbox counterfactual =="
        python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" --name-contains "str" --global-name cached_payload --allow-mutation --output "$OUT_DIR/$scenario/reachability_counterfactual.json"
        ;;
      fragmentation)
        python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" --name-contains "bytearray" --output "$OUT_DIR/$scenario/reachability_static.json" || true
        ;;
    esac
    echo ""
    echo "== Xuanyuan prompt facts =="
    echo "目标 skill: python-memory-leak-analyzer"
    echo "目标 skill 绝对路径: $SKILL_DIR"
    echo "场景: $scenario"
    echo "日志绝对路径: $log"
    echo "复现命令: bash ./run.sh run $scenario"
    echo "会话与报告: 本场景必须单独启动一个 Xuanyuan 会话；完成后输出并归档 Markdown 和 HTML 两份 Witty 原流程报告。"
    echo "诊断边界: 离线本地日志诊断，只读，不执行修复、重启、远程登录或配置写入。"
  } 2>&1 | tee "$log"

  echo "log=$log"
}

run_live_pid_monitor() {
  local scenario_dir="$1"
  local script="$2"
  local pid_file="$scenario_dir/live.pid"
  local process_log="$scenario_dir/live-process.log"
  python "$script" > "$process_log" 2>&1 &
  local live_pid=$!
  echo "$live_pid" > "$pid_file"
  sleep 1
  run_json_step "monitor_rss_pid" python "$SKILL_DIR/scripts/monitor_rss.py" --pid "$live_pid" --interval 0.5 --duration 3 --output "$scenario_dir/monitor_rss_pid.json"
  if kill -0 "$live_pid" 2>/dev/null; then
    kill "$live_pid" 2>/dev/null || true
    wait "$live_pid" 2>/dev/null || true
  fi
}

run_stress_one() {
  local scenario="$1"
  local script
  script=$(stress_script "$scenario") || {
    echo "ERROR: unknown stress scenario: $scenario" >&2
    exit 2
  }
  local summary
  summary=$(stress_summary "$scenario")
  local scenario_dir="$OUT_DIR/stress/$scenario"
  local log="$scenario_dir/${scenario}.log"
  local iterations
  iterations=$(stress_iterations "$scenario")
  local selector
  selector=$(retention_selector_args "$scenario")
  local global_name
  global_name=$(reachability_global_name "$scenario")

  mkdir -p "$scenario_dir"
  rm -f \
    "$scenario_dir/capabilities.json" \
    "$scenario_dir/discovery.json" \
    "$scenario_dir/discovery.initial.json" \
    "$scenario_dir/discovery.manual.json" \
    "$scenario_dir/object_growth.json" \
    "$scenario_dir/semantic.json" \
    "$scenario_dir/tracemalloc.json" \
    "$scenario_dir/retention.json" \
    "$scenario_dir/reachability_static.json" \
    "$scenario_dir/reachability_counterfactual.json"
  write_stress_metadata "$scenario" "$scenario_dir/metadata.json"
  if [ "$scenario" = "live_pid_readonly" ]; then
    rm -f \
      "$scenario_dir/monitor_rss_pid.json" \
      "$scenario_dir/live.pid" \
      "$scenario_dir/live-process.log"
  fi

  {
    echo "scenario=$scenario"
    echo "summary=$summary"
    echo "workload=$script"
    echo "skill_dir=$SKILL_DIR"
    echo "iterations=$iterations"
    echo "reproduce=./run.sh run-stress $scenario"
    echo "allowed_actions=$(stress_manifest_value "$scenario" allowed_actions)"
    echo "primary_signal=$(stress_manifest_value "$scenario" primary_signal)"
    echo "metadata_for_scoring=$scenario_dir/metadata.json"
    echo ""
    run_json_step "detect_capabilities" python "$SKILL_DIR/scripts/detect_capabilities.py" --output "$scenario_dir/capabilities.json"
    echo ""
    run_json_step "discover_evidence_initial" python "$SKILL_DIR/scripts/discover_evidence.py" "$scenario_dir" "$script" --output "$scenario_dir/discovery.initial.json"
    echo ""
    if [ "$scenario" = "live_pid_readonly" ]; then
      run_live_pid_monitor "$scenario_dir" "$script"
      echo ""
      run_json_step "discover_evidence_after_monitor" python "$SKILL_DIR/scripts/discover_evidence.py" "$scenario_dir" --output "$scenario_dir/discovery.json"
      echo ""
      echo "== live_process_boundary =="
      echo "external_readonly_only: PID/RSS evidence was collected without Python heap attach, mutation, or in-process root-cause confirmation."
      echo "confidence_cap: weak_without_reproducible_heap_evidence"
      echo ""
      echo "== Xuanyuan minimal prompt =="
      echo "python 泄露，请你分析找出原因"
      echo ""
      echo "== Xuanyuan sparse prompt =="
      echo "分析 Python 泄漏问题，范围在 $scenario_dir"
      echo ""
      echo "== Xuanyuan normal prompt facts =="
      echo "目标 skill: python-memory-leak-analyzer"
      echo "目标 skill 绝对路径: $SKILL_DIR"
      echo "场景: $scenario"
      echo "日志绝对路径: $log"
      echo "复现命令: bash ./run.sh run-stress $scenario"
      echo "会话与报告: 本场景必须单独启动一个 Xuanyuan 会话；完成后输出并归档 Markdown 和 HTML 两份 Witty 原流程报告。"
      echo "诊断边界: 线上/PID 外部只读观测，不执行修复、重启、远程登录、attach、ptrace、配置写入或进程内 Python 堆归因。"
    else
      run_json_step "object_growth" python "$SKILL_DIR/scripts/object_growth.py" --script "$script" --iterations "$iterations" --output "$scenario_dir/object_growth.json"
      echo ""
      run_json_step "semantic_probe" python "$SKILL_DIR/scripts/semantic_probe.py" --script "$script" --iterations "$iterations" --output "$scenario_dir/semantic.json"
      echo ""
      run_json_step "tracemalloc_probe" python "$SKILL_DIR/scripts/tracemalloc_probe.py" --script "$script" --iterations "$iterations" --output "$scenario_dir/tracemalloc.json"
      echo ""
      # shellcheck disable=SC2086
      run_json_step "retention_chain" python "$SKILL_DIR/scripts/retention_chain.py" --script "$script" --iterations "$iterations" $selector --output "$scenario_dir/retention.json"
      echo ""
      # shellcheck disable=SC2086
      run_json_step "reachability_probe_static" python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" $selector --output "$scenario_dir/reachability_static.json"
      echo ""
      if [ -n "$global_name" ]; then
        # shellcheck disable=SC2086
        run_json_step "reachability_probe_sandbox_counterfactual" python "$SKILL_DIR/scripts/reachability_probe.py" --script "$script" --iterations "$iterations" $selector --global-name "$global_name" --allow-mutation --output "$scenario_dir/reachability_counterfactual.json"
        echo ""
      fi
      run_json_step "discover_evidence_after_analysis" python "$SKILL_DIR/scripts/discover_evidence.py" "$scenario_dir" --output "$scenario_dir/discovery.json"
      echo ""
      echo "== Xuanyuan minimal prompt =="
      echo "python 泄露，请你分析找出原因"
      echo ""
      echo "== Xuanyuan sparse prompt =="
      echo "分析 Python 泄漏问题，范围在 $scenario_dir"
      echo ""
      echo "== Xuanyuan normal prompt facts =="
      echo "目标 skill: python-memory-leak-analyzer"
      echo "目标 skill 绝对路径: $SKILL_DIR"
      echo "场景: $scenario"
      echo "日志绝对路径: $log"
      echo "复现命令: bash ./run.sh run-stress $scenario"
      echo "会话与报告: 本场景必须单独启动一个 Xuanyuan 会话；完成后输出并归档 Markdown 和 HTML 两份 Witty 原流程报告。"
      echo "诊断边界: 离线本地日志诊断，只读，不执行修复、重启、远程登录、attach、ptrace 或配置写入。"
    fi
  } 2>&1 | tee "$log"

  write_prompt_files "$scenario" "$scenario_dir" "$log"
  update_scorecard "$scenario" "generated" "not-run" "$log" "$scenario_dir"
  echo "log=$log"
}

update_scorecard() {
  local scenario="$1"
  local prompt="$2"
  local grade="$3"
  local report="$4"
  local evidence_dir="$5"
  local scorecard="$OUT_DIR/stress/scorecard.tsv"
  mkdir -p "$OUT_DIR/stress"
  if [ ! -f "$scorecard" ]; then
    printf 'scenario\tprompt\tgrade\treport_or_log\tevidence_dir\n' > "$scorecard"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$scenario" "$prompt" "$grade" "$report" "$evidence_dir" >> "$scorecard"
}

show_prompt() {
  local scenario="$1"
  local kind="${2:-minimal}"
  local scenario_dir="$OUT_DIR/stress/$scenario"
  local prompt_file="$scenario_dir/prompts/$kind.txt"
  if [ ! -f "$prompt_file" ]; then
    echo "ERROR: prompt not found; run ./run.sh run-stress $scenario first" >&2
    exit 2
  fi
  cat "$prompt_file"
}

score_report() {
  local scenario="$1"
  local report="$2"
  local scenario_dir="$OUT_DIR/stress/$scenario"
  mkdir -p "$scenario_dir"
  local score="$scenario_dir/score-$(basename "$report").json"
  python "$ROOT_DIR/scripts/score_stress_report.py" --scenario "$scenario" --report "$report" --manifest "$MANIFEST" --output "$score"
  local grade
  grade=$(python - "$score" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle)["grade"])
PY
)
  update_scorecard "$scenario" "report" "$grade" "$report" "$scenario_dir"
}

status_tests() {
  echo "out_dir=$OUT_DIR"
  if [ -d "$OUT_DIR" ]; then
    find "$OUT_DIR" -maxdepth 4 -type f -printf '%p %s bytes\n' 2>/dev/null || find "$OUT_DIR" -maxdepth 4 -type f
  else
    echo "no output directory"
  fi
}

clean_tests() {
  rm -rf "$OUT_DIR"
  echo "cleaned $OUT_DIR"
}

case "${1:-}" in
  run)
    case "${2:-global}" in
      all)
        run_one global
        run_one cache
        run_one fragmentation
        ;;
      global|cache|fragmentation)
        run_one "$2"
        ;;
      *)
        echo "ERROR: unknown scenario: $2" >&2
        usage
        exit 2
        ;;
    esac
    ;;
  run-stress)
    case "${2:-all}" in
      all)
        for scenario in $(stress_scenarios); do
          run_stress_one "$scenario"
        done
        ;;
      *)
        run_stress_one "$2"
        ;;
    esac
    ;;
  prompt)
    show_prompt "${2:-}" "${3:-minimal}"
    ;;
  score)
    if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
      echo "ERROR: score requires <scenario> <report-path>" >&2
      usage
      exit 2
    fi
    score_report "$2" "$3"
    ;;
  status)
    status_tests
    ;;
  clean)
    clean_tests
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "ERROR: unknown command: $1" >&2
    usage
    exit 2
    ;;
esac
