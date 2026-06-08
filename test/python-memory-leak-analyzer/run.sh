#!/usr/bin/env bash
# =============================================================================
# python-memory-leak-analyzer test runner
# Usage:
#   ./run.sh run <global|cache|fragmentation|all>
#   ./run.sh run-edge <scenario|all>
#   ./run.sh run-realistic <scenario|all>
#   ./run.sh prompt <scenario> <minimal|sparse|normal>
#   ./run.sh status
#   ./run.sh clean
# =============================================================================

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$ROOT_DIR/../.." && pwd)
SKILL_DIR="$REPO_ROOT/skills/python-memory-leak-analyzer"
OUT_DIR="$ROOT_DIR/out"
MANIFEST="$ROOT_DIR/scenario_manifest.json"

if [ -f "$REPO_ROOT/.venv/bin/activate" ]; then
  # Use the repository-local environment when generating evidence.
  # shellcheck source=/dev/null
  . "$REPO_ROOT/.venv/bin/activate"
fi

EDGE_SCENARIOS="
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

REALISTIC_SCENARIOS="
live_pid_python_object_leak
native_ctypes_malloc_growth
mmap_file_or_shmem_growth
allocator_fragmentation_plateau
prefork_worker_skew
transient_peak_copy_volume
cgroup_sibling_growth
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

scenario_manifest_value() {
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

write_scenario_metadata() {
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

write_report_contract() {
  local scenario="$1"
  local scenario_dir="$2"
  local mode="${3:-offline}"
  cat > "$scenario_dir/report-contract.md" <<EOF
# Python Memory Leak Analyzer Final Report Contract

scenario: $scenario
evidence_dir: $scenario_dir
mode: $mode

final_report_must_include:
- Markdown and HTML generated from the same Markdown source.
- Markdown and HTML share one basename and use a unique run timestamp or session id.
- Evidence files read for this run.
- correlation.json verdict, confidence_cap, and missing_evidence when correlation.json exists.
- Read-only / side-effect boundary, including unexecuted attach, ptrace, repair, restart, mutation, or config writes.
- Impact of missing evidence on conclusion and confidence.

report_boundary_rules:
- Evidence files not produced in this scenario are missing evidence, not missing tools.
- Do not convert optional enhancement tools into report acceptance gates.
- Do not write optional enhancement tool names as missing evidence or missing direct evidence.
- Use evidence-type wording instead: missing native allocation stack, allocator stats, C-extension release evidence, Python heap snapshot, semantic retention signal, or retention chain.
- Do not claim Python retained leak beyond correlation.json verdict and confidence_cap.
- Do not reuse historical Markdown/HTML reports as the current run's final report.
- Internal acceptance checks must not be copied into the final Markdown or HTML report.
EOF
}

edge_script() {
  local scenario="$1"
  local rel
  rel=$(scenario_manifest_value "$scenario" script) || return 1
  echo "$ROOT_DIR/$rel"
}

edge_summary() {
  scenario_manifest_value "$1" summary
}

edge_scenarios() {
  printf '%s\n' $EDGE_SCENARIOS
}

realistic_script() {
  case "$1" in
    live_pid_python_object_leak) echo "$ROOT_DIR/fault-injection/realistic/live_pid_python_object_leak.py" ;;
    native_ctypes_malloc_growth) echo "$ROOT_DIR/fault-injection/realistic/native_ctypes_malloc_growth.py" ;;
    mmap_file_or_shmem_growth) echo "$ROOT_DIR/fault-injection/realistic/mmap_file_or_shmem_growth.py" ;;
    allocator_fragmentation_plateau) echo "$ROOT_DIR/fault-injection/realistic/allocator_fragmentation_plateau.py" ;;
    prefork_worker_skew) echo "$ROOT_DIR/fault-injection/realistic/prefork_worker_skew.py" ;;
    transient_peak_copy_volume) echo "$ROOT_DIR/fault-injection/realistic/transient_peak_copy_volume.py" ;;
    cgroup_sibling_growth) echo "$ROOT_DIR/fault-injection/realistic/cgroup_sibling_growth.py" ;;
    *) return 1 ;;
  esac
}

realistic_scenarios() {
  printf '%s\n' $REALISTIC_SCENARIOS
}

