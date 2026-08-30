import Quickshell
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lyricsEmbed"

    // pluginData 快照（PluginSettings 基类未提供，此处自行维护）
    property var pluginData: ({})

    onPluginServiceChanged: root._loadPluginData(root.pluginService)

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root._loadPluginData(root.pluginService);
        }
    }

    function _loadPluginData(svc) {
        if (!svc || !root.pluginId)
            return;
        root.pluginData = SettingsData.getPluginSettingsForPlugin(root.pluginId);
    }

    // 设置页自身语言（跟随主组件）
    property string language: pluginData.language ?? "auto"
    readonly property bool _systemChinese: (Qt.locale().name || "").toLowerCase().startsWith("zh")
        || (Quickshell.env("LANG") || "").toLowerCase().startsWith("zh")

    // 英文界面开关（直接绑定 language，供属性绑定追踪）
    readonly property bool isEnglish: {
        var la = root.language;
        if (la === "auto")
            la = root._systemChinese ? "zh" : "en";
        return la === "en";
    }

    StyledText {
        width: parent.width
        text: root.isEnglish ? "Lyrics Settings" : "Lyrics 设置"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.isEnglish ? "Configure lyric behavior and sources" : "配置歌词行为和歌词源"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        id: languageRect
        width: parent.width
        height: languageColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: languageColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.isEnglish ? "Language" : "语言"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            SelectionSetting {
                settingKey: "language"
                label: root.isEnglish ? "Interface Language" : "界面语言"
                description: root.isEnglish ? "Switch the plugin interface language. Follow System uses the system language (Chinese/English)" : "切换插件界面语言。跟随系统将使用系统语言（中文/英文）"
                options: [
                    { label: root.isEnglish ? "Follow System" : "跟随系统", value: "auto" },
                    { label: root.isEnglish ? "Chinese" : "中文", value: "zh" },
                    { label: root.isEnglish ? "English" : "English", value: "en" }
                ]
                defaultValue: "auto"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: displayColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: displayColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.isEnglish ? "Display" : "显示设置"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            SelectionSetting {
                settingKey: "coverPosition"
                label: root.isEnglish ? "Cover Position" : "封面位置"
                description: root.isEnglish ? "Position of the album cover in the status bar. In split-center mode, original text is shown on the left and translation on the right" : "状态栏中专辑封面的位置。居中分栏模式在封面左侧显示原文、右侧显示翻译"
                options: [
                    { label: root.isEnglish ? "Left" : "靠左", value: "left" },
                    { label: root.isEnglish ? "Right" : "靠右", value: "right" },
                    { label: root.isEnglish ? "Split-Center" : "居中分栏", value: "center" }
                ]
                defaultValue: "left"
            }

            SelectionSetting {
                settingKey: "lyricLanguage"
                label: root.isEnglish ? "Lyric Translation" : "歌词翻译"
                description: root.isEnglish ? "How to display paired lines of bilingual lyrics with the same timestamp. Original|Translation joins two lines into one; Original-only auto-detects by Japanese kana" : "双语歌词的同时间戳两行如何显示。原文|翻译将两行拼为一行；仅原文按日文假名自动识别"
                options: [
                    { label: root.isEnglish ? "Original|Translation" : "原文|翻译", value: "both" },
                    { label: root.isEnglish ? "Original Only" : "仅原文", value: "original" },
                    { label: root.isEnglish ? "Translation Only" : "仅翻译", value: "translation" }
                ]
                defaultValue: "both"
            }

            ToggleSetting {
                settingKey: "lyricEllipsis"
                label: root.isEnglish ? "Ellipsize Long Lyrics" : "超长歌词用省略号截断"
                description: root.isEnglish ? "Truncate overly long lyric lines with an ellipsis; disable to show the full line" : "开启后过长的歌词行以省略号截断；关闭则完整显示整行"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "vinylSpin"
                label: root.isEnglish ? "Auto Spin Cover" : "封面自动旋转"
                description: root.isEnglish ? "Rotate the status bar album cover while playing" : "是否在播放时自动旋转状态栏中的专辑封面"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showClockWhenIdle"
                label: root.isEnglish ? "Show Clock When Idle" : "未播放时显示时钟"
                description: root.isEnglish ? "When nothing is playing, the status bar widget shows the current time (H:M:S)" : "没有正在播放的内容时，状态栏组件显示当前时间（时:分:秒）"
                defaultValue: false
            }

            ToggleSetting {
                settingKey: "useAlbumAccent"
                label: root.isEnglish ? "Card Colors Follow Album Art" : "卡片颜色跟随封面"
                description: root.isEnglish ? "Use the album art dominant color for popup card accents (play buttons, timeline, time text, clocks). Turn off to follow the theme color" : "弹窗卡片重点元素（播放按钮、进度条、时间、时钟等）使用当前封面主色；关闭则跟随主题颜色"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showStatusIndicators"
                label: root.isEnglish ? "Show Source Status Chips" : "显示歌曲来源状态标签"
                description: root.isEnglish ? "Show the NetEase / LRC / Cache / Instrumental status chips in the popup card" : "在弹窗卡片中显示网易 / LRC / 缓存 / 纯音乐 的状态标签"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "scrollWheelVolume"
                label: root.isEnglish ? "Scroll Wheel Volume" : "滚轮调音量"
                description: root.isEnglish ? "Scroll up/down on the status bar lyric pill to adjust the current player volume" : "在状态栏歌词胶囊上上下滚动鼠标滚轮调整当前播放器音量"
                defaultValue: true
            }

            StringSetting {
                settingKey: "clockTimezones"
                label: root.isEnglish ? "World Clock Timezones" : "世界时钟时区"
                description: root.isEnglish ? "Timezone list shown in the popup, format: name:UTC offset (e.g. Beijing:8). Use auto or pacific for automatic Pacific DST. Comma-separate multiple timezones" : "弹窗中显示的时区列表，格式：名称:UTC偏移量（如 北京时间:8）。偏移量写 auto 或 pacific 表示太平洋夏令时自动计算。逗号分隔多个时区"
                placeholder: "北京时间:8,东京时间:9,太平洋时间:auto,纽约时间:-5,伦敦时间:0"
                defaultValue: "中国时间:8,日本时间:9,太平洋时间:auto"
            }

            StringSetting {
                settingKey: "lyricBlocklist"
                label: root.isEnglish ? "Blocklist" : "屏蔽词"
                description: root.isEnglish ? "Lines containing any keyword are hidden; separate multiple with commas (e.g. composed by, arranged by)" : "歌词行包含任一关键词则不显示，多个用逗号分隔（如：作词, 作曲, Lyrics by, Arranged by）"
                placeholder: "作词, 作曲, 編曲"
                defaultValue: ""
            }

            StringSetting {
                settingKey: "playerWhitelist"
                label: root.isEnglish ? "Player Whitelist" : "仅检测指定播放器"
                description: root.isEnglish ? "Comma-separated names, fuzzy-matched against player identity (e.g. kew, mpv, firefox). Leave empty to detect all players; prefers the one currently playing" : "多个名称用逗号分隔，按播放器标识模糊匹配（如 kew、mpv、firefox）。留空则检测所有播放器，多个匹配时优先选正在播放的"
                placeholder: "kew, mpv"
                defaultValue: ""
            }
        }
    }

    Row {
        spacing: Theme.spacingS
        anchors.left: parent.left
        anchors.right: parent.right

        MouseArea {
            id: importLyricsButton
            width: importLyricsRow.implicitWidth + Theme.spacingM * 2
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            enabled: !importLyricsProcess.running
            onClicked: importLyricsProcess.run()

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: importLyricsButton.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                Row {
                    id: importLyricsRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    DankIcon {
                        name: importLyricsProcess.running ? "hourglass_top" : "download"
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: importLyricsProcess.running ? root.isEnglish ? "Importing..." : "导入中..." : root.isEnglish ? "Import Embedded Lyrics" : "导入内嵌歌词到缓存"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        StyledText {
            id: importStatusText
            text: ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
        }
    }

    StyledText {
        text: root.isEnglish ? "Extract LRC lyrics from music file metadata into the local cache. Music library path is set below. Supports FLAC/MP3/OGG/M4A etc." : "从音乐库文件的元数据中提取 LRC 格式内嵌歌词，保存到本地缓存。音乐库路径可在下方「音乐库路径」中设置。支持 FLAC/MP3/OGG/M4A 等格式"
        font.pixelSize: Theme.fontSizeSmall - 1
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        width: parent.width
    }

    StyledRect {
        width: parent.width
        height: cacheColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: cacheColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.isEnglish ? "Cache" : "缓存"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "cachingEnabled"
                label: root.isEnglish ? "Local Cache" : "本地缓存"
                description: root.isEnglish ? "Store downloaded lyrics locally for faster loading and fewer network requests. Files are stored in ~/.cache/Lyrics." : "将下载的歌词保存在本地，加快加载速度并减少网络请求。歌词文件将存储在 ~/.cache/Lyrics 目录下。"
                defaultValue: true
            }

            StringSetting {
                settingKey: "musicLibraryPath"
                label: root.isEnglish ? "Music Library Path" : "音乐库路径"
                description: root.isEnglish ? "Music library directory scanned for embedded lyrics; all audio files are found recursively" : "扫描内嵌歌词时使用的音乐库目录，将递归查找其中所有音频文件"
                placeholder: "/mnt/F/Music"
                defaultValue: Quickshell.env("HOME") + "/Music"
            }

            Row {
                spacing: Theme.spacingS
                anchors.left: parent.left
                anchors.right: parent.right

                // 清除缓存按钮
                MouseArea {
                    id: clearCacheButton
                    width: clearCacheRow.implicitWidth + Theme.spacingM * 2
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter

                    onClicked: clearCacheDialog.open()

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: clearCacheButton.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        Row {
                            id: clearCacheRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.isEnglish ? "Refresh Cache" : "刷新缓存"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                StyledText {
                    id: cacheStatusText
                    text: ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                }
            }

            StyledText {
                text: root.isEnglish ? "While playing music, click in the popup toolbar to save the current lyrics to the local cache" : "播放音乐时可在弹窗工具栏点击「缓存歌词」将当前歌词保存到本地缓存"
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
    }

    // 清除缓存确认对话框
    Dialog {
        id: clearCacheDialog
        title: root.isEnglish ? "Confirm Clear Cache" : "确认清除缓存"
        modal: true
        standardButtons: Dialog.Yes | Dialog.No

        contentItem: StyledText {
            text: root.isEnglish ? "Are you sure you want to clear all lyric caches? This cannot be undone." : "确定要清除所有歌词缓存吗？此操作不可恢复。"
            wrapMode: Text.WordWrap
            width: parent.width
        }

        onAccepted: {
            clearCacheProcess.running = true;
        }
    }

    // 清除缓存进程
    Process {
        id: clearCacheProcess
        command: ["rm", "-rf", (Quickshell.env("HOME") || "") + "/.cache/Lyrics"]
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                cacheStatusText.text = root.isEnglish ? "Cache Cleared" : "缓存已清除";
                cacheStatusText.color = Theme.primary;
                console.info("[Lyrics] 缓存已清除");
            } else {
                cacheStatusText.text = root.isEnglish ? "Clear Failed" : "清除失败";
                cacheStatusText.color = Theme.error;
                console.warn("[Lyrics] 缓存清除失败");
            }
            // 3秒后清除状态文本
            clearStatusTimer.start();
        }
    }

    Timer {
        id: clearStatusTimer
        interval: 3000
        onTriggered: {
            cacheStatusText.text = "";
        }
    }

    // 导入内嵌歌词进程
    Process {
        id: importLyricsProcess
        property string scriptPath: {
            var url = Qt.resolvedUrl("./import-embedded-lyrics.sh");
            return url.toString().replace("file://", "");
        }
        property string musicPath: pluginData.musicLibraryPath || (Quickshell.env("HOME") + "/Music")

        function run() {
            musicPath = pluginData.musicLibraryPath || (Quickshell.env("HOME") + "/Music");
            command = ["bash", scriptPath, musicPath];
            running = true;
        }
        command: []
        running: false
        onExited: (exitCode, exitStatus) => {
            console.warn("[Lyrics] Import process exited with code=" + exitCode + " status=" + exitStatus);
            if (exitCode === 0) {
                importStatusText.text = root.isEnglish ? "Import Complete" : "导入完成";
                importStatusText.color = Theme.primary;
            } else {
                importStatusText.text = root.isEnglish ? "Import Failed" : "导入失败";
                importStatusText.color = Theme.error;
            }
            importStatusTimer.start();
        }
    }

    Timer {
        id: importStatusTimer
        interval: 5000
        onTriggered: importStatusText.text = ""
    }

    StyledRect {
        width: parent.width
        height: builtinColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: builtinColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.isEnglish ? "Built-in Sources" : "内置歌词源"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "neteaseEnabled"
                label: root.isEnglish ? "Netease Music" : "网易云音乐"
                description: root.isEnglish ? "Preferred; better support for Chinese songs" : "优先使用，对中文歌曲支持更好"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "lrclibEnabled"
                label: root.isEnglish ? "lrclib.net" : "lrclib.net"
                description: root.isEnglish ? "Open-source lyric database; backup to Netease" : "开源歌词库，作为网易云的后备源"
                defaultValue: true
            }
        }
    }

    StyledRect {
        width: parent.width
        height: customApiColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: customApiColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.isEnglish ? "Custom API" : "自定义 API"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "customApiEnabled"
                label: root.isEnglish ? "Enable Custom API" : "启用自定义 API"
                description: root.isEnglish ? "Use a custom API for lyrics; falls back to enabled built-in sources on failure" : "使用自定义 API 获取歌词，失败时回退到启用的内置源"
                defaultValue: false
            }

            StringSetting {
                settingKey: "customApiUrl"
                label: root.isEnglish ? "API URL" : "API 地址"
                description: root.isEnglish ? "Custom lyrics API URL. Variables: {title}, {artist}, {album}" : "自定义歌词 API 的 URL。支持变量: {title}, {artist}, {album}"
                placeholder: "https://api.example.com/lyrics?title={title}&artist={artist}"
                defaultValue: ""
            }

            SelectionSetting {
                settingKey: "customApiMethod"
                label: root.isEnglish ? "Request Method" : "请求方式"
                description: root.isEnglish ? "Select the API request method" : "选择 API 请求方法"
                options: [
                    { label: "GET", value: "GET" },
                    { label: "POST", value: "POST" }
                ]
                defaultValue: "GET"
            }
        }
    }
}