#!/usr/bin/env python3
"""Control only the opt-in text trace; never launch/capture/translate/install."""
import argparse
import json
import os
from pathlib import Path
import stat
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description="译芽本地文字诊断（含原文与译文，不保存截图或凭证）")
    parser.add_argument("action", choices=("start", "stop", "status"))
    parser.add_argument("--seconds", type=int, default=120)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        parser.error("--seconds 必须为 1～300")
    root = Path(f"/tmp/yiya-text-trace-{os.getuid()}")
    if args.action == "start":
        root.mkdir(mode=0o700, exist_ok=True)
    if not root.exists():
        print("文字诊断已关闭；没有创建任何日志。")
        return
    st = root.lstat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise SystemExit("诊断目录权限不安全，未执行操作。")
    control = root / "control.json"
    log = root / "events.jsonl"
    if args.action == "stop":
        control.unlink(missing_ok=True)
        print(f"文字诊断已关闭；后续事件停止写入。已有日志保留在 {log}")
    elif args.action == "start":
        # Stop first. The logger holds no persistent output handle, so unlinking
        # the previous private log cannot redirect an old session into a new one.
        control.unlink(missing_ok=True)
        log.unlink(missing_ok=True)
        now = time.time()
        data = {"session": str(uuid.uuid4()), "issued_at": now, "expires_at": now + args.seconds}
        temp = root / f".control-{uuid.uuid4()}.tmp"
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream)
        os.replace(temp, control)
        print(f"已启用 {args.seconds} 秒，日志上限 1 MiB；包含选中窗口的 OCR 原文与译文。")
        print(f"日志：{log}（首次翻译处理周期后才生成；本命令不会启动应用或发起翻译）")
        print("本次 start 已清除上次文字诊断日志。可随时运行 stop。")
    else:
        active = False
        remaining = 0
        if control.exists() and not control.is_symlink() and control.stat().st_size <= 4096:
            try:
                data = json.loads(control.read_text())
                start, end = float(data["issued_at"]), float(data["expires_at"])
                uuid.UUID(data["session"])
                now = time.time()
                active = start <= now < end and 0 < end - start <= 300
                remaining = max(0, int(end - now))
            except (ValueError, KeyError, TypeError, OSError):
                pass
        size = log.stat().st_size if log.exists() and not log.is_symlink() else 0
        print(f"开关：{'有效' if active else '关闭或已过期'}；剩余约 {remaining if active else 0} 秒；日志 {size} 字节。")
        print("达到大小上限会提前停止；此状态不表示运行中的应用已加载诊断代码。")


if __name__ == "__main__":
    main()
