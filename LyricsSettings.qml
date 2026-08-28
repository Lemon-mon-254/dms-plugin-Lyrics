import Quickshell
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lyrics"

    StyledText {
        width: parent.width
        text: I18n.tr("Lyrics 设置")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.tr("配置歌词行为和歌词源")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // 显示设置
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
                text: I18n.tr("显示设置")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            SelectionSetting {
                settingKey: "coverPosition"
                label: I18n.tr("封面位置")
                description: I18n.tr("状态栏中专辑封面的位置。居中分栏模式在封面左侧显示原文、右侧显示翻译")
                options: [
                    { label: "靠左", value: "left" },
                    { label: "靠右", value: "right" },
                    { label: "居中分栏", value: "center" }
                ]
                defaultValue: "left"
            }

            SelectionSetting {
                settingKey: "lyricLanguage"
                label: I18n.tr("歌词翻译")
                description: I18n.tr("双语歌词的同时间戳两行如何显示。原文|翻译将两行拼为一行；仅原文按日文假名自动识别")
                options: [
                    { label: "原文|翻译", value: "both" },
                    { label: "仅原文", value: "original" },
                    { label: "仅翻译", value: "translation" }
                ]
                defaultValue: "both"
            }

            ToggleSetting {
                settingKey: "lyricEllipsis"
                label: I18n.tr("超长歌词用省略号截断")
                description: I18n.tr("开启后过长的歌词行以省略号截断；关闭则完整显示整行")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "vinylSpin"
                label: I18n.tr("封面自动旋转")
                description: I18n.tr("是否在播放时自动旋转状态栏中的专辑封面")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showClockWhenIdle"
                label: I18n.tr("未播放时显示时钟")
                description: I18n.tr("没有正在播放的内容时，状态栏组件显示当前时间（时:分:秒）")
                defaultValue: false
            }

            StringSetting {
                settingKey: "clockTimezones"
                label: I18n.tr("世界时钟时区")
                description: I18n.tr("弹窗中显示的时区列表，格式：名称:UTC偏移量（如 北京时间:8）。偏移量写 auto 或 pacific 表示太平洋夏令时自动计算。逗号分隔多个时区")
                placeholder: "北京时间:8,东京时间:9,太平洋时间:auto,纽约时间:-5,伦敦时间:0"
                defaultValue: "中国时间:8,日本时间:9,太平洋时间:auto"
            }

            StringSetting {
                settingKey: "lyricBlocklist"
                label: I18n.tr("屏蔽词")
                description: I18n.tr("歌词行包含任一关键词则不显示，多个用逗号分隔（如：作词, 作曲, Lyrics by, Arranged by）")
                placeholder: "作词, 作曲, 編曲"
                defaultValue: ""
            }

            StringSetting {
                settingKey: "playerWhitelist"
                label: I18n.tr("仅检测指定播放器")
                description: I18n.tr("多个名称用逗号分隔，按播放器标识模糊匹配（如 kew、mpv、firefox）。留空则检测所有播放器，多个匹配时优先选正在播放的")
                placeholder: "kew, mpv"
                defaultValue: ""
            }
        }
    }

    // 导入内嵌歌词按钮
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
                        text: importLyricsProcess.running ? I18n.tr("导入中...") : I18n.tr("导入内嵌歌词到缓存")
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
        text: I18n.tr("从音乐库文件的元数据中提取 LRC 格式内嵌歌词，保存到本地缓存。音乐库路径可在下方「音乐库路径」中设置。支持 FLAC/MP3/OGG/M4A 等格式")
        font.pixelSize: Theme.fontSizeSmall - 1
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        width: parent.width
    }

    // 缓存设置
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
                text: I18n.tr("缓存")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "cachingEnabled"
                label: I18n.tr("本地缓存")
                description: I18n.tr("将下载的歌词保存在本地，加快加载速度并减少网络请求。歌词文件将存储在 ~/.cache/Lyrics 目录下。")
                defaultValue: true
            }

            StringSetting {
                settingKey: "musicLibraryPath"
                label: I18n.tr("音乐库路径")
                description: I18n.tr("扫描内嵌歌词时使用的音乐库目录，将递归查找其中所有音频文件")
                placeholder: "/mnt/F/Music"
                defaultValue: Quickshell.env("HOME") + "/Music"
            }

            // 刷新缓存按钮
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
                                text: I18n.tr("刷新缓存")
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
                text: I18n.tr("播放音乐时可在弹窗工具栏点击「缓存歌词」将当前歌词保存到本地缓存")
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
        title: I18n.tr("确认清除缓存")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No

        contentItem: StyledText {
            text: I18n.tr("确定要清除所有歌词缓存吗？此操作不可恢复。")
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
                cacheStatusText.text = I18n.tr("缓存已清除");
                cacheStatusText.color = Theme.primary;
                console.info("[Lyrics] 缓存已清除");
            } else {
                cacheStatusText.text = I18n.tr("清除失败");
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
            var path = url.toString().replace("file://", "");
            console.warn("[Lyrics] Import script path: " + path);
            return path;
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
                importStatusText.text = I18n.tr("导入完成");
                importStatusText.color = Theme.primary;
            } else {
                importStatusText.text = I18n.tr("导入失败");
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

    // 内置 API 设置
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
                text: I18n.tr("内置歌词源")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "neteaseEnabled"
                label: I18n.tr("网易云音乐")
                description: I18n.tr("优先使用，对中文歌曲支持更好")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "lrclibEnabled"
                label: I18n.tr("lrclib.net")
                description: I18n.tr("开源歌词库，作为网易云的后备源")
                defaultValue: true
            }
        }
    }

    // 自定义 API 设置
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
                text: I18n.tr("自定义 API")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "customApiEnabled"
                label: "启用自定义 API"
                description: "使用自定义 API 获取歌词，失败时回退到启用的内置源"
                defaultValue: false
            }

            StringSetting {
                settingKey: "customApiUrl"
                label: "API 地址"
                description: "自定义歌词 API 的 URL。支持变量: {title}, {artist}, {album}"
                placeholder: "https://api.example.com/lyrics?title={title}&artist={artist}"
                defaultValue: ""
            }

            SelectionSetting {
                settingKey: "customApiMethod"
                label: "请求方式"
                description: "选择 API 请求方法"
                options: [
                    { label: "GET", value: "GET" },
                    { label: "POST", value: "POST" }
                ]
                defaultValue: "GET"
            }
        }
    }
}