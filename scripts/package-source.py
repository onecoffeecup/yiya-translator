#!/usr/bin/env python3
"""Export the public source files; omit private work, credentials and large data."""
from pathlib import Path
import hashlib
import os
import re
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ROOT_FILES = [".gitignore", ".gitattributes", "README.md", "LICENSE", "VERSION",
              "CHANGELOG.md", "THIRD_PARTY_NOTICES.md"]
PUBLIC_DIRECTORIES = ["objc", "scripts", "tests", "tools", "resources", "docs"]
TOKEN = re.compile(rb"\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b")


def excluded(path):
    parts = path.parts
    return (any(part in {"__pycache__", "AppIcon.iconset", ".DS_Store", "_private", "handoff", "design"} for part in parts)
            or "refactoring" in parts
            or path.as_posix().startswith("docs/images/promo/")
            or path.as_posix() == "docs/重复修复候选验收清单-20261005.md"
            or path.as_posix() == "tests/MappingDebug.m"
            or path.name.startswith((".env", "reference.sqlite"))
            or path.suffix.lower() in {".sqlite", ".sqlite3", ".db", ".log"}
            or path.suffix in {".pyc", ".pyo", ".pem", ".p12", ".pfx"})


def main():
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("VERSION 必须是三段数字版本号")
    candidates = [ROOT / name for name in ROOT_FILES]
    for directory in PUBLIC_DIRECTORIES:
        candidates.extend(path for path in (ROOT / directory).rglob("*") if path.is_file() or path.is_symlink())
    files = []
    for path in sorted(set(candidates)):
        relative = path.relative_to(ROOT)
        if excluded(relative):
            continue
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"公开文件缺失或包含符号链接：{relative}")
        if path.stat().st_size > 100 * 2**20:
            raise ValueError(f"公开源码包含过大的文件：{relative}")
        data = path.read_bytes()
        if TOKEN.search(data) or re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", data):
            raise ValueError(f"发现疑似凭据：{relative}（未输出凭据内容）")
        files.append(path)
    output = ROOT / "dist/release" / f"fuyi-source-{version}.zip"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, f"fuyi-{version}/" + path.relative_to(ROOT).as_posix())
        with zipfile.ZipFile(temporary_path) as archive:
            if archive.testzip() is not None:
                raise ValueError("源码压缩包完整性检查失败")
        os.replace(temporary_path, output)
    finally:
        temporary_path.unlink(missing_ok=True)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_name(output.name + ".sha256").write_text(f"{digest}  {output.name}\n")
    print(f"公开源码包：{output}（{len(files)} 个文件，{output.stat().st_size / 2**20:.1f} MiB）")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"错误：{error}")
