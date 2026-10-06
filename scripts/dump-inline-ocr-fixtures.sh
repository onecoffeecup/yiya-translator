#!/usr/bin/env bash
# 把真实截图跑一遍**生产同配置**的 Vision OCR，导出贴译布局验证用的夹具 JSON。
# 只读图片、不启动应用、不访问网络、不读写用户设置与学习库。
#
#   bash scripts/dump-inline-ocr-fixtures.sh
#
# 产物：
#   .build/inline-layout/InlineOcrDump                    编译出的工具
#   .build/inline-layout/fixtures/<basename>.json         每张图的 OCR 夹具
#   .build/inline-layout/inputs/                          仅当原图最长边 > 2000 时的等比缩放副本
#   .build/inline-layout/home/                            CFFIXED_USER_HOME（见下），只放偏好文件
#
# 语言可用环境变量覆盖（默认 ja-JP）：FY_INLINE_OCR_LANG=en-US bash scripts/dump-inline-ocr-fixtures.sh
# 幂等：每次重新编译工具、覆盖写入夹具，可重复运行。
#
# CFFIXED_USER_HOME：Vision 的 Accurate 识别经 CoreImage/Metal 预处理，
# Metal 记录 binary archive 使用情况时要用 CFPreferences 读写用户偏好。
# 在受限文件沙箱（真实 ~/Library/Preferences 不可写）里，裸可执行文件会以
# CRImageReaderError 9 失败、或崩在 _MTLDevice recordBinaryArchiveUsage:。
# 把偏好目录指到 .build 内的可写目录即可；工具源码与生产 OCR 配置都不改。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.build/inline-layout"
FIXTURE_DIR="$OUT_DIR/fixtures"
INPUT_DIR="$OUT_DIR/inputs"
MODULE_CACHE="$OUT_DIR/module-cache"
TOOL="$OUT_DIR/InlineOcrDump"
PREF_HOME="$OUT_DIR/home"
LANG_CODE="${FY_INLINE_OCR_LANG:-ja-JP}"
# 夹具里的框是归一化坐标，缩放只影响像素密度，不影响归一化结果；
# 但过大的图会让 Vision 变慢，所以最长边超过这个值就先等比缩小。
MAX_EDGE=2000

mkdir -p "$OUT_DIR" "$FIXTURE_DIR" "$MODULE_CACHE" "$PREF_HOME/Library/Preferences" "$PREF_HOME/Library/Caches"

echo "编译 InlineOcrDump → $TOOL"
clang -fobjc-arc -fmodules -fmodules-cache-path="$MODULE_CACHE" \
  -mmacosx-version-min=13.0 -Wall \
  "$ROOT_DIR/tools/InlineOcrDump.m" -o "$TOOL" \
  -framework Foundation -framework CoreGraphics -framework ImageIO -framework Vision

# 必填输入：真实采集卡帧（1920×1080 真实游戏画面）。
REQUIRED_IMAGES=(
  "$ROOT_DIR/.build/capture-card-check/hardware-capture-20261005/frame-01.png"
  "$ROOT_DIR/.build/capture-card-check/hardware-capture-20261005/frame-02.png"
  "$ROOT_DIR/.build/capture-card-check/hardware-capture-20261005/frame-03.png"
)
# 可选输入：界面参考图（存在才导出）。
OPTIONAL_IMAGES=(
  "$ROOT_DIR/docs/design/yiya-reference-preview/production/yiya-inline-news.png"
)

SCALED_NOTES=()
DUMPED_FILES=()
MISSING_REQUIRED=0

image_size() { # image_size <图片> → "宽 高"
  sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null |
    awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if (w && h) print w, h}'
}

# 把实际送进 OCR 的图片路径写进全局 PREPARED_INPUT；过大的图先等比缩放到 $INPUT_DIR。
# 用全局变量而不是 stdout 返回，是因为缩放说明要累加到 SCALED_NOTES，
# 而 $(...) 命令替换里的数组修改只发生在子 shell 里。
PREPARED_INPUT=""
prepare_input() { # prepare_input <源图>
  local source="$1"
  local base
  base="$(basename "$source")"
  local width height
  read -r width height <<<"$(image_size "$source")"
  if [ -z "${width:-}" ] || [ -z "${height:-}" ]; then
    echo "  读取尺寸失败，按原图处理: ${source}" >&2
    PREPARED_INPUT="$source"
    return 0
  fi
  local longest=$width
  if [ "$height" -gt "$longest" ]; then longest=$height; fi
  if [ "$longest" -le "$MAX_EDGE" ]; then
    PREPARED_INPUT="$source"
    return 0
  fi
  local scaled="$INPUT_DIR/$base"
  mkdir -p "$INPUT_DIR"
  sips -Z "$MAX_EDGE" "$source" --out "$scaled" >/dev/null
  local scaled_size
  scaled_size="$(image_size "$scaled")"
  SCALED_NOTES+=("$base: ${width}x${height} → ${scaled_size// /x}（sips -Z ${MAX_EDGE}，已写入 ${scaled}）")
  PREPARED_INPUT="$scaled"
}

dump_one() { # dump_one <源图>
  local source="$1"
  local base
  base="$(basename "$source")"
  base="${base%.*}"
  local json="$FIXTURE_DIR/$base.json"
  local input
  prepare_input "$source"
  input="$PREPARED_INPUT"
  env CFFIXED_USER_HOME="$PREF_HOME" "$TOOL" "$input" --lang "$LANG_CODE" >"$json"
  local count
  count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1], encoding="utf-8"))["lines"]))' "$json")"
  local bytes
  bytes="$(wc -c <"$json" | tr -d ' ')"
  DUMPED_FILES+=("$json")
  echo "  $base: $count 行 → fixtures/$base.json（$bytes 字节）"
}

echo "OCR 语言: $LANG_CODE"
echo "输入图片："
for source in "${REQUIRED_IMAGES[@]}"; do
  if [ ! -f "$source" ]; then
    echo "错误: 缺少必填采集帧 $source" >&2
    MISSING_REQUIRED=1
    continue
  fi
  dump_one "$source"
done
for source in "${OPTIONAL_IMAGES[@]}"; do
  if [ ! -f "$source" ]; then
    echo "  （可选图不存在，跳过）${source#"$ROOT_DIR"/}"
    continue
  fi
  dump_one "$source"
done

if [ "$MISSING_REQUIRED" -ne 0 ]; then
  echo "失败: 必填采集帧缺失，夹具不完整。" >&2
  exit 1
fi

if [ "${#SCALED_NOTES[@]}" -gt 0 ]; then
  echo "缩放说明："
  for note in "${SCALED_NOTES[@]}"; do echo "  - $note"; done
fi

echo "完成：${#DUMPED_FILES[@]} 份夹具 → ${FIXTURE_DIR}"
for json in "${DUMPED_FILES[@]}"; do
  echo "  $(wc -c <"$json" | tr -d ' ') 字节  ${json#"$ROOT_DIR"/}"
done
