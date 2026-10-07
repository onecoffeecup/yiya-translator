#!/usr/bin/env bash
# 采集卡验证入口。默认**只做离线 OCR 核对**（不需要权限、不接硬件、不占桌面）。
# 真实硬件 / 相机权限必须显式调用 probe 子命令，并且由使用者确认后再运行。
#
#   scripts/run-capture-card-check.sh [offline] [图片] [必须包含的子串]
#                                                   离线核对真实采集帧 → 生产 OCR
#   scripts/run-capture-card-check.sh inspect      只列举外接采集设备（不采集、不申请权限）
#   scripts/run-capture-card-check.sh authorize     触发一次相机权限申请（会弹系统提示）
#   scripts/run-capture-card-check.sh capture <设备显示名> [帧数]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT="$ROOT_DIR/.build/capture-card-check"
MODULE_CACHE="$ROOT_DIR/.build/capture-card-check-module-cache"
mkdir -p "$OUT" "$MODULE_CACHE"

# 工具源码自己 #import 了 LiveCaptionTranslator.m，这里只补链接其余实现文件，
# 否则会出现重复符号。
LINK_SOURCES=(
  "$ROOT_DIR/objc/FYTranslationTrace.m" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m"
  "$ROOT_DIR/objc/FYInlineLayout.m" "$ROOT_DIR/objc/FYWindowManager.m" "$ROOT_DIR/objc/FYOCRManager.m" "$ROOT_DIR/objc/FYGeometryManager.m" "$ROOT_DIR/objc/FYTranslationManager.m"
  "$ROOT_DIR/objc/FYCaptureCardInput.m"
  "$ROOT_DIR"/objc/learning/*.m
)
FRAMEWORKS=(
  -framework Cocoa -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision
  -framework Carbon -framework NaturalLanguage
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo
  -framework ImageIO -lsqlite3
)

build() { # build <工具源文件> <输出可执行名>
  clang -fobjc-arc -fmodules -fmodules-cache-path="$MODULE_CACHE" \
    -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -Wno-nonnull \
    -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" \
    "$1" "${LINK_SOURCES[@]}" -o "$OUT/$2" "${FRAMEWORKS[@]}"
}

# Vision 的 Accurate 文字识别要求调用方是有 bundle 身份、已签名的应用：
# 裸可执行文件会以 CRImageReaderError 9 直接失败。因此工具统一装进 .app 再运行。
# Vision 的 Accurate 识别会通过 CoreImage/Metal 载入预编译二进制归档。
# 在受限沙箱里，"全新 bundle 标识"第一次初始化这份归档可能失败
# （异常出在 Metal 的 recordBinaryArchiveUsage:，与译芽代码无关），
# 因此 bundle 标识允许用 FY_CAPTURE_CARD_BUNDLE_ID 覆盖。
# 正常终端/正式应用没有这个限制，默认用项目自己的标识即可。
FY_CAPTURE_CARD_BUNDLE_ID="${FY_CAPTURE_CARD_BUNDLE_ID:-com.nanami.yiya.capture-card-ocr-check}"

bundle_tool() { # bundle_tool <工具源文件> <可执行名> <bundle 名> <bundle id> <相机用途说明>
  local source="$1" exe="$2" name="$3" identifier="$4" camera_note="$5"
  local bundle="$OUT/$name.app"
  local binary="$bundle/Contents/MacOS/$exe"
  # 复用已签名的 bundle：ad-hoc 签名重编后 cdhash 变化会让相机权限授权失效，
  # 因此只有工具源码变了（或显式 FY_CAPTURE_CARD_FORCE_REBUILD=1）才重建。
  if [ -x "$binary" ] && [ -z "${FY_CAPTURE_CARD_FORCE_REBUILD:-}" ] &&
     [ -z "$(find "$ROOT_DIR/tools" "$ROOT_DIR/objc" -name '*.m' -newer "$binary" -print -quit 2>/dev/null)" ]; then
    xattr -cr "$bundle" 2>/dev/null || true
    echo "$bundle"
    return 0
  fi
  build "$source" "$exe"
  rm -rf "$bundle"
  mkdir -p "$bundle/Contents/MacOS"
  cp "$OUT/$exe" "$bundle/Contents/MacOS/$exe"
  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$exe</string>
  <key>CFBundleIdentifier</key><string>$identifier</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSCameraUsageDescription</key><string>$camera_note</string>
</dict>
</plist>
PLIST
  # LaunchServices/Finder 可能留下扩展属性，codesign 会因此拒绝。
  xattr -cr "$bundle" 2>/dev/null || true
  # 用与 install-app.sh 相同的稳定 designated requirement：
  # ad-hoc 签名每次重编 cdhash 都变，只有基于标识的需求才能让相机权限授权跨重编保留。
  codesign --force --deep --sign - --identifier "$identifier" \
    --requirements "=designated => identifier \"$identifier\"" "$bundle" >/dev/null
  echo "$bundle"
}

MODE="${1:-offline}"

if [ "$MODE" = "offline" ]; then
  FRAME="${2:-$ROOT_DIR/.build/clean-video-probe/capture-20261005T110436.662741Z/frame-02.png}"
  if [ "$#" -ge 4 ]; then REQUIRED="$4"; elif [ "$#" -ge 2 ]; then REQUIRED=""; else REQUIRED="ミヨは占いに凝ってんの。"; fi
  if [ ! -f "$FRAME" ]; then
    echo "找不到已验证的采集帧 $FRAME" >&2
    echo "它来自独立验证程序 .build/clean-video-probe/CleanVideoProbe.m；没有它就不能核对采集卡输入。" >&2
    exit 1
  fi
  CHECK_APP="$(bundle_tool "$ROOT_DIR/tools/CaptureCardOcrCheck.m" CaptureCardOcrCheck 译芽采集卡离线核对 "$FY_CAPTURE_CARD_BUNDLE_ID" "离线核对工具不访问相机。")"
  REPORT="$OUT/offline-ocr-check.log"
  # 经 LaunchServices 启动：Accurate 识别要求调用方是有 bundle 身份的签名应用。
  rm -rf /tmp/yiya-capture-card-check
  mkdir -p /tmp/yiya-capture-card-check
  chmod 700 /tmp/yiya-capture-card-check
  # 同一句对白：录制条遮挡时现场读到的是残句「ミヨは、」，采集卡帧必须读到完整句。
  python3 -c 'import json, sys
print(json.dumps({
    "image": sys.argv[1],
    "require_line": sys.argv[2],
    "dialogue_contains": sys.argv[3],
    "fast": sys.argv[4] == "1",
    "report": sys.argv[5],
}))' "$FRAME" "$REQUIRED" "$REQUIRED" "${FY_CAPTURE_CARD_FAST_OCR:+1}0" "$REPORT" > /tmp/yiya-capture-card-check/request.json
  rm -f "$REPORT"
  open -W -n "$CHECK_APP"
  cat "$REPORT" 2>/dev/null || echo "离线核对没有生成报告"
  grep -q "^PASS" "$REPORT" 2>/dev/null || { echo "离线核对失败" >&2; exit 1; }
  echo "离线核对通过：真实画面经生产 OCR／对白提取完成（报告 ${REPORT}）。"
  exit 0
fi

if [ "$MODE" != "inspect" ] && [ "$MODE" != "authorize" ] && [ "$MODE" != "authorize-ui" ] && [ "$MODE" != "capture" ]; then
  echo "未知子命令: $MODE" >&2
  exit 2
fi

if [ "${FY_CAPTURE_CARD_ALLOW_HARDWARE:-0}" != "1" ]; then
  echo "BLOCKED: 真实采集卡/相机权限验证会使用硬件并可能弹出系统权限提示。" >&2
  echo "确认桌面与设备空闲后，用 FY_CAPTURE_CARD_ALLOW_HARDWARE=1 重新运行本命令。" >&2
  exit 86
fi

BUNDLE="$(bundle_tool "$ROOT_DIR/tools/CaptureCardProbe.m" CaptureCardProbe 译芽采集卡探针 com.nanami.yiya.capture-card-probe "探针只读取你指定的采集卡画面用于本地核对，不录制、不保存视频、不使用麦克风。")"
# open 经 LaunchServices 启动后系统会往 bundle 上写扩展属性，验签前再清一次。
xattr -cr "$BUNDLE" 2>/dev/null || true
codesign --verify --strict "$BUNDLE"

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yiya-capture-card-XXXXXX")"
chmod 700 "$RUN_DIR"

# 经 LaunchServices 启动探针：只有这样才能让相机授权按探针自己的身份生效。
# 直接从终端跑子进程时 TCC 会归到父进程名下，读出来的授权状态是错的。
run_probe_ui() { # run_probe_ui <mode> <设备名|空> <帧数|空> <输出目录>
  local mode="$1" device="${2:-}" frames="${3:-}" dir="$4"
  rm -rf /tmp/yiya-capture-card-probe
  mkdir -p /tmp/yiya-capture-card-probe
  chmod 700 /tmp/yiya-capture-card-probe
  python3 -c 'import json, sys
mode, device, frames, directory = sys.argv[1:5]
request = {"mode": mode, "directory": directory}
if device:
    request["device_name"] = device
if frames:
    request["frames"] = int(frames)
print(json.dumps(request))' "$mode" "$device" "$frames" "$dir" > /tmp/yiya-capture-card-probe/request.json
  rm -f "$dir/status.json"
  open -W -n "$BUNDLE"
}

if [ "$MODE" = "inspect" ]; then
  run_probe_ui inspect "" "" "$RUN_DIR"
  echo "证据目录: $RUN_DIR"
  cat "$RUN_DIR/status.json"
  exit 0
fi

if [ "$MODE" = "authorize" ]; then
  echo "接下来系统会询问相机权限；请允许「译芽采集卡探针」。"
  set +e
  "$BUNDLE/Contents/MacOS/CaptureCardProbe" authorize "$RUN_DIR"
  CODE=$?
  set -e
  echo "证据目录: $RUN_DIR"
  cat "$RUN_DIR/status.json"
  exit "$CODE"
fi

if [ "$MODE" = "authorize-ui" ]; then
  echo "即将弹出相机权限提示，请点「允许」：译芽采集卡探针"
  run_probe_ui authorize "" "" "/tmp/yiya-capture-card-probe"
  echo "状态："
  cat /tmp/yiya-capture-card-probe/status.json 2>/dev/null || echo "没有生成状态文件"
  exit 0
fi

DEVICE="${2:?用法: capture <设备显示名> [帧数]}"
FRAMES="${3:-3}"
run_probe_ui capture "$DEVICE" "$FRAMES" "$RUN_DIR"
echo "证据目录: $RUN_DIR"
cat "$RUN_DIR/status.json"
