## 阶段一快照采集脚本

本目录用于存放 `network-diagnosis` Skill 的辅助脚本。

### `collect_snapshot.sh`

用于在“阶段一：快速信息收集（T0 快照）”并行/批量采集关键信息并落盘。

```bash
bash collect_snapshot.sh --out ./out --iface bond0 --dest 10.0.0.1
```

输出会生成到 `./out/snapshot_YYYYmmdd_HHMMSS/`。

