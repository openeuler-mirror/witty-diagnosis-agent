import dotenv
import os
import logging
from pathlib import Path
from typing import Any, Dict, List, Tuple

from langfuse import get_client

from evaluation.constants import ENV_FILE
from evaluation.utils import check_environment_variables


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

dotenv.load_dotenv(override=True, dotenv_path=ENV_FILE)


def read_text(path: Path, max_chars: int | None = None) -> str:
    with path.open("r", encoding="utf-8") as f:
        s = f.read()
    if max_chars is not None and len(s) > max_chars:
        return s[:max_chars] + f"\n\n...[TRUNCATED {len(s) - max_chars} chars]"
    return s


def collect_files(skill_dir: Path) -> List[Path]:
    files: List[Path] = []
    for root, _, filenames in os.walk(skill_dir):
        root_path = Path(root)
        for fn in filenames:
            p = root_path / fn
            p_str = str(p)
            if "/.git/" in p_str or "/__pycache__/" in p_str or p_str.endswith(".pyc"):
                continue
            files.append(p)
    files.sort()
    return files


def build_manifest(skill_dir: Path, files: List[Path]) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []
    for p in files:
        rel = p.relative_to(skill_dir).as_posix()
        st = p.stat()
        items.append({"path": rel, "bytes": st.st_size, "mtime": int(st.st_mtime)})
    return {
        "skill_name": skill_dir.name,
        "file_count": len(files),
        "files": items,
    }


def make_dataset_item_input(skill_dir: Path) -> Tuple[str, Dict[str, Any]]:
    skill_md_path = skill_dir / "SKILL.md"
    if not skill_md_path.exists():
        raise FileNotFoundError(f"missing SKILL.md: {skill_md_path}")

    files = collect_files(skill_dir)
    manifest = build_manifest(skill_dir, files)

    references: Dict[str, str] = {}
    for ref_dir_name in ("reference", "references"):
        ref_dir = skill_dir / ref_dir_name
        if ref_dir.is_dir():
            for root, _, filenames in os.walk(ref_dir):
                root_path = Path(root)
                for fn in sorted(filenames):
                    if not fn.lower().endswith(".md"):
                        continue
                    p = root_path / fn
                    rel = p.relative_to(skill_dir).as_posix()
                    references[rel] = read_text(p, max_chars=20_000)

    # scripts 也提供预览（需要全文就看附件）
    scripts: Dict[str, str] = {}
    scripts_dir = skill_dir / "scripts"
    if scripts_dir.is_dir():
        for fn in sorted(os.listdir(scripts_dir)):
            p = scripts_dir / fn
            if p.is_file():
                rel = p.relative_to(skill_dir).as_posix()
                scripts[rel] = read_text(p, max_chars=20_000)

    inp: Dict[str, Any] = {
        "skill_name": manifest["skill_name"],
        "skill_md": read_text(skill_md_path, max_chars=80_000),
        "references": references,
        "scripts": scripts,
        "manifest": manifest,
    }
    item_id = manifest["skill_name"]
    return item_id, inp


def ensure_dataset_exists(client: Any, dataset_name: str) -> None:
    try:
        client.create_dataset(name=dataset_name)
    except Exception as e:
        logging.warning("Failed to create dataset %s: %s", dataset_name, e)


def upload_all_skills(dataset_name: str, skills_root: Path) -> None:
    client = get_client()

    ensure_dataset_exists(client, dataset_name)

    skill_dirs: List[Path] = []

    if (skills_root / "SKILL.md").exists():
        skill_dirs.append(skills_root)
    else:
        for name in sorted(os.listdir(skills_root)):
            skill_dir = skills_root / name
            if not skill_dir.is_dir():
                continue
            if not (skill_dir / "SKILL.md").exists():
                continue
            skill_dirs.append(skill_dir)

    for skill_dir in skill_dirs:
        item_id, inp = make_dataset_item_input(skill_dir)

        logging.info(
            "Uploading skill %s as dataset item %s", inp["skill_name"], item_id
        )
        client.create_dataset_item(
            id=item_id,
            dataset_name=dataset_name,
            input=inp,
            expected_output=None,
            metadata={
                "type": "skill",
                "skill_name": inp["skill_name"],
            },
        )


def main() -> None:
    check_environment_variables(
        [
            "LANGFUSE_PUBLIC_KEY",
            "LANGFUSE_SECRET_KEY",
            "EVALUATION_LANGFUSE_DATASET_NAME",
            "EVALUATION_SKILL_PATH",
        ]
    )
    dataset_name = os.environ.get("EVALUATION_LANGFUSE_DATASET_NAME")
    skills_root = os.environ.get("EVALUATION_SKILL_PATH")
    skills_root = Path(skills_root).expanduser().resolve()
    if not skills_root.exists():
        raise SystemExit(f"skills_root does not exist: {skills_root}")

    upload_all_skills(dataset_name=dataset_name, skills_root=skills_root)


if __name__ == "__main__":
    main()
