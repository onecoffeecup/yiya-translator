#!/usr/bin/env python3
"""Hardware-free PoC checks. Device compilation is opt-in and is NEVER hardware PASS."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import platform
import shlex
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
POC = ROOT / 'ipados' / 'CapturePoC'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='also require a generic iPad device build, without signing')
    parser.add_argument('--host-sdk', help='optional existing macOS SDK for host checks; does not change xcode-select')
    args = parser.parse_args()
    parent = ROOT / '.build' / 'ipados-poc'
    parent.mkdir(parents=True, exist_ok=True)
    report_dir = Path(tempfile.mkdtemp(prefix=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-'), dir=parent))
    os.chmod(report_dir, 0o700)
    results = []

    def run(name, cmd):
        try:
            p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
            code, output = p.returncode, p.stdout
        except (OSError, subprocess.TimeoutExpired) as error:
            code, output = -1, str(error)
        log = report_dir / (name + '.log')
        log.write_text(output)
        os.chmod(log, 0o600)
        result = {'name': name, 'command': shlex.join(map(str, cmd)), 'exit_code': code,
                  'status': 'passed' if code == 0 else 'failed', 'log': str(log)}
        results.append(result)
        print(f'{name}: {result["status"]} (exit {code})')
        if code:
            print('\n'.join(output.splitlines()[:8]))
        return code == 0

    # Structural checks enforce the target's device family, source membership and privacy configuration.
    project = POC / 'YiyaCapturePoC.xcodeproj' / 'project.pbxproj'
    try:
        info = plistlib.loads((POC / 'Info.plist').read_bytes())
        assert info['NSCameraUsageDescription']
        assert 'NSMicrophoneUsageDescription' not in info
        assert 'NSAppTransportSecurity' not in info
        assert 'UIBackgroundModes' not in info
        converted = subprocess.run(['plutil', '-convert', 'xml1', '-o', '-', str(project)], capture_output=True, check=True)
        data = plistlib.loads(converted.stdout)
        objects = data['objects']
        root = objects[data['rootObject']]
        target = objects[root['targets'][0]]
        source_refs = []
        for phase_id in target['buildPhases']:
            phase = objects[phase_id]
            if phase['isa'] == 'PBXSourcesBuildPhase':
                source_refs = [objects[objects[x]['fileRef']]['path'] for x in phase['files']]
        assert sorted(source_refs) == sorted(x.name for x in (POC / 'Sources').glob('*.swift'))
        for config_id in objects[root['buildConfigurationList']]['buildConfigurations']:
            assert str(objects[config_id]['buildSettings']['IPHONEOS_DEPLOYMENT_TARGET']) == '17.0'
        for config_id in objects[target['buildConfigurationList']]['buildConfigurations']:
            settings = objects[config_id]['buildSettings']
            assert str(settings['TARGETED_DEVICE_FAMILY']) == '2'
            assert settings['SUPPORTS_MACCATALYST'] == 'NO'
        ET.parse(POC / 'YiyaCapturePoC.xcodeproj/xcshareddata/xcschemes/YiyaCapturePoC.xcscheme')
        results.append({'name': 'project-and-privacy-structure', 'status': 'passed'})
        print('project-and-privacy-structure: passed')
    except (OSError, KeyError, AssertionError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        results.append({'name': 'project-and-privacy-structure', 'status': 'failed', 'error': str(error)})
        print('project-and-privacy-structure: failed', error)

    host_flags = ['-sdk', args.host_sdk] if args.host_sdk else []
    sources = sorted(map(str, (POC / 'Sources').glob('*.swift')))
    # Syntax-only parsing deliberately does not resolve Clang module maps or Apple APIs.
    run('swift-syntax', ['swiftc', '-frontend', '-parse', '-Xcc', '-fno-implicit-module-maps', *sources])
    binary = report_dir / 'CapturePrimitivesChecks'
    compiled = run('host-primitives-build', ['swiftc', '-swift-version', '5', *host_flags,
        str(POC / 'Sources/CapturePrimitives.swift'), str(POC / 'Tests/CapturePrimitivesChecks.swift'), '-o', str(binary)])
    if compiled:
        run('host-primitives-execution', [str(binary)])
    else:
        results.append({'name': 'host-primitives-execution', 'status': 'not_run', 'reason': 'host build failed'})
    # Type-check real capture service without connecting cameras. Still a macOS SDK, not an iPad build.
    run('host-capture-service-typecheck', ['swiftc', '-swift-version', '5', *host_flags,
        '-target', f'{platform.machine()}-apple-macosx14.0', '-typecheck',
        str(POC / 'Sources/CapturePrimitives.swift'), str(POC / 'Sources/CaptureService.swift')])

    if args.build:
        available = run('xcode-preflight', ['xcodebuild', '-version'])
        sdk = run('ipados-sdk-preflight', ['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'])
        if available and sdk:
            run('ipados-device-build', ['xcodebuild', '-project', str(POC / 'YiyaCapturePoC.xcodeproj'),
                '-scheme', 'YiyaCapturePoC', '-configuration', 'Debug', '-destination', 'generic/platform=iOS',
                '-derivedDataPath', str(report_dir / 'DerivedData'), 'CODE_SIGNING_ALLOWED=NO', 'build'])
        else:
            results.append({'name': 'ipados-device-build', 'status': 'not_run', 'reason': 'full Xcode / iPadOS SDK unavailable'})
    else:
        results.append({'name': 'ipados-device-build', 'status': 'not_requested'})
    results.append({'name': 'hardware-gate', 'status': 'not_verified',
                    'reason': 'requires target USB-C iPad, UVC capture card and Switch; never inferred from these checks'})
    files = sorted((POC / 'Sources').glob('*.swift')) + sorted((POC / 'Tests').glob('*.swift')) + [POC / 'Info.plist', project, Path(__file__).resolve()]
    summary = {'schema': 1, 'checks': results, 'host_sdk_override': args.host_sdk,
               'sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
               'hardware_gate': 'not_verified', 'third_stage_allowed': False}
    summary_path = report_dir / 'summary.json'
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    os.chmod(summary_path, 0o600)
    print('Report:', summary_path)
    print('Hardware gate: NOT VERIFIED; third stage remains closed.')
    return 1 if any(r['status'] == 'failed' for r in results) else 0


if __name__ == '__main__':
    raise SystemExit(main())
