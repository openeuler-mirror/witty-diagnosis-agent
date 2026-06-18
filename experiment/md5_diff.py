"""
对比两个目录下每个文件的 MD5，将不同的文件输出到 D:\\code。

输出内容：
  D:\\code\\md5_diff_report.txt   — 文本报告（差异/仅左/仅右）
  D:\\code\\md5_diff_report.json  — 同样信息的 JSON
  D:\\code\\agent-insight-diff\\         — 左侧有差异的文件副本（保留相对路径）
  D:\\code\\witty-skill-insight-diff\\   — 右侧有差异的文件副本（保留相对路径）

用法：
  python md5_diff.py
  python md5_diff.py --left <左目录> --right <右目录> --out <输出目录>
  python md5_diff.py --no-copy   # 只生成报告，不复制文件
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_LEFT = r"\\wsl.localhost\Ubuntu-22.04\opt\src\agent-insight"
DEFAULT_RIGHT = r"\\wsl.localhost\Ubuntu-22.04\opt\src\witty-skill-insight"
DEFAULT_OUT = r"D:\code"
CHUNK = 1024 * 1024  # 1 MiB


def md5_of(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def walk_files(root: Path) -> dict[str, Path]:
    """返回 {相对路径(用'/'分隔, 大小写保留): 绝对路径}。跳过符号链接和无法访问的项。"""
    result: dict[str, Path] = {}
    if not root.exists():
        print(f"[warn] 目录不存在: {root}", file=sys.stderr)
        return result
    for p in root.rglob("*"):
        try:
            if p.is_symlink() or not p.is_file():
                continue
        except OSError as e:
            print(f"[warn] 跳过 {p}: {e}", file=sys.stderr)
            continue
        rel = p.relative_to(root).as_posix()
        result[rel] = p
    return result


@dataclass
class DiffResult:
    only_left: list[str] = field(default_factory=list)
    only_right: list[str] = field(default_factory=list)
    different: list[dict] = field(default_factory=list)   # {path, left_md5, right_md5}
    same_count: int = 0
    errors: list[dict] = field(default_factory=list)      # {path, side, error}


def compare(left_root: Path, right_root: Path) -> DiffResult:
    left = walk_files(left_root)
    right = walk_files(right_root)
    res = DiffResult()

    left_keys = set(left)
    right_keys = set(right)

    res.only_left = sorted(left_keys - right_keys)
    res.only_right = sorted(right_keys - left_keys)

    for rel in sorted(left_keys & right_keys):
        try:
            lm = md5_of(left[rel])
        except OSError as e:
            res.errors.append({"path": rel, "side": "left", "error": str(e)})
            continue
        try:
            rm = md5_of(right[rel])
        except OSError as e:
            res.errors.append({"path": rel, "side": "right", "error": str(e)})
            continue
        if lm == rm:
            res.same_count += 1
        else:
            res.different.append({"path": rel, "left_md5": lm, "right_md5": rm})

    return res


def copy_diff(rel_paths: list[str], src_root: Path, dst_root: Path) -> None:
    for rel in rel_paths:
        src = src_root / rel
        if not src.exists():
            continue
        dst = dst_root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copy2(src, dst)
        except OSError as e:
            print(f"[warn] 复制失败 {src} -> {dst}: {e}", file=sys.stderr)


def write_reports(out_dir: Path, left: Path, right: Path, res: DiffResult) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    txt = out_dir / "md5_diff_report.txt"
    with txt.open("w", encoding="utf-8") as f:
        f.write(f"LEFT : {left}\n")
        f.write(f"RIGHT: {right}\n")
        f.write(f"相同文件数 : {res.same_count}\n")
        f.write(f"内容不同   : {len(res.different)}\n")
        f.write(f"仅在 LEFT  : {len(res.only_left)}\n")
        f.write(f"仅在 RIGHT : {len(res.only_right)}\n")
        f.write(f"错误       : {len(res.errors)}\n")
        f.write("\n=== 内容不同（同名文件 MD5 不一致） ===\n")
        for d in res.different:
            f.write(f"  {d['path']}\n    L={d['left_md5']}\n    R={d['right_md5']}\n")
        f.write("\n=== 仅在 LEFT (agent-insight) ===\n")
        for p in res.only_left:
            f.write(f"  {p}\n")
        f.write("\n=== 仅在 RIGHT (witty-skill-insight) ===\n")
        for p in res.only_right:
            f.write(f"  {p}\n")
        if res.errors:
            f.write("\n=== 错误 ===\n")
            for e in res.errors:
                f.write(f"  [{e['side']}] {e['path']}: {e['error']}\n")

    js = out_dir / "md5_diff_report.json"
    js.write_text(
        json.dumps(
            {
                "left": str(left),
                "right": str(right),
                "same_count": res.same_count,
                "different": res.different,
                "only_left": res.only_left,
                "only_right": res.only_right,
                "errors": res.errors,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"报告已写入: {txt}")
    print(f"          : {js}")


def main() -> int:
    ap = argparse.ArgumentParser(description="按 MD5 对比两个目录的文件")
    ap.add_argument("--left", default=DEFAULT_LEFT)
    ap.add_argument("--right", default=DEFAULT_RIGHT)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--no-copy", action="store_true", help="只生成报告，不复制差异文件")
    args = ap.parse_args()

    left = Path(args.left)
    right = Path(args.right)
    out = Path(args.out)

    print(f"LEFT : {left}")
    print(f"RIGHT: {right}")
    print(f"OUT  : {out}")
    print("正在扫描并计算 MD5 ...")
    res = compare(left, right)

    print(
        f"相同={res.same_count}  不同={len(res.different)}  "
        f"仅左={len(res.only_left)}  仅右={len(res.only_right)}  错误={len(res.errors)}"
    )

    write_reports(out, left, right, res)

    if not args.no_copy:
        # 把两边的差异文件分别落到独立子目录，保留相对路径
        left_dst = out / "agent-insight-diff"
        right_dst = out / "witty-skill-insight-diff"
        diff_paths = [d["path"] for d in res.different]
        copy_diff(diff_paths + res.only_left, left, left_dst)
        copy_diff(diff_paths + res.only_right, right, right_dst)
        print(f"差异文件已复制到: {left_dst}  /  {right_dst}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
