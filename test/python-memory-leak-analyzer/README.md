# Python Memory Leak Analyzer Tests

This directory contains reproducible scenarios for `python-memory-leak-analyzer`.
The scenarios generate structured evidence under `out/` and can be used by
Xuanyuan/Baize end-to-end validation.

## Layout

```text
test/python-memory-leak-analyzer/
├── run.sh
├── cleanup.sh
├── scenario_manifest.json
├── fault-injection/
│   ├── global_container_leak.py
│   ├── lru_cache_unbounded.py
│   ├── rss_fragmentation_like.py
│   ├── edge-cases/
│   └── realistic/
└── reports/
```

`out/` is generated at runtime and must not be committed.

## Basic Scenarios

```bash
cd test/python-memory-leak-analyzer
bash ./run.sh clean
bash ./run.sh run global
bash ./run.sh run cache
bash ./run.sh run fragmentation
```

Expected direction:

| Scenario | Expected result |
| --- | --- |
| `global` | Python retained leak through a module-level container. |
| `cache` | Unbounded cache growth. |
| `fragmentation` | RSS or allocator direction; no confirmed Python retained leak without retention evidence. |

## Edge-Case Scenarios

```bash
bash ./run.sh run-edge multi_source_mismatch
bash ./run.sh run-edge closure_capture
bash ./run.sh run-edge live_pid_readonly
```

Expected direction:

| Scenario | Expected result |
| --- | --- |
| `multi_source_mismatch` | Dominant listener/cache growth is not confused with the small visible global. |
| `closure_capture` | Closure or global task table retention is reported. |
| `live_pid_readonly` | PID/RSS-only evidence keeps the conclusion at read-only insufficient or equivalent boundary. |

## Realistic Scenarios

```bash
bash ./run.sh run-realistic native_ctypes_malloc_growth
bash ./run.sh run-realistic mmap_file_or_shmem_growth
bash ./run.sh run-realistic allocator_fragmentation_plateau
```

Expected direction:

| Scenario | Expected result |
| --- | --- |
| `native_ctypes_malloc_growth` | Native or allocator direction; no Python retained root cause. |
| `mmap_file_or_shmem_growth` | mmap/file-backed/shmem RSS surface direction. |
| `allocator_fragmentation_plateau` | Allocator high-water or plateau boundary; no confirmed ongoing retained leak. |

## Outputs

Each run writes evidence into:

```text
out/<scenario>/
out/edge-cases/<scenario>/
out/realistic/<scenario>/
```

Important generated evidence includes `correlation.json`, `discovery.json`,
`object_growth.json`, `semantic.json`, `tracemalloc.json`, `retention.json`,
`monitor_rss_pid.json`, and `live_process_snapshot.json` when applicable.

## Reports

`reports/` stores representative Xuanyuan/Baize Markdown and HTML outputs.
Each scenario directory contains one Markdown report and the HTML rendered from
the same Markdown basename:

```text
reports/<scenario>/<scenario>_xuanyuan_report.md
reports/<scenario>/<scenario>_xuanyuan_report.html
```

## Cleanup

```bash
bash ./run.sh clean
# or
bash ./cleanup.sh
```

Cleanup removes generated runtime evidence under `out/`.
