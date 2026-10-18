#!/bin/bash
# 从音乐文件中提取内嵌歌词并保存到 ~/.cache/Lyrics/
# 用法: import-embedded-lyrics.sh [音乐目录]
# 依赖: ffprobe (ffmpeg), python3

set -u

CACHE_DIR="${HOME:-$PWD}/.cache/Lyrics"
MUSIC_DIR="${1:-${HOME:-$PWD}/Music}"

err() {
    echo "错误: $*" >&2
}

if ! command -v ffprobe >/dev/null 2>&1; then
    err "未找到 ffprobe，请先安装 ffmpeg"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    err "未找到 python3"
    exit 1
fi
if [ ! -d "$MUSIC_DIR" ]; then
    err "音乐目录不存在: $MUSIC_DIR"
    exit 1
fi
if ! mkdir -p "$CACHE_DIR"; then
    err "无法创建缓存目录: $CACHE_DIR"
    exit 1
fi
if [ ! -w "$CACHE_DIR" ]; then
    err "缓存目录不可写: $CACHE_DIR"
    exit 1
fi

# 输出 "<可读文件名>\t<缓存键>"。
# 键算法必须与 Lyrics.qml 的 _cacheKey 完全一致：小写后按 UTF-16 code unit 做 FNV-1a。
cache_info() {
    python3 - "$1" "$2" <<'PY'
import re
import sys

title, artist = sys.argv[1], sys.argv[2]


def sanitize(name):
    if not name:
        return ''
    name = re.sub(r'[\\/\x00-\x1f\x7f]', '_', name).strip()
    if name.startswith('.'):
        name = '_' + name[1:]
    return name or 'untitled'


readable = sanitize(title) + ' - ' + sanitize(artist)
if len(readable.encode('utf-8')) > 190:
    out = ''
    size = 0
    for ch in readable:
        n = len(ch.encode('utf-8'))
        if size + n > 190:
            break
        out += ch
        size += n
    readable = out + '...'

units = (title + '\x00' + artist).lower().encode('utf-16-le', 'surrogatepass')
h = 0x811c9dc5
for i in range(0, len(units), 2):
    code_unit = units[i] | (units[i + 1] << 8)
    h = ((h ^ code_unit) * 0x01000193) & 0xFFFFFFFF

print(f'{readable}\t{h:08x}')
PY
}

FILE_LIST=$(mktemp "${TMPDIR:-/tmp}/lyrics-import.XXXXXX") || {
    err "无法创建临时文件"
    exit 1
}
trap 'rm -f "$FILE_LIST"' EXIT

if ! find "$MUSIC_DIR" -type f \( \
        -iname "*.flac" -o -iname "*.mp3" -o -iname "*.ogg" -o \
        -iname "*.m4a" -o -iname "*.wma" -o -iname "*.aac" -o \
        -iname "*.opus" -o -iname "*.ape" -o -iname "*.wav" \
    \) -print0 > "$FILE_LIST"; then
    err "扫描音乐目录失败: $MUSIC_DIR"
    exit 1
fi

if [ ! -s "$FILE_LIST" ]; then
    echo "未在 $MUSIC_DIR 找到音频文件"
    echo ""
    echo "完成: 导入 0 首，跳过 0 首"
    exit 0
fi

count=0
skipped=0
errors=0