realistic_summary() {
  case "$1" in
    live_pid_python_object_leak) echo "真实 PID 只读阶段只能确认目标 PID 在涨；复现阶段应确认 Python retained leak。" ;;
    native_ctypes_malloc_growth) echo "ctypes malloc native memory retained；Python heap ratio 低，Private_Dirty/RssAnon 增长。" ;;
    mmap_file_or_shmem_growth) echo "文件或 /dev/shm mmap retained mapping 增长；不应误报 Python heap leak。" ;;
    allocator_fragmentation_plateau) echo "大量分配释放后 RSS 高位平台；应输出 plateau/high-water，不确认 retained leak。" ;;
    prefork_worker_skew) echo "master 稳定、worker 子进程增长；应提示切换 worker/process tree scope。" ;;
    transient_peak_copy_volume) echo "短时复制峰值高但最终释放；应输出 peak high but not retained。" ;;
    cgroup_sibling_growth) echo "目标父进程稳定但同 cgroup 子进程增长；应提示 target PID 不足以解释 cgroup memory。" ;;
    *) return 1 ;;
  esac
}

realistic_iterations() {
  case "$1" in
    native_ctypes_malloc_growth) echo 12 ;;
    mmap_file_or_shmem_growth) echo 8 ;;
    allocator_fragmentation_plateau) echo 20 ;;
    transient_peak_copy_volume) echo 600 ;;
    *) echo 300 ;;
  esac
}

realistic_retention_selector_args() {
  case "$1" in
    live_pid_python_object_leak) echo '--type-filter builtins.dict' ;;
    prefork_worker_skew|cgroup_sibling_growth) echo '--type-filter builtins.dict' ;;
    *) echo '--type-filter builtins.dict' ;;
  esac
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

