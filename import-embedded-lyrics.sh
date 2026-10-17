#!/bin/bash
# 从音乐文件中提取内嵌歌词并保存到 ~/.cache/Lyrics/
# 用法: import-embedded-lyrics.sh [音乐目录]
# 依赖: ffprobe (ffmpeg), python3

CACHE_DIR="$HOME/.cache/Lyrics"
MUSIC_DIR="${1:-$HOME/Music}"

mkdir -p "$CACHE_DIR"

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

count=0
skipped=0

while IFS= read -r -d '' file; do
    metadata=$(ffprobe -v quiet -print_format json -show_format "$file" 2>/dev/null)

    title=$(printf '%s' "$metadata" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() == 'TITLE':
        print(tags[k]); break
" 2>/dev/null)
    artist=$(printf '%s' "$metadata" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() == 'ARTIST':
        print(tags[k]); break
" 2>/dev/null)

    if [ -z "$title" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    lyrics=$(printf '%s' "$metadata" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() in ('LYRICS', 'UNSYNCEDLYRICS', 'USLT', 'LYRIC'):
        print(tags[k]); break
" 2>/dev/null)

    if [ -z "$lyrics" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    IFS=$'\t' read -r cache_name cache_key <<< "$(cache_info "$title" "$artist")"
    if [ -z "$cache_name" ] || [ -z "$cache_key" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    cache_file="$CACHE_DIR/${cache_name}_${cache_key}.json"
    legacy_file="$CACHE_DIR/${cache_key}.json"

    if [ -f "$cache_file" ] || [ -f "$legacy_file" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    lrc_lines=$(printf '%s' "$lyrics" | python3 -c "
import sys, re, json

text = sys.stdin.read()
lines = []
for line in text.splitlines():
    line = line.strip()
    if not line:
        continue
    m = re.findall(r'\[(\d+):(\d+\.?\d*)\]', line)
    content = re.sub(r'\[\d+:\d+\.?\d*\]', '', line).strip()
    if not content:
        continue
    if m:
        for mins, secs in m:
            time_val = int(mins) * 60 + float(secs)
            lines.append({'time': round(time_val, 2), 'text': content})
    elif lines:
        lines.append({'time': lines[-1]['time'], 'text': content})

seen = set()
unique = []
for line in lines:
    key = (line['time'], line['text'])
    if key not in seen:
        seen.add(key)
        unique.append(line)

print(json.dumps(unique))
" 2>/dev/null)

    if [ -z "$lrc_lines" ] || [ "$lrc_lines" = "[]" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    # 写入缓存，保留已有 offset 以免覆盖手动校准
    LY_CACHE_FILE="$cache_file" && export LY_CACHE_FILE && printf '%s' "$lrc_lines" | python3 -c "
import json
import os
import sys
lines = json.load(sys.stdin)
cache_file = os.environ['LY_CACHE_FILE']
offset = 0
try:
    with open(cache_file, encoding='utf-8') as f:
        old = json.load(f)
    if isinstance(old.get('offset'), (int, float)):
        offset = old['offset']
except Exception:
    pass
data = {
    'lines': lines,
    'source': 4,
    'cachedAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'offset': offset
}
with open(cache_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
" 2>/dev/null

    count=$((count + 1))
    echo "OK: $title - $artist (${cache_name}_${cache_key}.json)"
done < <(find "$MUSIC_DIR" -type f \( -iname "*.flac" -o -iname "*.mp3" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wma" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.ape" -o -iname "*.wav" \) -print0)

echo ""
echo "完成: 导入 $count 首，跳过 $skipped 首"
