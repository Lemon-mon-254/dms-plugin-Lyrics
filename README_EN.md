# LyricsEmbed

> A synced lyrics plugin focused on **embedded lyrics**, a fork of [xubuyuan18/dms-plugin-Lyrics](https://github.com/xubuyuan18/dms-plugin-Lyrics). Original upstream author: [gasiyu/dms-plugin-musiclyrics](https://github.com/gasiyu/dms-plugin-musiclyrics).

[中文文档](README.md) | **English**

## ✨ Features

### 🎵 Embedded Lyrics First
- Extract LRC lyrics from `LYRICS`/`USLT` tags in music file metadata, import into local cache
- Incremental: skips already-cached songs, **never overwrites manually calibrated lyric offsets**
- Customizable music library path (default `$HOME/Music`)

### 🔄 Multiple Sources
- Custom API → Local Cache → Netease Music → lrclib.net
- Variables supported: `{title}`, `{artist}`, `{album}`

### 🌐 Bilingual Lyrics
- `Original|Translation`: joins two lines with the same timestamp into one
- `Original only` / `Translation only`: auto-detects the original via Japanese kana
- Split-center mode: original on the left, translation on the right

### 🎚️ Lyric Offset Tuning
- `-` / `+` buttons in the toolbar step by 0.1s
- Offsets are saved per-song and restored automatically on next play

### 🎸 More
- Vinyl record spinning cover popup, playback controls, real-time MPRIS sync
- Blocklist filtering, player whitelist, world clock when idle
- Firefox video / MV auto-detection

## 📸 Screenshot

![LyricsEmbed popup](docs/screenshot.png)

## Interface Language

The plugin supports Chinese and English. Open the plugin **Settings → Language** and choose:
- Follow System (default)
- Chinese
- English

The setting applies to the plugin UI including the settings page immediately.

## 📦 Install

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/Lemon-mon-254/dms-plugin-Lyrics.git LyricsEmbed
dms ipc call plugins reload lyricsEmbed
```

> If `dms ipc plugins reload` does not work, restart DankMaterialShell.

Requires `ffprobe` (ffmpeg suite) for embedded lyric extraction:

```bash
sudo pacman -S ffmpeg
```

## 📁 Project Structure

```
LyricsEmbed/
├── Lyrics.qml                    # Main component: fetching, UI, playback controls, offsets
├── LyricsSettings.qml            # Settings UI
├── import-embedded-lyrics.sh     # Embedded lyric import script
├── plugin.json                   # Plugin config
├── docs/
│   └── screenshot.png            # Plugin screenshot
├── README.md
└── LICENSE
```

## ⚙️ Configuration

| Category | Option | Description |
|------|------|------|
| Language | Interface Language | Follow System / Chinese / English |
| Display | Cover Position | Left / Right / Split-Center (dual bilingual) |
| Display | Lyric Translation | `Original\|Translation` / Original only / Translation only |
| Display | Ellipsize Long Lyrics | Truncate long lines with ellipsis |
| Display | Auto Spin Cover | Rotate status bar cover while playing |
| Display | Show Clock When Idle | Show H:M:S when nothing is playing |
| Display | World Clock Timezones | Popup timezone list (name:UTC offset, comma separated) |
| Display | Blocklist | Hide lyric lines containing any keyword |
| Display | Player Whitelist | Only detect listed players; empty = all |
| Cache | Music Library Path | Directory scanned for embedded lyrics (default `$HOME/Music`) |
| Cache | Local Cache | Store downloaded lyrics to disk |
| Built-in | Netease Music | Preferred; better for Chinese songs |
| Built-in | lrclib.net | Open-source backup source |
| Custom API | URL / Method | Supports `{title}`, `{artist}`, `{album}` |

**Fetch order**: Custom API → Local Cache → Netease Music → lrclib.net

### Custom API

- **URL format**: `https://api.example.com/lyrics?title={title}&artist={artist}&album={album}`
- **Method**: GET or POST
- **Response**: any of `lyrics` / `lyric` / `lrc` / `content` / `data` contains the LRC text

**Example**:
```
https://lrclib.net/api/get?track_name={title}&artist_name={artist}
```

## 📝 Usage

### Import Embedded Lyrics
1. Set the 「Music Library Path」in settings (default `$HOME/Music`)
2. Click **Import Lyrics** in the popup toolbar, or **Import Embedded Lyrics** in the settings page
3. Already-cached songs are skipped and manual offsets are preserved

### Lyric Offset Tuning
1. Open the popup panel, use `-` / `+` in the toolbar (0.1s per step)
2. Click the save button (💾) once aligned — written to that song's cache
3. Restored automatically on next play, remembered per song

## 🧠 Implementation Details

### Fetch Flow
1. Detect track changes (MPRIS)
2. Fetch order: Custom API → Cache → Netease → lrclib
3. Parse LRC and build a time index
4. Poll the playback position and match the current line

### Album Matching
```
1. Exact title + album match
2. Exact title (case/space-insensitive)
3. Fuzzy title + album match
4. Fuzzy title (containment)
5. Fall back to the first result
```

### Cache Format
- Path: `~/.cache/Lyrics/`
- Filename: `fnv1a32(title + "\0" + artist).json`
- Content: `{lines, source, cachedAt, offset}`

### Instrumental Detection
Lines containing these markers are filtered automatically:
- 纯音乐，请欣赏
- Instrumental
- 无歌词 / 暂无歌词

## 📜 Credits

- Fork of: [xubuyuan18/dms-plugin-Lyrics](https://github.com/xubuyuan18/dms-plugin-Lyrics)
- Upstream: [gasiyu/dms-plugin-musiclyrics](https://github.com/gasiyu/dms-plugin-musiclyrics)

## 🔒 License

[MIT](./LICENSE)