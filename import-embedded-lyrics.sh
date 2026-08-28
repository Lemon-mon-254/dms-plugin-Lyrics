#!/bin/bash
# 从音乐文件中提取内嵌歌词并保存到 ~/.cache/Lyrics/
# 用法: import-embedded-lyrics.sh /path/to/music/dir

CACHE_DIR="$HOME/.cache/Lyrics"
MUSIC_DIR="${1:-$HOME/Music}"
SUPPORTED_EXT="flac|mp3|ogg|m4a|wma|aac|opus|ape|wav"

mkdir -p "$CACHE_DIR"

# FNV-1a32 哈希函数
fnv1a32() {
    echo -n "$1" | python3 -c "
import sys
data = sys.stdin.buffer.read()
h = 0x811c9dc5
for b in data:
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
print(f'{h:08x}')
"
}

count=0
skipped=0

find "$MUSIC_DIR" -type f \( -iname "*.flac" -o -iname "*.mp3" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.wma" -o -iname "*.aac" -o -iname "*.opus" -o -iname "*.ape" -o -iname "*.wav" \) | while read -r file; do
    # 提取标题和艺术家
    metadata=$(ffprobe -v quiet -print_format json -show_format "$file" 2>/dev/null)
    title=$(echo "$metadata" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() == 'TITLE':
        print(tags[k]); break
" 2>/dev/null)
    artist=$(echo "$metadata" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() == 'ARTIST':
        print(tags[k]); break
" 2>/dev/null)

    # 跳过没有标题的文件
    if [ -z "$title" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    # 提取内嵌歌词（LYRICS / UNSYNCEDLYRICS 标签，不区分大小写）
    lyrics=$(echo "$metadata" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tags = d.get('format', {}).get('tags', {})
for k in tags:
    if k.upper() in ('LYRICS', 'UNSYNCEDLYRICS'):
        print(tags[k]); break
" 2>/dev/null)

    # 跳过没有歌词的文件
    if [ -z "$lyrics" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    # 生成缓存键（与 Lyrics.qml 一致）
    key_input="${title}\x00${artist}"
    cache_key=$(fnv1a32 "$(echo -e "$key_input" | tr '[:upper:]' '[:lower:]')")
    cache_file="$CACHE_DIR/${cache_key}.json"

    # 跳过已缓存的文件
    if [ -f "$cache_file" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    # 解析 LRC 格式歌词
    lrc_lines=$(echo "$lyrics" | python3 -c "
import sys, re, json

text = sys.stdin.read()
lines = []
for line in text.splitlines():
    line = line.strip()
    if not line:
        continue
    # 匹配 [mm:ss.xx] 格式
    m = re.findall(r'\[(\d+):(\d+\.?\d*)\]', line)
    content = re.sub(r'\[\d+:\d+\.?\d*\]', '', line).strip()
    if not content:
        continue
    if m:
        for time_str in m:
            mins, secs = time_str
            time_val = int(mins) * 60 + float(secs)
            lines.append({'time': round(time_val, 2), 'text': content})
    elif lines:
        # 没有时间戳的行，继承上一行的时间
        lines.append({'time': lines[-1]['time'], 'text': content})

# 去重
seen = set()
unique = []
for l in lines:
    key = (l['time'], l['text'])
    if key not in seen:
        seen.add(key)
        unique.append(l)

print(json.dumps(unique))
" 2>/dev/null)

    # 跳过解析失败的
    if [ -z "$lrc_lines" ] || [ "$lrc_lines" = "[]" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    # 写入缓存（保留已有 offset，避免覆盖手动校准的歌词偏移）
    python3 -c "
import json
lines = json.loads('''$lrc_lines''')
offset = 0
try:
    with open('$cache_file', encoding='utf-8') as f:
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
with open('$cache_file', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
" 2>/dev/null

    count=$((count + 1))
    echo "OK: $title - $artist ($cache_key.json)"
done

echo ""
echo "完成: 导入 $count 首，跳过 $skipped 首"