while IFS= read -r -d '' file; do
    if ! metadata=$(ffprobe -v quiet -print_format json -show_format "$file" 2>/dev/null) \
            || [ -z "$metadata" ]; then
        echo "警告: ffprobe 无法读取: $file" >&2
        errors=$((errors + 1))
        continue
    fi

    if ! title=$(printf '%s' "$metadata" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() == 'TITLE':
        print(tags[k]); break
" 2>/dev/null); then
        echo "警告: 无法解析标题: $file" >&2
        errors=$((errors + 1))
        continue
    fi

    artist=$(printf '%s' "$metadata" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() == 'ARTIST':
        print(tags[k]); break
" 2>/dev/null) || artist=""

    if [ -z "$title" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    lyrics=$(printf '%s' "$metadata" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() in ('LYRICS', 'UNSYNCEDLYRICS', 'USLT', 'LYRIC'):
        print(tags[k]); break
" 2>/dev/null) || lyrics=""

    if [ -z "$lyrics" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    if ! cache_info_output=$(cache_info "$title" "$artist"); then
        echo "警告: 无法生成缓存键: $title - $artist" >&2
        errors=$((errors + 1))
        continue
    fi
    IFS=$'\t' read -r cache_name cache_key <<< "$cache_info_output"
    if [ -z "$cache_name" ] || [ -z "$cache_key" ]; then
        echo "警告: 缓存键为空: $title - $artist" >&2
        errors=$((errors + 1))
        continue
    fi
    cache_file="$CACHE_DIR/${cache_name}_${cache_key}.json"
    legacy_file="$CACHE_DIR/${cache_key}.json"

    if [ -f "$cache_file" ] || [ -f "$legacy_file" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    if ! lrc_json=$(printf '%s' "$lyrics" | python3 -c "
import json, re, sys

text = sys.stdin.read()
time_re = re.compile(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]')
meta_re = re.compile(r'^\s*\[[a-zA-Z#]+:.*\]\s*$')
credit_re = re.compile(
    r'^(?:作词|作曲|编曲|制作人|制作|出品|发行|监制|混音|母带|录音|和声|演唱|原唱|词|曲)\s*[:：]'
    r'|^(?:lyrics?|lyricist|composer|composed|arranger|arranged|producer|mixed|mastered|written|music)\b(?:\s+by)?\s*[:：]',
    re.I,
)
timed = []
plain = []

for raw in text.splitlines():
    line = raw.strip()
    if not line or meta_re.match(line):
        continue
    matches = list(time_re.finditer(line))
    content = time_re.sub('', line).strip()
    if not content or credit_re.match(content):
        continue
    if matches:
        for m in matches:
            fraction = m.group(3) or ''
            if len(fraction) == 1:
                millis = int(fraction) * 100
            elif len(fraction) == 2:
                millis = int(fraction) * 10
            elif len(fraction) == 3:
                millis = int(fraction)
            else:
                millis = 0
            timed.append({
                'time': round(int(m.group(1)) * 60 + int(m.group(2)) + millis / 1000, 2),
                'text': content,
            })
    elif timed:
        # 无时间戳的续行（常见于翻译）沿用上一行时间，交给 QML 的同时间组合并
        timed.append({'time': timed[-1]['time'], 'text': content})
    else:
        plain.append(content)

lines = timed if timed else [{'time': 0, 'text': line} for line in plain]
if timed:
    # QML 播放进度按时间倒序查找，缓存行必须按时间升序排列
    lines.sort(key=lambda item: item['time'])
    seen = set()
    unique = []
    for line in lines:
        key = (line['time'], line['text'])
        if key not in seen:
            seen.add(key)
            unique.append(line)
    lines = unique

print(json.dumps({'lines': lines, 'plain': not timed}, ensure_ascii=False))
" 2>/dev/null); then
        echo "警告: 歌词解析失败: $title - $artist" >&2
        errors=$((errors + 1))
        continue
    fi

    printf '%s' "$lrc_json" | LY_CACHE_FILE="$cache_file" python3 -c "
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

data = json.load(sys.stdin)
lines = data.get('lines') or []
if not lines:
    raise SystemExit(2)
cache_file = os.environ['LY_CACHE_FILE']
offset = 0
try:
    with open(cache_file, encoding='utf-8') as f:
        old = json.load(f)
    if isinstance(old.get('offset'), (int, float)):
        offset = old['offset']
except Exception:
    pass

payload = {
    'lines': lines,
    'source': 5,
    'cachedAt': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'offset': offset,
    'plain': bool(data.get('plain')),
}

tmp_path = None
try:
    fd, tmp_path = tempfile.mkstemp(prefix='.tmp-', dir=os.path.dirname(cache_file) or '.')
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, cache_file)
except Exception as e:
    if tmp_path:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
    print(f'写入缓存失败: {e}', file=sys.stderr)
    raise SystemExit(1)
" 2>/dev/null
    write_status=${PIPESTATUS[1]}
    if [ "$write_status" -ne 0 ]; then
        if [ "$write_status" -eq 2 ]; then
            skipped=$((skipped + 1))
        else
            echo "警告: 写入缓存失败: $title - $artist" >&2
            errors=$((errors + 1))
        fi
        continue
    fi

    count=$((count + 1))
    echo "OK: $title - $artist (${cache_name}_${cache_key}.json)"
done < "$FILE_LIST"

echo ""
echo "完成: 导入 $count 首，跳过 $skipped 首"
if [ "$errors" -gt 0 ]; then
    echo "有 $errors 个文件处理失败" >&2
    exit 1
fi