edge_iterations() {
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
  summary=$(edge_summary "$scenario")
  mkdir -p "$scenario_dir/prompts"
  write_report_contract "$scenario" "$scenario_dir" "edge"
  printf 'python 泄露，请你分析找出原因\n' > "$scenario_dir/prompts/minimal.txt"
  printf '分析 Python 泄漏问题，范围在 %s\n' "$scenario_dir" > "$scenario_dir/prompts/sparse.txt"
  {
    echo "目标 skill: python-memory-leak-analyzer"
    echo "目标 skill 绝对路径: $SKILL_DIR"
    echo "场景: $scenario"
    echo "故障概要: $summary"
    echo "日志绝对路径: $log"
    echo "复现命令: bash ./run.sh run-edge $scenario"
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
  write_report_contract "$scenario" "$OUT_DIR/$scenario" "basic"
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
    "$OUT_DIR/$scenario/reachability_counterfactual.json" \
    "$OUT_DIR/$scenario/correlation.json"
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
    echo "== correlate_evidence =="
    python "$SKILL_DIR/scripts/correlate_evidence.py" \
      --object-growth "$OUT_DIR/$scenario/object_growth.json" \
      --tracemalloc "$OUT_DIR/$scenario/tracemalloc.json" \
      --semantic "$OUT_DIR/$scenario/semantic.json" \
      --retention "$OUT_DIR/$scenario/retention.json" \
      --output "$OUT_DIR/$scenario/correlation.json"
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

run_edge_one() {
  local scenario="$1"
  local script
  script=$(edge_script "$scenario") || {
    echo "ERROR: unknown edge-case scenario: $scenario" >&2
    exit 2
  }
  local summary
  summary=$(edge_summary "$scenario")
  local scenario_dir="$OUT_DIR/edge-cases/$scenario"
  local log="$scenario_dir/${scenario}.log"
  local iterations
  iterations=$(edge_iterations "$scenario")
  local selector
  selector=$(retention_selector_args "$scenario")
  local global_name
  global_name=$(reachability_global_name "$scenario")

  mkdir -p "$scenario_dir"
  write_report_contract "$scenario" "$scenario_dir" "edge"
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
    "$scenario_dir/reachability_counterfactual.json" \
    "$scenario_dir/correlation.json"
  write_scenario_metadata "$scenario" "$scenario_dir/metadata.json"
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
    echo "reproduce=./run.sh run-edge $scenario"
    echo "allowed_actions=$(scenario_manifest_value "$scenario" allowed_actions)"
    echo "primary_signal=$(scenario_manifest_value "$scenario" primary_signal)"
    echo "scenario_metadata=$scenario_dir/metadata.json"
    echo ""
    run_json_step "detect_capabilities" python "$SKILL_DIR/scripts/detect_capabilities.py" --output "$scenario_dir/capabilities.json"
    echo ""
    run_json_step "discover_evidence_initial" python "$SKILL_DIR/scripts/discover_evidence.py" "$scenario_dir" "$script" --output "$scenario_dir/discovery.initial.json"
    echo ""
    if [ "$scenario" = "live_pid_readonly" ]; then
      run_live_pid_monitor "$scenario_dir" "$script"
      echo ""
      run_json_step "correlate_evidence_readonly" python "$SKILL_DIR/scripts/correlate_evidence.py" \
        --monitor "$scenario_dir/monitor_rss_pid.json" \
        --output "$scenario_dir/correlation.json"
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
      echo "复现命令: bash ./run.sh run-edge $scenario"
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
      run_json_step "correlate_evidence" python "$SKILL_DIR/scripts/correlate_evidence.py" \
        --object-growth "$scenario_dir/object_growth.json" \
        --tracemalloc "$scenario_dir/tracemalloc.json" \
        --semantic "$scenario_dir/semantic.json" \
        --retention "$scenario_dir/retention.json" \
        --output "$scenario_dir/correlation.json"
      echo ""
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
      echo "复现命令: bash ./run.sh run-edge $scenario"
      echo "会话与报告: 本场景必须单独启动一个 Xuanyuan 会话；完成后输出并归档 Markdown 和 HTML 两份 Witty 原流程报告。"
      echo "诊断边界: 离线本地日志诊断，只读，不执行修复、重启、远程登录、attach、ptrace 或配置写入。"
    fi
  } 2>&1 | tee "$log"

  write_prompt_files "$scenario" "$scenario_dir" "$log"
  echo "log=$log"
}

start_realistic_processes() {
  local scenario="$1"
  local script="$2"
  local scenario_dir="$3"
  local target_log="$scenario_dir/live-target.log"
  local sibling_log="$scenario_dir/live-sibling.log"
  if [ "$scenario" = "cgroup_sibling_growth" ]; then
    python "$script" --sibling > "$sibling_log" 2>&1 &
    local sibling_pid=$!
    echo "$sibling_pid" > "$scenario_dir/sibling.pid"
    python "$script" --live > "$target_log" 2>&1 &
    local target_pid=$!
    echo "$target_pid" > "$scenario_dir/live.pid"
  else
    python "$script" --live > "$target_log" 2>&1 &
    local target_pid=$!
    echo "$target_pid" > "$scenario_dir/live.pid"
  fi
}

stop_realistic_processes() {
  local scenario_dir="$1"
  local pid_file
  for pid_file in "$scenario_dir/live.pid" "$scenario_dir/sibling.pid"; do
    if [ -f "$pid_file" ]; then
      local pid
      pid=$(cat "$pid_file" 2>/dev/null || true)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
    fi
  done
  sleep 0.5
  for pid_file in "$scenario_dir/live.pid" "$scenario_dir/sibling.pid"; do
    if [ -f "$pid_file" ]; then
      local pid
      pid=$(cat "$pid_file" 2>/dev/null || true)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
  done
}

run_realistic_one() {
  local scenario="$1"
  local script
  script=$(realistic_script "$scenario") || {
    echo "ERROR: unknown realistic scenario: $scenario" >&2
    exit 2
  }
  local summary
  summary=$(realistic_summary "$scenario")
  local scenario_dir="$OUT_DIR/realistic/$scenario"
  local log="$scenario_dir/${scenario}.log"
  local iterations
  iterations=$(realistic_iterations "$scenario")
  local selector
  selector=$(realistic_retention_selector_args "$scenario")

  mkdir -p "$scenario_dir"
  write_report_contract "$scenario" "$scenario_dir" "realistic"
  rm -f \
    "$scenario_dir/capabilities.json" \
    "$scenario_dir/discovery.json" \
    "$scenario_dir/live_process_snapshot.json" \
    "$scenario_dir/monitor_rss_pid.json" \
    "$scenario_dir/object_growth.json" \
    "$scenario_dir/semantic.json" \
    "$scenario_dir/tracemalloc.json" \
    "$scenario_dir/retention.json" \
    "$scenario_dir/correlation.json" \
    "$scenario_dir/live.pid" \
    "$scenario_dir/sibling.pid" \
    "$scenario_dir/live-target.log" \
    "$scenario_dir/live-sibling.log"

  {
    echo "scenario=$scenario"
    echo "summary=$summary"
    echo "workload=$script"
    echo "skill_dir=$SKILL_DIR"
    echo "iterations=$iterations"
    echo "reproduce=./run.sh run-realistic $scenario"
    echo "diagnosis_boundary=stdlib-only, no attach, no ptrace, no mutation against target PID"
    echo ""
    run_json_step "detect_capabilities" python "$SKILL_DIR/scripts/detect_capabilities.py" --output "$scenario_dir/capabilities.json"
    echo ""
    start_realistic_processes "$scenario" "$script" "$scenario_dir"
    sleep 1
    local live_pid
    live_pid=$(cat "$scenario_dir/live.pid")
    echo "live_pid=$live_pid"
    if [ -f "$scenario_dir/sibling.pid" ]; then
      echo "sibling_pid=$(cat "$scenario_dir/sibling.pid")"
    fi
    echo ""
    run_json_step "live_process_snapshot" python "$SKILL_DIR/scripts/live_process_snapshot.py" --pid "$live_pid" --output "$scenario_dir/live_process_snapshot.json"
    echo ""
    run_json_step "monitor_rss_pid" python "$SKILL_DIR/scripts/monitor_rss.py" --pid "$live_pid" --interval 0.5 --duration 4 --output "$scenario_dir/monitor_rss_pid.json"
    echo ""
    stop_realistic_processes "$scenario_dir"
    echo ""
    run_json_step "object_growth" python "$SKILL_DIR/scripts/object_growth.py" --script "$script" --iterations "$iterations" --output "$scenario_dir/object_growth.json"
    echo ""
    run_json_step "semantic_probe" python "$SKILL_DIR/scripts/semantic_probe.py" --script "$script" --iterations "$iterations" --output "$scenario_dir/semantic.json"
    echo ""
    run_json_step "tracemalloc_probe" python "$SKILL_DIR/scripts/tracemalloc_probe.py" --script "$script" --iterations "$iterations" --output "$scenario_dir/tracemalloc.json"
    echo ""
    # shellcheck disable=SC2086
    run_json_step "retention_chain" python "$SKILL_DIR/scripts/retention_chain.py" --script "$script" --iterations "$iterations" $selector --output "$scenario_dir/retention.json"
    echo ""
    run_json_step "correlate_evidence" python "$SKILL_DIR/scripts/correlate_evidence.py" \
      --monitor "$scenario_dir/monitor_rss_pid.json" \
      --snapshot "$scenario_dir/live_process_snapshot.json" \
      --object-growth "$scenario_dir/object_growth.json" \
      --tracemalloc "$scenario_dir/tracemalloc.json" \
      --semantic "$scenario_dir/semantic.json" \
      --retention "$scenario_dir/retention.json" \
      --output "$scenario_dir/correlation.json"
    echo ""
    run_json_step "discover_evidence_after_prod" python "$SKILL_DIR/scripts/discover_evidence.py" "$scenario_dir" "$script" --output "$scenario_dir/discovery.json"
    echo ""
    echo "== expected_focus =="
    echo "$summary"
    echo "final_report_must_reference=$scenario_dir/correlation.json"
  } 2>&1 | tee "$log"

  stop_realistic_processes "$scenario_dir"
  echo "log=$log"
}

show_prompt() {
  local scenario="$1"
  local kind="${2:-minimal}"
  local scenario_dir="$OUT_DIR/edge-cases/$scenario"
  local prompt_file="$scenario_dir/prompts/$kind.txt"
  if [ ! -f "$prompt_file" ]; then
    echo "ERROR: prompt not found; run ./run.sh run-edge $scenario first" >&2
    exit 2
  fi
  cat "$prompt_file"
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
  run-edge)
    case "${2:-all}" in
      all)
        for scenario in $(edge_scenarios); do
          run_edge_one "$scenario"
        done
        ;;
      *)
        run_edge_one "$2"
        ;;
    esac
    ;;
  run-realistic)
    case "${2:-all}" in
      all)
        for scenario in $(realistic_scenarios); do
          run_realistic_one "$scenario"
        done
        ;;
      *)
        run_realistic_one "$2"
        ;;
    esac
    ;;
  prompt)
    show_prompt "${2:-}" "${3:-minimal}"
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
