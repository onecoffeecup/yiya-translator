#!/usr/bin/env python3
"""Bound a native headless test and preserve its stack on a genuine hang."""
import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--sample', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command or args.timeout <= 0:
        parser.error('positive timeout and test command required')
    print('RUN native test:', Path(args.command[0]).name, flush=True)
    process = subprocess.Popen(args.command)
    try:
        return process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print('FAIL native test exceeded deadline; collecting stack, never treating timeout as pass', flush=True)
        args.sample.parent.mkdir(parents=True, exist_ok=True)
        try:
            result = subprocess.run(['sample', str(process.pid), '1', '-file', str(args.sample)],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10)
            print('sample exit:', result.returncode, flush=True)
            if args.sample.exists():
                print('\n'.join(args.sample.read_text(errors='replace').splitlines()[:240]), flush=True)
            else:
                print(result.stdout[:2000], flush=True)
        except (OSError, subprocess.TimeoutExpired) as error:
            print('stack unavailable:', type(error).__name__, flush=True)
        finally:
            process.kill()
            process.wait()
        return 124


if __name__ == '__main__':
    sys.exit(main())
