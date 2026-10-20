# LyricsEmbed

> 一款支持 **内嵌歌词导入** 的 DMS 同步歌词插件，基于 [xubuyuan18/dms-plugin-Lyrics](https://github.com/xubuyuan18/dms-plugin-Lyrics) 二次开发，上游原作者为 [gasiyu/dms-plugin-musiclyrics](https://github.com/gasiyu/dms-plugin-musiclyrics)。

**中文** | [English](README_EN.md)

![Version](https://img.shields.io/badge/version-1.7.5-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![DMS](https://img.shields.io/badge/DankMaterialShell-1.5+-purple)

## ✨ 特性

### 🎵 内嵌歌词导入
- 扫描音乐库，从 `LYRICS` / `UNSYNCEDLYRICS` / `USLT` / `LYRIC` 标签中提取歌词到本地缓存
- 同时支持 LRC 时间轴和多时间戳格式，以及没有时间轴的纯文本歌词
- 已缓存歌曲增量跳过，**不覆盖手动校准的歌词偏移**
- 导入后与普通缓存歌曲一样，直接读取内嵌歌词
- 音乐库路径可自定义（默认 `$HOME/Music`）

### 🔄 多源歌词
- 自定义 API（启用时）→ 本地缓存 → 网易云音乐 → lrclib.net
- 自定义 API 请求失败或无有效歌词时，会继续回退到缓存 → 网易云 → lrclib，不会直接跳到最后一个源
- 支持 LRC 多时间戳、`[mm:ss]` / `[mm:ss.xx]` / `[mm:ss.xxx]` 等格式，以及纯文本歌词
- 内嵌歌词通过手动导入写入本地缓存；自动获取仍从自定义 API 和缓存开始
- 支持变量 `{title}`、`{artist}`、`{album}`

### 🌐 双语歌词
- `原文|翻译`：同时间戳两行拼接为一行
- `仅原文` / `仅翻译`：自动识别原文和翻译
- 居中分栏模式：封面左侧原文、右侧翻译

### 🎚️ 歌词偏移微调
- 工具栏 `-` / `+` 按钮逐 0.1s 校准
- 停止调整 0.5s 后自动保存到单曲缓存，下次播放自动恢复（自定义 API 每次请求前也会先恢复该曲偏移）

### 🎸 其他
- 黑胶唱片旋转封面弹窗、播放控制、MPRIS 实时同步
- 屏蔽词过滤、播放器白名单、未播放时世界时钟
- 火狐浏览器视频 / MV 自动识别

## 📸 截图

![LyricsEmbed 弹窗](docs/screenshot.png)

## 📦 安装

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/Lemon-mon-254/dms-plugin-Lyrics.git LyricsEmbed
dms ipc call plugins reload lyricsEmbed
```

> 若 `dms ipc plugins reload` 无效，重启 DankMaterialShell 使插件生效。
>
> 需要 DankMaterialShell 1.5.0 或更高版本。

依赖 `ffprobe`（ffmpeg 套件）和 `python3`，用于内嵌歌词提取：

```bash
sudo pacman -S ffmpeg python
```

## 📁 项目结构

```
LyricsEmbed/
├── Lyrics.qml                    # 主组件：歌词获取、UI、播放控制、偏移微调
├── LyricsSettings.qml            # 设置界面
├── import-embedded-lyrics.sh     # 内嵌歌词导入脚本（扫描按钮调用）
├── plugin.json                   # 插件配置
├── docs/
│   └── screenshot.png            # 插件截图
├── README.md
└── LICENSE
```

## ⚙️ 配置

| 类别 | 选项 | 说明 |
|------|------|------|
| 显示 | 封面位置 | 靠左 / 靠右 / 居中分栏（左右双语） |
| 显示 | 歌词翻译 | `原文\|翻译` / `仅原文` / `仅翻译` |
| 显示 | 超长歌词截断 | 用省略号截断超长行 |
| 显示 | 封面自动旋转 | 状态栏封面是否播放时旋转 |
| 显示 | 未播放时显示时钟 | 空闲时显示当前时间 |
| 显示 | 世界时钟时区 | 弹窗时区列表（名称:UTC偏移量，逗号分隔） |
| 显示 | 屏蔽词 | 歌词行包含任一关键词则不显示 |
| 显示 | 播放器白名单 | 仅检测指定播放器，留空则全部 |
| 缓存 | 音乐库路径 | 扫描内嵌歌词的音乐库目录（默认 `$HOME/Music`） |
| 缓存 | 本地缓存 | 启用磁盘缓存，加速加载 |
| 内置源 | 网易云音乐 | 中文歌曲优先 |
| 内置源 | lrclib.net | 开源歌词库，后备源 |
| 自定义 API | 地址/方法 | 支持变量 `{title}`, `{artist}`, `{album}` |

**获取优先级**: 自定义 API（启用时）→ 本地缓存 → 网易云音乐 → lrclib.net。自定义 API 失败后会从缓存继续按内置源顺序回退。

### 自定义 API 配置

- **URL 格式**: `https://api.example.com/lyrics?title={title}&artist={artist}&album={album}`
- **请求方式**: GET 或 POST
- **响应格式**: `lyrics` / `lyric` / `lrc` / `content` / `data` 任一字段为 LRC 文本

**示例**:
```
https://lrclib.net/api/get?track_name={title}&artist_name={artist}
```

### 网络请求

- `lrclib.net`：歌曲名、歌手、专辑和时长
- `music.163.com`：用歌曲名和歌手搜索（最多 10 条结果），在本地校验标题、歌手、专辑和时长后，再用网易云歌曲 id 获取歌词（直连，不经过第三方代理）
- 启用自定义 API 时请求你配置的地址
- 不访问其他主机

## 📝 使用说明

### 内嵌歌词导入
1. 设置页配置「音乐库路径」（默认 `$HOME/Music`）
2. 弹窗工具栏点击「导入缓存」，或设置页点击「导入内嵌歌词到缓存」
3. 已有缓存歌曲自动跳过，不覆盖手动校准的偏移

### 歌词偏移微调
1. 打开弹出面板，工具栏点 `-` / `+`（每步 0.1s）
2. 停止调整 0.5s 后自动写入该歌曲缓存
3. 下次播放自动恢复，每首歌独立记忆

## 🧠 实现细节

### 歌词获取流程
1. 检测歌曲切换（MPRIS 事件）
2. 按优先级获取：自定义 API（启用时）→ 缓存 → 网易云 → lrclib
3. 解析 LRC 格式，建立时间索引；无时间戳时按纯文本处理
4. 定时轮询播放位置，匹配当前歌词行；纯文本固定显示首行
5. 请求回调和缓存读取都校验歌曲与请求代次，避免旧响应覆盖新曲目

### 网易云匹配算法
```
1. 用歌曲名和歌手搜索，最多取 10 条结果
2. 标题必须完全匹配或存在包含关系
3. 歌手有信息时必须匹配（支持多个歌手用 / 分隔）
4. 按标题精确度、歌手、专辑和时长打分
5. 选择得分最高的结果；没有合适结果时回退 lrclib
```

### 缓存格式
- 路径: `~/.cache/Lyrics/`
- 文件名: `<歌曲名> - <歌手>_<fnv1a32(title + "\0" + artist)>.json`，插件与导入脚本使用相同的键和可读前缀
- 旧版纯哈希文件名仍可读取，首次命中时会迁移为可读文件名
- 内容: `{lines, source, cachedAt, offset, plain}`；`plain: true` 表示纯文本歌词

### 纯音乐检测
自动过滤包含以下标记的歌词行：
- 纯音乐，请欣赏
- Instrumental
- 无歌词 / 暂无歌词

## 📜 致谢

- 原插件: [xubuyuan18/dms-plugin-Lyrics](https://github.com/xubuyuan18/dms-plugin-Lyrics)
- 上游项目: [gasiyu/dms-plugin-musiclyrics](https://github.com/gasiyu/dms-plugin-musiclyrics)

## 🔒 许可证

[MIT](./LICENSE)
