#!/usr/bin/env python3
"""Verify, package and install the reviewed offline dictionary snapshot.

Uses only Python's standard library. Never accesses the user's learning database.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "resources/learning/reference"
LOCK = REFERENCE / "reference-package.json"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_lock():
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    if data["format_version"] != 1:
        raise ValueError("不支持的资料包版本")
    for name in data["files"]:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or str(path) != name:
            raise ValueError("校验清单包含不安全的路径")
    return data


def verify(directory, lock):
    for name, expected in lock["files"].items():
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"缺少资料文件：{name}。请按 docs/源码构建.md 安装资料包。")
        if path.stat().st_size != expected["size"] or sha256(path) != expected["sha256"]:
            raise ValueError(f"资料校验失败：{name}；请使用与源码匹配的 Release 资料包。")
    database = directory / "reference.sqlite"
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as db:
        if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ValueError("词典数据库完整性检查失败")
        manifest = json.loads(db.execute("SELECT value FROM metadata WHERE key='manifest'").fetchone()[0])
    if manifest != json.loads((directory / "reference-manifest.json").read_text(encoding="utf-8")):
        raise ValueError("数据库与来源清单不一致")


def write_checksum(path):
    path.with_name(path.name + ".sha256").write_text(f"{sha256(path)}  {path.name}\n", encoding="utf-8")


def create_lock():
    manifest = json.loads((REFERENCE / "reference-manifest.json").read_text(encoding="utf-8"))
    snapshot = manifest["jmdict_header_dates"][0].replace("-", "")
    names = ["reference.sqlite", "reference-manifest.json", "README.txt"]
    names += [str(p.relative_to(REFERENCE)) for p in sorted((REFERENCE / "licenses").iterdir()) if p.is_file()]
    files = {}
    for name in names:
        path = REFERENCE / name
        if path.is_symlink():
            raise ValueError("资料包不允许符号链接")
        files[name] = {"size": path.stat().st_size, "sha256": sha256(path)}
    lock = {"format_version": 1, "snapshot": snapshot,
            "archive": f"fuyi-reference-{snapshot}.zip", "files": files}
    verify(REFERENCE, lock)
    LOCK.write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已生成校验清单：{LOCK}")


def pack(lock):
    verify(REFERENCE, lock)
    output = ROOT / "dist/release" / lock["archive"]
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name in list(lock["files"]) + [LOCK.name]:
                archive.write(REFERENCE / name, "reference/" + name)
        os.replace(temporary_path, output)
    finally:
        temporary_path.unlink(missing_ok=True)
    write_checksum(output)
    print(f"资料包：{output}（{output.stat().st_size / 2**20:.1f} MiB）")


def install(path, lock):
    expected = {"reference/" + name: info for name, info in lock["files"].items()}
    expected["reference/" + LOCK.name] = {"size": LOCK.stat().st_size, "sha256": sha256(LOCK)}
    temporary_root = ROOT / ".build/reference-import"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=temporary_root) as temporary:
        temporary = Path(temporary)
        with zipfile.ZipFile(path) as archive:
            entries = [entry for entry in archive.infolist() if not entry.is_dir()]
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)) or set(names) != set(expected):
                raise ValueError("资料包文件清单不匹配；拒绝未知路径、缺失文件或重复文件")
            for entry in entries:
                mode = stat.S_IFMT(entry.external_attr >> 16)
                if mode not in (0, stat.S_IFREG) or entry.file_size != expected[entry.filename]["size"]:
                    raise ValueError("资料包包含不支持的文件类型或大小")
                destination = temporary / entry.filename
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, destination.open("wb") as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
                if sha256(destination) != expected[entry.filename]["sha256"]:
                    raise ValueError(f"资料包校验失败：{entry.filename}")
        verify(temporary / "reference", lock)
        # 全部文件验证完才替换；数据库最后以原子 rename 发布。
        names = [name for name in lock["files"] if name != "reference.sqlite"] + ["reference.sqlite"]
        for name in names:
            destination = REFERENCE / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(temporary / "reference" / name, destination)
    print("离线资料已安装并通过校验；用户学习记录未参与此操作。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="检查资料完整性和 SHA-256")
    commands.add_parser("pack", help="生成单独的 Release 资料附件")
    commands.add_parser("create-lock", help="维护者审核数据更新后重新登记校验值")
    command = commands.add_parser("install", help="从下载的 Release 附件安装资料")
    command.add_argument("archive", type=Path)
    command = commands.add_parser("stage", help="把已验证的资料复制到 App 资源目录")
    command.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "create-lock":
            create_lock()
            return
        lock = load_lock()
        if args.command == "install":
            install(args.archive.expanduser(), lock)
        elif args.command == "pack":
            pack(lock)
        else:
            verify(REFERENCE, lock)
            if args.command == "stage":
                for name in list(lock["files"]) + [LOCK.name]:
                    destination = args.destination / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(REFERENCE / name, destination)
            print(f"离线资料校验通过（快照 {lock['snapshot']}）")
    except (OSError, ValueError, KeyError, sqlite3.Error, zipfile.BadZipFile) as error:
        parser.exit(1, f"错误：{error}\n")


if __name__ == "__main__":
    main()
