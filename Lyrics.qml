import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

/**
 * LyricsEmbed
 * 内嵌歌词优先的同步歌词插件，基于 xubuyuan18/dms-plugin-Lyrics 二次开发
 */

PluginComponent {
    id: root
    layerNamespacePlugin: "lyricsEmbed"

    // ============================================
    // 配置属性
    // ============================================
    property bool cachingEnabled: pluginData.cachingEnabled ?? true
    property bool lrclibEnabled: pluginData.lrclibEnabled ?? true
    property bool neteaseEnabled: pluginData.neteaseEnabled ?? true
    property bool customApiEnabled: pluginData.customApiEnabled ?? false
    property string customApiUrl: pluginData.customApiUrl ?? ""
    property string customApiMethod: pluginData.customApiMethod ?? "GET"

    // ============================================
    // 插件语言（zh / en / auto=跟随系统）
    // ============================================
    property string language: pluginData.language ?? "auto"

    // 系统是否为中文环境（auto 模式用）
    readonly property bool _systemChinese: (Qt.locale().name || "").toLowerCase().startsWith("zh")
        || (Quickshell.env("LANG") || "").toLowerCase().startsWith("zh")

    // 英文界面开关（直接绑定 language，供属性绑定追踪）
    readonly property bool isEnglish: {
        var la = root.language;
        if (la === "auto")
            la = root._systemChinese ? "zh" : "en";
        return la === "en";
    }

    // ============================================
    // MPRIS 播放器
    // ============================================

    // 播放器白名单（留空检测全部；逗号分隔，按 identity 模糊匹配）
    property string playerWhitelist: pluginData.playerWhitelist ?? ""
    readonly property var _whitelist: playerWhitelist.split(/[,,、\s]+/)
        .map(function(s) { return s.trim().toLowerCase(); })
        .filter(function(s) { return s.length > 0; })

    readonly property MprisPlayer activePlayer: {
        if (_whitelist.length === 0)
            return MprisController.activePlayer;
        var players = MprisController.availablePlayers || [];
        var firstMatch = null;
        for (var i = 0; i < players.length; i++) {
            var ident = (players[i].identity || "").toLowerCase();
            var matched = false;
            for (var j = 0; j < _whitelist.length; j++) {
                if (ident.includes(_whitelist[j])) {
                    matched = true;
                    break;
                }
            }
            if (!matched)
                continue;
            if (!firstMatch)
                firstMatch = players[i];
            if (players[i].playbackState === MprisPlaybackState.Playing)
                return players[i];
        }
        return firstMatch;
    }
    property var allPlayers: MprisController.availablePlayers

    // ============================================
    // 浏览器视频检测
    // ============================================
    
    // 检测是否为火狐浏览器
    readonly property bool isFirefox: {
        var identity = activePlayer?.identity?.toLowerCase() || "";
        return identity.includes("firefox") || identity.includes("mozilla");
    }
    
    // MV标识关键词（预定义，避免每次重新创建）
    readonly property var _mvKeywords: [
        "mv", "music video", "official video", "official mv", 
        "musicvideo", "video clip", "videoclip",
        "【mv】", "【music video】", "【官方mv】", "【官方版】",
        "official music video", "official hd", "official 4k",
        "歌词版", "歌词mv", "lyrics video", "lyric video"
    ]
    
    // 非MV视频关键词
    readonly property var _nonMvKeywords: [
        "tutorial", "review", "unboxing", "gameplay", 
        "walkthrough", "guide", "how to", "ep.", "episode",
        "教程", "评测", "开箱", "游戏", "攻略", "第", "集"
    ]
    
    // 检测是否为MV（音乐视频）
    readonly property bool isMusicVideo: {
        if (!isFirefox) return false;
        
        var title = currentTitle.toLowerCase();
        var artist = currentArtist.toLowerCase();
        
        // 检查标题是否包含MV关键词
        for (var i = 0; i < _mvKeywords.length; i++) {
            if (title.includes(_mvKeywords[i])) return true;
        }
        
        // 检查是否同时有艺术家和较短的时长（通常MV 3-6分钟）
        if (artist && artist !== "未知艺术家" && currentDuration > 120 && currentDuration < 600) {
            // 如果标题看起来像歌曲名（不包含明显的非MV视频关键词）
            for (var j = 0; j < _nonMvKeywords.length; j++) {
                if (title.includes(_nonMvKeywords[j])) {
                    return false;
                }
            }
            return true;
        }
        
        return false;
    }
    
    // 是否为浏览器视频模式（火狐播放视频但不是MV）
    readonly property bool isBrowserVideo: {
        return isFirefox && !isMusicVideo && currentTitle !== "";
    }
    
    // 是否应该搜索歌词
    readonly property bool shouldSearchLyrics: {
        // 不是火狐浏览器 - 正常搜索歌词
        if (!isFirefox) return true;
        
        // 是火狐浏览器且是MV - 搜索歌词
        if (isMusicVideo) return true;
        
        // 是火狐浏览器但不是MV - 不搜索歌词
        return false;
    }

    // ============================================
    // 状态枚举
    // ============================================

    // 状态码（用于 lrclibStatus, neteaseStatus, cacheStatus）
    QtObject {
        id: status
        readonly property int none: 0
        readonly property int searching: 1
        readonly property int found: 2
        readonly property int notFound: 3
        readonly property int error: 4
        readonly property int skippedConfig: 5
        readonly property int skippedFound: 6
        readonly property int skippedPlain: 7
        readonly property int cacheHit: 8
        readonly property int cacheMiss: 9
        readonly property int cacheDisabled: 10
    }

    // 歌词获取生命周期
    QtObject {
        id: lyricState
        readonly property int idle: 0
        readonly property int loading: 1
        readonly property int synced: 2
        readonly property int notFound: 3
    }

    // 歌词来源
    QtObject {
        id: lyricSrc
        readonly property int none: 0
        readonly property int lrclib: 1
        readonly property int cache: 2
        readonly property int netease: 3
        readonly property int custom: 4
    }

    // ============================================
    // 歌词状态
    // ============================================
    property var lyricsLines: []
    property int currentLineIndex: -1

    // 显示选项（设置页可调）
    property string coverPosition: pluginData.coverPosition ?? "left"
    property string lyricLanguage: pluginData.lyricLanguage ?? "both"
    property bool lyricEllipsis: pluginData.lyricEllipsis ?? true
    property bool vinylSpin: pluginData.vinylSpin ?? true
    property bool showClockWhenIdle: pluginData.showClockWhenIdle ?? false
    property string lyricBlocklist: pluginData.lyricBlocklist ?? ""
    property string musicLibraryPath: pluginData.musicLibraryPath || (Quickshell.env("HOME") + "/Music")

    // 歌词时间偏移量（秒，正=歌词提前，负=歌词延后）
    property real lyricsOffset: 0

    // 音乐库扫描状态: "" 空闲 / "running" / "ok" / "fail"
    property string scanLibStatus: ""
    property bool scanLibRunning: scanLibStatus === "running"

    // 世界时钟时区配置（备份版用，格式："名称:偏移量" 逗号分隔）
    property string clockTimezones: pluginData.clockTimezones ?? "中国时间:8,日本时间:9,太平洋时间:auto"
    property bool useAlbumAccent: pluginData.useAlbumAccent ?? true
    property bool showStatusIndicators: pluginData.showStatusIndicators ?? true
    readonly property color _cardAccent: root.useAlbumAccent ? MediaAccentService.accent : Theme.primary
    readonly property color _cardAccentTrack: Theme.withAlpha(root._cardAccent, 0.28)
    readonly property color _cardAccentSubtle: Theme.withAlpha(root._cardAccent, 0.55)

    // 屏蔽词：歌词包含任一关键词的行不显示
    readonly property var _blocklist: lyricBlocklist.split(/[,,、\s]+/)
        .map(function(s) { return s.trim(); })
        .filter(function(s) { return s.length > 0; })

    onLyricLanguageChanged: rebuildDisplayLines()
    onLyricBlocklistChanged: rebuildDisplayLines()

    // 播放状态细分：无播放器→时钟；暂停→封面+标题/作者；播放→歌词
    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool pausedState: hasPlayer && !isPlaying
    readonly property bool idleClock: showClockWhenIdle && !hasPlayer

    // 与 DMS 内置时钟同源：SystemClock 驱动，精度跟随系统设置
    SystemClock {
        id: idleSystemClock
        precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // 按语言过滤后的显示行与当前索引
    property var displayLines: []
    property int currentDisplayIndex: -1
    property var currentPair: null

    onLyricsLinesChanged: rebuildDisplayLines()
    onCurrentLineIndexChanged: {
        _syncDisplayIndex();
        _rebuildCurrentPair();
    }
    property bool lyricsLoading: lyricStatus === lyricState.loading

    // 内部状态跟踪
    property string _lastFetchedTrack: ""
    property string _lastFetchedArtist: ""
    property string _lastSyncedTrack: ""
    property string _lastSyncedArtist: ""
    property var _cancelActiveFetch: null

    // 各源状态
    property int lrclibStatus: status.none
    property int neteaseStatus: status.none
    property int cacheStatus: status.none

    // 当前状态
    property int lyricStatus: lyricState.idle
    property int lyricSource: lyricSrc.none

    // 当前歌曲信息
    property string currentTitle: activePlayer?.trackTitle ?? ""
    property string currentArtist: activePlayer?.trackArtist ?? ""
    property string currentAlbum: activePlayer?.trackAlbum ?? ""
    property real currentDuration: activePlayer?.length ?? 0

    // 强制更新标志（用于轮询）
    property bool _forceUpdate: false

    // ============================================
    // 计算属性
    // ============================================
    property string currentLyricText: {
        // 处理歌曲名：去掉括号及括号内容
        var title = currentTitle || (root.pureInstrumental
            ? (root.isEnglish ? "Instrumental" : "纯音乐")
            : (root.isEnglish ? "No Lyrics" : "暂无歌词"));
        title = title.replace(/[（(].*?[）)]/g, "");  // 去掉括号及内容
        
        // 如果有歌词，显示"歌曲名 歌词"
        if (lyricsLines.length > 0 && currentLineIndex >= 0 && lyricsLines[currentLineIndex].text) {
            return title + "  " + lyricsLines[currentLineIndex].text;
        }
        return title;
    }

    // 是否有任何可用的在线歌词源
    readonly property bool onlineSourcesEnabled: neteaseEnabled || lrclibEnabled
        || (customApiEnabled && customApiUrl && customApiUrl.trim() !== "")

    // 当前曲目是否为纯音乐：
    // - 无歌词 且 标题/歌手带纯音乐标记；或
    // - 无歌词 且 用户关闭了全部在线源（此时无缓存即视为纯音乐）
    readonly property bool pureInstrumental: !lyricsLoading
        && lyricsLines.length === 0
        && (_isInstrumentalIdentity(currentTitle, currentArtist) || !root.onlineSourcesEnabled)

    // ============================================
    // 定时器
    // ============================================

    // 防抖定时器 - 避免标题和艺术家同时变化时重复获取
    Timer {
        id: fetchDebounceTimer
        interval: 300
        onTriggered: root.fetchLyricsIfNeeded()
    }

    onCurrentTitleChanged: {
        _resetLyricsForTrack();
        fetchDebounceTimer.restart();
    }
    onCurrentArtistChanged: fetchDebounceTimer.restart()

    // XHR 超时定时器
    Timer {
        id: xhrTimeoutTimer
        repeat: false
        property var onTimeout: null
        onTriggered: if (onTimeout) onTimeout()
    }

    // XHR 重试定时器
    Timer {
        id: xhrRetryTimer
        repeat: false
        property var onRetry: null
        onTriggered: if (onRetry) onRetry()
    }

    // ============================================
    // 状态管理函数
    // ============================================

    /**
     * 重置歌词状态（保留 _lastFetchedTrack/_lastFetchedArtist）
     */
    function _resetLyricsState() {
        lyricsLines = [];
        currentLineIndex = -1;
        lyricsOffset = 0;
        lrclibStatus = status.none;
        neteaseStatus = status.none;
        cacheStatus = status.none;
        lyricStatus = lyricState.loading;
        lyricSource = lyricSrc.none;
    }

    /**
     * 设置最终"未找到"状态
     */
    function _setFinalNotFound(sourceStatusVal) {
        lrclibStatus = sourceStatusVal;
        neteaseStatus = sourceStatusVal;
        lyricStatus = lyricState.notFound;
        root._cancelActiveFetch = null;
    }

    // ============================================
    // 缓存管理
    // ============================================

    readonly property string _cacheDir: (Quickshell.env("HOME") || "") + "/.cache/Lyrics"
    property bool _cacheDirReady: false

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root._cacheDir]
        running: false
    }

    // 音乐库内嵌歌词导入（卡片工具栏按钮触发）
    Process {
        id: scanLibProcess
        command: []
        running: false
        onStarted: root.scanLibStatus = "running"
        onExited: (exitCode, exitStatus) => {
            console.warn("[Lyrics] 导入进程退出 code=" + exitCode + " status=" + exitStatus)
            root.scanLibStatus = exitCode === 0 ? "ok" : "fail"
            scanLibStatusTimer.start()
        }
    }

    Timer {
        id: scanLibStatusTimer
        interval: 4000
        onTriggered: root.scanLibStatus = ""
    }

    function _ensureCacheDir() {
        if (_cacheDirReady) return;
        _cacheDirReady = true;
        mkdirProcess.running = true;
    }

    /**
     * FNV-1a 32位哈希
     */
    function _fnv1a32(str) {
        var hash = 0x811c9dc5;
        for (var i = 0; i < str.length; i++) {
            hash = Math.imul(hash ^ str.charCodeAt(i), 0x01000193) >>> 0;
        }
        return ("00000000" + hash.toString(16)).slice(-8);
    }

    function _cacheKey(title, artist) {
        return _fnv1a32((title + "\x00" + artist).toLowerCase());
    }

    function _cacheFilePath(title, artist) {
        return _cacheDir + "/" + _cacheKey(title, artist) + ".json";
    }

    // 缓存读取: 静态 FileView (避免动态实例化竞态)
    FileView {
        id: cacheReader
        property var callback
        watchChanges: false
        onLoaded: {
            var cb = callback
            callback = null
            if (!cb) return
            try {
                cb(JSON.parse(text()))
            } catch (e) {
                console.warn("[Lyrics] 缓存JSON解析失败: " + e)
                cb(null)
            }
        }
        onLoadFailed: {
            var cb = callback
            callback = null
            if (cb) cb(null)
        }
    }

    // 缓存文件探测: 仅判断是否存在，不读取内容
    FileView {
        id: cacheProbe
        property string probePath: ""
        watchChanges: false
        onLoaded: {
            var p = probePath
            probePath = ""
            if (!p) return
            // micro.desktop 声明 Terminal=true，niri 下 gio open 无法启动；
            // 直接用 kitty 打开 micro 查看歌词 json
            Quickshell.execDetached(["kitty", "--class", "lyrics-cache", "-e", "micro", p])
        }
        onLoadFailed: {
            if (probePath) {
                console.warn("[Lyrics] 缓存文件不存在，打开缓存目录: " + probePath)
                Quickshell.execDetached(["gio", "open", root._cacheDir])
                probePath = ""
            }
        }
    }

    /**
     * 从缓存读取歌词
     */
    function readFromCache(title, artist, callback) {
        cacheReader.callback = callback
        cacheReader.path = _cacheFilePath(title, artist)
        cacheReader.load()
    }

    /**
     * 写入缓存
     */
    function writeToCache(title, artist, lines, source) {
        _ensureCacheDir();
        cacheWriterComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            cTitle: title,
            cArtist: artist,
            cLines: lines,
            cSource: source,
            cOffset: root.lyricsOffset
        });
    }

    /**
     * 清除当前歌曲的缓存并重新搜索
     */
    function clearCurrentCacheAndRefetch() {
        if (!currentTitle) return;
        
        var cacheFile = _cacheFilePath(currentTitle, currentArtist);
        console.info("[Lyrics] 清除缓存: \"" + currentTitle + "\"");
        
        // 使用 Process 删除缓存文件
        var deleter = cacheDeleterProcessComponent.createObject(root, {
            cacheFilePath: cacheFile
        });
        deleter.running = true;
    }

    // 缓存删除进程组件
    Component {
        id: cacheDeleterProcessComponent
        Process {
            property string cacheFilePath: ""
            
            command: ["rm", "-f", cacheFilePath]
            
            onExited: (exitCode, exitStatus) => {
                console.info("[Lyrics] 缓存已清除，重新搜索...");
                // 重置状态并重新搜索
                root._lastFetchedTrack = "";
                root._lastFetchedArtist = "";
                root.fetchLyricsIfNeeded();
                destroy();
            }
        }
    }

    // 缓存读取组件
    Component {
        id: cacheReaderComponent
        FileView {
            property var callback
            blockLoading: true
            preload: true
            onLoaded: {
                try {
                    callback(JSON.parse(text()));
                } catch (e) {
                    callback(null);
                }
                destroy();
            }
            onLoadFailed: {
                callback(null);
                destroy();
            }
        }
    }

    // 缓存写入组件
    Component {
        id: cacheWriterComponent
        FileView {
            property string cTitle
            property string cArtist
            property var cLines
            property int cSource
            property real cOffset: 0

            blockWrites: false
            atomicWrites: true

            Component.onCompleted: {
                setText(JSON.stringify({
                    lines: cLines,
                    source: cSource,
                    cachedAt: new Date().toISOString(),
                    offset: cOffset
                }));
            }

            onSaved: {
                console.info("[Lyrics] 缓存: 已保存 \"" + cTitle + "\" 的歌词 (" + cLines.length + " 行)");
                destroy();
            }
            onSaveFailed: {
                console.warn("[Lyrics] 缓存: 保存失败 \"" + cTitle + "\"");
                destroy();
            }
        }
    }

    // ============================================
    // 歌词获取协调
    // ============================================

    /**
     * 主入口：检查并获取歌词
     * 优先级：自定义API → 缓存 → 网易云 → lrclib
     */
    function fetchLyricsIfNeeded() {
        if (!currentTitle) return;

        // 如果歌曲相同且已同步，跳过
        if (currentTitle === _lastFetchedTrack &&
            currentArtist === _lastFetchedArtist &&
            lyricStatus === lyricState.synced) {
            return;
        }

        // 取消进行中的请求
        if (_cancelActiveFetch) {
            _cancelActiveFetch();
            _cancelActiveFetch = null;
        }

        _lastFetchedTrack = currentTitle;
        _lastFetchedArtist = currentArtist;
        _resetLyricsState();

        _logSongChange();

        // 检查是否应该搜索歌词（火狐浏览器非MV视频不搜索）
        if (!shouldSearchLyrics) {
            console.info("[Lyrics] 浏览器视频模式: 显示封面和标题，跳过歌词搜索");
            lyricStatus = lyricState.idle;
            lrclibStatus = status.skippedConfig;
            neteaseStatus = status.skippedConfig;
            cacheStatus = status.skippedConfig;
            return;
        }

        var capturedTitle = currentTitle;
        var capturedArtist = currentArtist;

        // 优先级1：自定义API
        if (customApiEnabled && customApiUrl) {
            _fetchFromCustomApi(capturedTitle, capturedArtist);
            return;
        }

        // 优先级2：缓存
        if (cachingEnabled) {
            _tryCacheThenFetch(capturedTitle, capturedArtist);
        } else {
            cacheStatus = status.cacheDisabled;
            _startFetchFromSources(capturedTitle, capturedArtist);
        }
    }

    /**
     * 尝试从缓存读取，失败则从源获取
     */
    function _tryCacheThenFetch(title, artist) {
        readFromCache(title, artist, function (cached) {
            // 守卫：歌曲已切换
            if (title !== root._lastFetchedTrack || artist !== root._lastFetchedArtist) return;

            if (cached?.lines?.length > 0) {
                _applyCachedLyrics(cached, title, artist);
                return;
            }

            root.cacheStatus = status.cacheMiss;
            if (!root.onlineSourcesEnabled) {
                root._setFinalNotFound(status.notFound);
                return;
            }
            _startFetchFromSources(title, artist);
        });
    }

    /**
     * 应用缓存的歌词
     */
    function _applyCachedLyrics(cached, title, artist) {
        root.lyricsLines = cached.lines;
        root.lyricStatus = lyricState.synced;
        root.lyricSource = cached.source > 0 ? cached.source : lyricSrc.cache;
        root.cacheStatus = status.cacheHit;
        root.lrclibStatus = status.skippedFound;
        root.neteaseStatus = status.skippedFound;
        root._lastSyncedTrack = title;
        root._lastSyncedArtist = artist;
        // 恢复偏移量
        if (typeof cached.offset === "number")
            root.lyricsOffset = cached.offset;
        console.info("[Lyrics] ✓ 缓存: 已加载 \"" + title + "\" 的歌词 (" + cached.lines.length + " 行)");
    }

    /**
     * 从各源获取歌词（网易云优先）
     */
    function _startFetchFromSources(title, artist) {
        if (!root.onlineSourcesEnabled) {
            root._setFinalNotFound(status.notFound);
            return;
        }
        if (neteaseEnabled) {
            _fetchFromNetease(title, artist);
        } else {
            lrclibStatus = status.skippedConfig;
            _fetchFromLrclib(title, artist);
        }
    }

    /**
     * 记录歌曲切换日志
     */
    function _logSongChange() {
        var durationStr = currentDuration > 0
            ? (Math.floor(currentDuration / 60) + ":" + ("0" + Math.floor(currentDuration % 60)).slice(-2))
            : "未知";
        console.info("[Lyrics] ▶ 歌曲切换: \"" + currentTitle + "\" - " + currentArtist +
                    (currentAlbum ? " [" + currentAlbum + "]" : "") + " (" + durationStr + ")");
    }

    // ============================================
    // 网络请求工具
    // ============================================

    /**
     * XHR 请求（带重试机制）
     * @returns {Function} 取消函数
     */
    function _xhrRequest(url, method, timeoutMs, onSuccess, onError, customHeaders, postData) {
        const MAX_RETRIES = 2;
        const RETRY_DELAY = 3000;

        var retriesLeft = MAX_RETRIES;
        var attempt = 0;
        var cancelled = false;
        var currentXhr = null;
        var httpMethod = method || "GET";

        function _attempt() {
            attempt++;
            currentXhr = new XMLHttpRequest();
            var done = false;

            // 设置超时
            xhrTimeoutTimer.stop();
            xhrTimeoutTimer.interval = timeoutMs;
            xhrTimeoutTimer.onTimeout = function () {
                if (!done && !cancelled) {
                    done = true;
                    currentXhr.abort();
                    _retry("timeout");
                }
            };
            xhrTimeoutTimer.start();

            // 状态处理
            currentXhr.onreadystatechange = function () {
                if (currentXhr.readyState !== XMLHttpRequest.DONE || done || cancelled) return;

                done = true;
                xhrTimeoutTimer.stop();

                if (currentXhr.status === 0) {
                    _retry("network error (status 0)");
                    return;
                }

                var responseBody = (currentXhr.responseText || "").trim();
                if (responseBody.length === 0) {
                    _retry("empty response (HTTP " + currentXhr.status + ")");
                    return;
                }

                onSuccess(currentXhr.responseText, currentXhr.status);
            };

            // 发送请求
            currentXhr.open(httpMethod, url);

            if (customHeaders) {
                for (var key in customHeaders) {
                    currentXhr.setRequestHeader(key, customHeaders[key]);
                }
            } else {
                currentXhr.setRequestHeader("User-Agent", "DankMaterialShell Lyrics/1.7.0");
                currentXhr.setRequestHeader("Accept", "application/json");
            }

            if (httpMethod === "POST" && postData) {
                currentXhr.setRequestHeader("Content-Type", "application/json");
                currentXhr.send(JSON.stringify(postData));
            } else {
                currentXhr.send();
            }
        }

        function _retry(errMsg) {
            if (cancelled) return;

            if (retriesLeft > 0) {
                retriesLeft--;
                console.warn("[Lyrics] 请求失败，重试中 (" + (MAX_RETRIES - retriesLeft) + "/" + MAX_RETRIES + "): " + url);
                xhrRetryTimer.stop();
                xhrRetryTimer.interval = RETRY_DELAY;
                xhrRetryTimer.onRetry = _attempt;
                xhrRetryTimer.start();
            } else {
                onError(errMsg);
            }
        }

        _attempt();

        return function cancel() {
            cancelled = true;
            xhrTimeoutTimer.stop();
            xhrRetryTimer.stop();
            if (currentXhr) currentXhr.abort();
        };
    }

    function _xhrGet(url, timeoutMs, onSuccess, onError, customHeaders) {
        return _xhrRequest(url, "GET", timeoutMs, onSuccess, onError, customHeaders, null);
    }

    // ============================================
    // 歌词源：lrclib.net
    // ============================================

    function _fetchFromLrclib(expectedTitle, expectedArtist) {
        if (!_checkSourceEnabled("lrclib", lrclibEnabled, neteaseEnabled)) return;
        if (_checkAlreadySynced("lrclib")) return;

        lrclibStatus = status.searching;
        console.info("[Lyrics] lrclib: 正在搜索 \"" + expectedTitle + "\"");

        var url = _buildLrclibUrl(expectedTitle, expectedArtist);

        root._cancelActiveFetch = _xhrGet(url, 20000,
            function (responseText, httpStatus) {
                _handleLrclibResponse(responseText, expectedTitle, expectedArtist);
            },
            function (errMsg) {
                _handleLrclibError(errMsg, expectedTitle, expectedArtist);
            }
        );
    }

    function _buildLrclibUrl(title, artist) {
        var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(artist)
                + "&track_name=" + encodeURIComponent(title);
        if (currentAlbum) url += "&album_name=" + encodeURIComponent(currentAlbum);
        if (currentDuration > 0) url += "&duration=" + Math.round(currentDuration);
        return url;
    }

    function _handleLrclibResponse(responseText, expectedTitle, expectedArtist) {
        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _fallbackAfterLrclib(status.error, "空响应", expectedTitle, expectedArtist);
            return;
        }

        try {
            var result = JSON.parse(rawData);

            if (result.statusCode === 404 || result.error) {
                _fallbackAfterLrclib(status.notFound, "未找到", expectedTitle, expectedArtist);
                return;
            }

            if (result.syncedLyrics) {
                _applyLyricsFromSource(result.syncedLyrics, lyricSrc.lrclib, expectedTitle, expectedArtist);
                return;
            }

            if (result.plainLyrics) {
                var plainLines = _plainTextToLines(result.plainLyrics);
                if (plainLines.length > 0) {
                    _applyLyricsLines(plainLines, lyricSrc.lrclib, expectedTitle, expectedArtist);
                    return;
                }
            }

            _fallbackAfterLrclib(status.notFound, "无歌词数据", expectedTitle, expectedArtist);

        } catch (e) {
            _fallbackAfterLrclib(status.error, "解析失败: " + e, expectedTitle, expectedArtist);
        }
    }

    function _handleLrclibError(errMsg, expectedTitle, expectedArtist) {
        console.warn("[Lyrics] lrclib: 请求失败 — " + errMsg);
        _fallbackAfterLrclib(status.error, errMsg, expectedTitle, expectedArtist);
    }

    function _fallbackAfterLrclib(statusVal, reason, title, artist) {
        lrclibStatus = statusVal;
        console.info("[Lyrics] lrclib: " + reason + " - \"" + title + "\"");

        if (neteaseEnabled) {
            _fetchFromNetease(title, artist);
        } else {
            _setFinalNotFound(statusVal);
        }
    }

    // ============================================
    // 歌词源：网易云音乐
    // ============================================

    function _fetchFromNetease(expectedTitle, expectedArtist) {
        if (!_checkSourceEnabled("netease", neteaseEnabled, false)) {
            _setFinalNotFound(status.notFound);
            return;
        }
        if (_checkAlreadySynced("netease")) return;

        neteaseStatus = status.searching;
        console.info("[Lyrics] 网易云: 搜索 \"" + expectedTitle + "\"");

        var searchUrl = "https://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag=&s="
                      + encodeURIComponent(expectedTitle) + "&type=1&offset=0&total=true&limit=2";

        var customHeaders = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0",
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://music.163.com/"
        };

        root._cancelActiveFetch = _xhrRequest(searchUrl, "GET", 15000,
            function (responseText, httpStatus) {
                _handleNeteaseSearchResponse(responseText, expectedTitle, expectedArtist);
            },
            function (errMsg) {
                _handleNeteaseError("搜索失败: " + errMsg, expectedTitle, expectedArtist);
            },
            customHeaders
        );
    }

    function _handleNeteaseSearchResponse(responseText, expectedTitle, expectedArtist) {
        if (!_isCurrentTrack(expectedTitle, expectedArtist)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空搜索响应", expectedTitle);
            return;
        }

        try {
            var result = JSON.parse(rawData);
            var songs = result?.result?.songs;

            if (!songs || songs.length === 0) {
                _handleNeteaseError("未找到歌曲", expectedTitle, expectedArtist);
                return;
            }

            var matchedSong = _findBestMatch(songs, expectedTitle, currentAlbum);
            var songId = matchedSong.id;
            var songName = matchedSong.name;
            var artistName = matchedSong.artists?.[0]?.name || "未知";

            console.info("[Lyrics] 网易云: 匹配 \"" + songName + "\" - " + artistName);

            _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, songName, artistName);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle);
        }
    }

    function _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, matchedName, matchedArtist) {
        if (!_isCurrentTrack(expectedTitle, expectedArtist)) return;

        var lyricUrl = "https://api.paugram.com/netease/?id=" + encodeURIComponent(songId);

        root._cancelActiveFetch = _xhrGet(lyricUrl, 15000,
            function (responseText, httpStatus) {
                _handleNeteaseLyricResponse(responseText, expectedTitle, expectedArtist, matchedName, matchedArtist);
            },
            function (errMsg) {
                _handleNeteaseError("歌词请求失败: " + errMsg, expectedTitle, expectedArtist);
            }
        );
    }

    function _handleNeteaseLyricResponse(responseText, expectedTitle, expectedArtist, matchedName, matchedArtist) {
        if (!_isCurrentTrack(expectedTitle, expectedArtist)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空搜索响应", expectedTitle, expectedArtist);
            return;
        }

        try {
            var result = JSON.parse(rawData);

            if (!result.title) {
                _handleNeteaseError("无歌曲数据", expectedTitle, expectedArtist);
                return;
            }

            var lyricText = result.lyric || "";
            if (lyricText.trim() === "") {
                _handleNeteaseError("该歌曲无歌词", expectedTitle, expectedArtist);
                return;
            }

            var lines = parseLrc(lyricText);
            if (lines.length === 0) {
                _handleNeteaseError("LRC解析失败", expectedTitle, expectedArtist);
                return;
            }

            _applyLyricsLines(lines, lyricSrc.netease, expectedTitle, expectedArtist);
            console.info("[Lyrics] 网易云: 匹配 \"" + matchedName + "\" - " + matchedArtist);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle, expectedArtist);
        }
    }

    function _handleNeteaseError(reason, title, artist) {
        neteaseStatus = status.error;
        console.warn("[Lyrics] 网易云: " + reason + " - \"" + title + "\"");

        // 网易云失败时，回退到 lrclib
        if (lrclibEnabled) {
            console.info("[Lyrics] 网易云失败，尝试 lrclib...");
            _fetchFromLrclib(title, artist);
        } else {
            _setFinalNotFound(status.error);
        }
    }

    // ============================================
    // 歌词源：自定义 API
    // ============================================

    function _fetchFromCustomApi(expectedTitle, expectedArtist) {
        console.info("[Lyrics] 自定义API: 获取 \"" + expectedTitle + "\"");

        var url = customApiUrl
            .replace(/{title}/g, encodeURIComponent(expectedTitle))
            .replace(/{artist}/g, encodeURIComponent(expectedArtist))
            .replace(/{album}/g, encodeURIComponent(currentAlbum || ""));

        var postData = customApiMethod === "POST" ? {
            title: expectedTitle,
            artist: expectedArtist,
            album: currentAlbum || ""
        } : null;

        root._cancelActiveFetch = _xhrRequest(url, customApiMethod, 20000,
            function (responseText, httpStatus) {
                _handleCustomApiResponse(responseText, expectedTitle, expectedArtist);
            },
            function (errMsg) {
                console.warn("[Lyrics] 自定义API: 失败 - " + errMsg);
                _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
            },
            null,
            postData
        );
    }

    function _handleCustomApiResponse(responseText, expectedTitle, expectedArtist) {
        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空歌词响应", expectedTitle, expectedArtist);
            return;
        }

        try {
            var result = JSON.parse(rawData);
            var lyricText = result.lyrics || result.lyric || result.lrc || result.content || result.data;

            if (!lyricText || lyricText.trim() === "") {
                _fallbackToBuiltin("响应中无歌词", expectedTitle, expectedArtist);
                return;
            }

            var lines = parseLrc(lyricText);
            if (lines.length === 0) {
                lines = _plainTextToLines(lyricText);
            }

            if (lines.length === 0) {
                _fallbackToBuiltin("解析失败", expectedTitle, expectedArtist);
                return;
            }

            _applyLyricsLines(lines, lyricSrc.custom, expectedTitle, expectedArtist);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle, expectedArtist);
        }
    }

    function _fallbackToBuiltin(reason, title, artist) {
        console.warn("[Lyrics] 自定义API: " + reason + "，回退到内置源");
        _fetchFromCacheOrBuiltin(title, artist);
    }

    function _fetchFromCacheOrBuiltin(title, artist) {
        if (cachingEnabled) {
            readFromCache(title, artist, function (cached) {
                if (cached?.lines?.length > 0) {
                    _applyCachedLyrics(cached, title, artist);
                    return;
                }
                root.cacheStatus = status.cacheMiss;
                if (!root.onlineSourcesEnabled) {
                    root._setFinalNotFound(status.notFound);
                    return;
                }
                _fetchFromLrclib(title, artist);
            });
        } else {
            cacheStatus = status.cacheDisabled;
            if (!root.onlineSourcesEnabled) {
                root._setFinalNotFound(status.notFound);
                return;
            }
            _fetchFromLrclib(title, artist);
        }
    }

    // ============================================
    // 歌词处理辅助函数
    // ============================================

    function _checkSourceEnabled(name, enabled, hasFallback) {
        if (!enabled) {
            if (name === "lrclib") lrclibStatus = status.skippedConfig;
            if (name === "netease") neteaseStatus = status.skippedConfig;
            console.info("[Lyrics] " + name + ": 已禁用，跳过");
            return false;
        }
        return true;
    }

    function _checkAlreadySynced(name) {
        if (lyricStatus === lyricState.synced) {
            if (name === "lrclib") lrclibStatus = status.skippedFound;
            if (name === "netease") neteaseStatus = status.skippedFound;
            console.info("[Lyrics] " + name + ": 已跳过 (已找到歌词)");
            return true;
        }
        return false;
    }

    function _isCurrentTrack(title, artist) {
        return title === root._lastFetchedTrack && artist === root._lastFetchedArtist;
    }

    /**
     * 网易云歌曲匹配 - 支持大小写、空格模糊匹配和专辑匹配
     */
    function _findBestMatch(songs, expectedTitle, expectedAlbum) {
        // 标准化函数：转为小写并移除所有空格
        function normalize(str) {
            if (!str) return "";
            return str.toLowerCase().replace(/\s+/g, "");
        }

        var normalizedExpected = normalize(expectedTitle);
        var normalizedExpectedAlbum = normalize(expectedAlbum);

        // 第一优先级：歌曲名完全匹配 + 专辑匹配
        if (normalizedExpectedAlbum) {
            for (var i = 0; i < songs.length; i++) {
                var songAlbum = normalize(songs[i].album?.name || songs[i].album);
                if (normalize(songs[i].name) === normalizedExpected && 
                    songAlbum === normalizedExpectedAlbum) {
                    console.info("[Lyrics] 网易云: 精确匹配(含专辑) \"" + songs[i].name + "\" - \"" + (songs[i].album?.name || songs[i].album) + "\"");
                    return songs[i];
                }
            }
        }

        // 第二优先级：歌曲名完全匹配（忽略大小写和空格）
        for (var j = 0; j < songs.length; j++) {
            if (normalize(songs[j].name) === normalizedExpected) {
                console.info("[Lyrics] 网易云: 精确匹配 \"" + songs[j].name + "\"");
                return songs[j];
            }
        }

        // 第三优先级：歌曲名模糊匹配 + 专辑匹配
        if (normalizedExpectedAlbum) {
            var lowerExpected = expectedTitle.toLowerCase();
            for (var k = 0; k < songs.length; k++) {
                var songNameLower = songs[k].name.toLowerCase();
                var songAlbum2 = normalize(songs[k].album?.name || songs[k].album);
                var nameMatches = songNameLower === lowerExpected ||
                                  songNameLower.indexOf(lowerExpected) !== -1 ||
                                  lowerExpected.indexOf(songNameLower) !== -1;
                
                if (nameMatches && songAlbum2 === normalizedExpectedAlbum) {
                    console.info("[Lyrics] 网易云: 模糊匹配(含专辑) \"" + songs[k].name + "\" - \"" + (songs[k].album?.name || songs[k].album) + "\"");
                    return songs[k];
                }
            }
        }

        // 第四优先级：忽略大小写的包含匹配
        var lowerExpected2 = expectedTitle.toLowerCase();
        for (var m = 0; m < songs.length; m++) {
            var songNameLower2 = songs[m].name.toLowerCase();
            if (songNameLower2 === lowerExpected2 ||
                songNameLower2.indexOf(lowerExpected2) !== -1 ||
                lowerExpected2.indexOf(songNameLower2) !== -1) {
                console.info("[Lyrics] 网易云: 模糊匹配 \"" + songs[m].name + "\"");
                return songs[m];
            }
        }

        // 默认返回第一首
        console.info("[Lyrics] 网易云: 默认匹配 \"" + songs[0].name + "\"");
        return songs[0];
    }

    function _plainTextToLines(plainText) {
        return plainText
            .split("\n")
            .map(function(line) { return { time: 0, text: line.trim() }; })
            .filter(function(l) { return l.text !== ""; });
    }

    function _applyLyricsFromSource(lrcText, source, title, artist) {
        var lines = parseLrc(lrcText);
        _applyLyricsLines(lines, source, title, artist);
    }

    function _applyLyricsLines(lines, source, title, artist) {
        root.lyricsLines = lines;
        root.lyricStatus = lyricState.synced;
        root.lyricSource = source;
        root._lastSyncedTrack = title;
        root._lastSyncedArtist = artist;
        root._cancelActiveFetch = null;

        if (source === lyricSrc.lrclib) lrclibStatus = status.found;
        if (source === lyricSrc.netease) neteaseStatus = status.found;

        var sourceName = source === lyricSrc.lrclib ? "lrclib" :
                        source === lyricSrc.netease ? "网易云" :
                        source === lyricSrc.custom ? "自定义API" : "未知";

        console.info("[Lyrics] ✓ " + sourceName + ": 已找到歌词 (" + lines.length + " 行) - \"" + title + "\"");

        if (cachingEnabled) {
            writeToCache(title, artist, lines, source);
        }
    }

    // -------------------------------------------------------------------------
    // LRC parser
    // -------------------------------------------------------------------------

    /**
     * 检查是否为纯音乐标记
     * 支持多种变体："纯音乐，请欣赏"、"纯音乐 请欣赏"、"Instrumental"等
     */
    function _isInstrumentalMarker(text) {
        if (!text || text.trim() === "") return false;

        var normalized = text.toLowerCase().replace(/[\s,，。、;；:：!！?？]+/g, "").trim();

        // 中文纯音乐标记
        var instrumentalPatterns = [
            "纯音乐请欣赏",
            "纯音乐",
            "纯乐器",
            "无歌词",
            "暂无歌词",
            "纯音",
            "音轨",
            "instrumental",
            "musiconly",
            "nomusic",
            "インスト",
            "演奏のみ",
            "instrumentmusik"
        ];

        for (var i = 0; i < instrumentalPatterns.length; i++) {
            if (normalized.indexOf(instrumentalPatterns[i]) !== -1) {
                return true;
            }
        }

        return false;
    }

    /**
     * 根据标题/艺术家判断是否为纯音乐（无歌词曲目）
     * 匹配 Instrumental / 纯音乐 / BGM / OST / 主题曲 等常见标记
     */
    function _isInstrumentalIdentity(title, artist) {
        var hay = ((title || "") + " " + (artist || "")).toLowerCase();
        if (!hay.trim()) return false;
        var patterns = [
            "pure instrumental",
            "instrumental",
            "纯音乐",
            "纯乐器",
            "bgm",
            "original soundtrack",
            "original sound track",
            "\bost\b",
            "サウンドトラック",
            "メインテーマ",
            "ピアノソロ",
            "piano solo",
            "piano piece",
            "music box",
            "演奏のみ",
            "インスト"
        ];
        for (var j = 0; j < patterns.length; j++) {
            if (hay.indexOf(patterns[j]) !== -1) {
                return true;
            }
        }
        return false;
    }

    function parseLrc(lrcText) {
        var timeRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]/;
        var result = lrcText.split("\n").reduce(function (acc, rawLine) {
            var line = rawLine.trim();
            if (!line)
                return acc;
            var match = timeRegex.exec(line);
            if (!match)
                return acc;
            var millis = parseInt(match[3]);
            if (match[3].length === 2)
                millis *= 10;

            var text = line.replace(/\[\d{2}:\d{2}\.\d{2,3}\]/g, "").trim();

            // 跳过纯音乐标记行
            if (_isInstrumentalMarker(text)) {
                return acc;
            }

            acc.push({
                time: parseInt(match[1]) * 60 + parseInt(match[2]) + millis / 1000,
                text: text
            });
            return acc;
        }, []);
        result.sort(function (a, b) {
            return a.time - b.time;
        });
        return result;
    }

    // -------------------------------------------------------------------------
    // Position tracking for synced lyrics
    // -------------------------------------------------------------------------

    // MPRIS Position 锚点：部分播放器（如 kew）上报停滞，播放中按真实时间外推
    property real _lastRealPos: -1
    property real _lastPosStamp: 0

    function clockText() {
        const d = idleSystemClock.date || new Date();
        const sec = SettingsData.showSeconds ? (":" + String(d.getSeconds()).padStart(2, "0")) : "";
        if (SettingsData.use24HourClock)
            return Qt.formatDateTime(d, "HH:mm") + sec;
        let h = d.getHours();
        const ampm = h >= 12 ? " PM" : " AM";
        h = h === 0 ? 12 : h > 12 ? h - 12 : h;
        return String(h).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0") + sec + ampm;
    }

    SystemClock {
        id: worldClockSource
        precision: SystemClock.Seconds
    }

    function _tzDate(offsetHours) {
        const now = worldClockSource.date || new Date();
        return new Date(now.getTime() + offsetHours * 3600000);
    }

    function _tzTime(offsetHours) {
        const d = _tzDate(offsetHours);
        const p2 = n => String(n).padStart(2, "0");
        return p2(d.getUTCHours()) + ":" + p2(d.getUTCMinutes()) + ":" + p2(d.getUTCSeconds());
    }

    function _tzDateStr(offsetHours) {
        const d = _tzDate(offsetHours);
        const wd = ["日", "一", "二", "三", "四", "五", "六"];
        return (d.getUTCMonth() + 1) + "/" + d.getUTCDate() + " 周" + wd[d.getUTCDay()];
    }

    // 太平洋时间（洛杉矶）：自动处理夏令时（3月第二个周日 ~ 11月第一个周日）
    function _pacificOffset() {
        const now = worldClockSource.date || new Date();
        const t = now.getTime();
        const y = new Date(t).getUTCFullYear();
        function nthSun(month, n) {
            const d = new Date(Date.UTC(y, month, 1));
            while (d.getUTCDay() !== 0)
                d.setUTCDate(d.getUTCDate() + 1);
            d.setUTCDate(d.getUTCDate() + 7 * (n - 1));
            return d.getTime();
        }
        const start = nthSun(2, 2) + 10 * 3600000;
        const end = nthSun(10, 1) + 10 * 3600000;
        return (t >= start && t < end) ? -7 : -8;
    }

    // 解析 clockTimezones 设置（名称:偏移 逗号分隔），偏移可为数字或 auto（=太平洋夏令时）
    readonly property var _clockTimezonesArr: {
        const raw = (root.clockTimezones || "").trim();
        if (!raw)
            return [];
        const out = [];
        const parts = raw.split(/[,，;；]+/);
        for (let i = 0; i < parts.length; i++) {
            const seg = parts[i].trim();
            if (!seg)
                continue;
            const idx = seg.lastIndexOf(":");
            if (idx <= 0 || idx === seg.length - 1)
                continue;
            const name = seg.slice(0, idx).trim();
            const offStr = seg.slice(idx + 1).trim().toLowerCase();
            let off;
            if (offStr === "auto" || offStr === "pacific")
                off = root._pacificOffset();
            else if (offStr === "utc" || offStr === "gmt")
                off = 0;
            else {
                off = parseFloat(offStr);
                if (isNaN(off))
                    continue;
            }
            out.push([name, off]);
        }
        return out.length ? out : [[root.isEnglish ? "UTC" : "世界时间", 0]];
    }

    // 换曲时重置同步状态，避免残留上一首的行索引和位置锚点
    // （由 onCurrentTitleChanged 统一触发，见 fetchDebounceTimer 处）
    function _resetLyricsForTrack() {
        currentLineIndex = -1;
        _lastRealPos = -1;
        _lastPosStamp = 0;
        rebuildDisplayLines();
    }

    Timer {
        id: positionTimer
        interval: 200
        running: activePlayer && lyricsLines.length > 0
        repeat: true
        onTriggered: {
            var now = Date.now() / 1000;
            var raw = activePlayer.position || 0;
            var playing = activePlayer.playbackState === MprisPlaybackState.Playing;
            var gap = _lastPosStamp > 0 ? now - _lastPosStamp : 0;

            if (!playing || gap > 30 || Math.abs(raw - _lastRealPos) > 0.04) {
                // 暂停、长时间无更新或播放器上报了新位置：重新锚定
                _lastRealPos = raw;
                _lastPosStamp = now;
                gap = 0;
            }

            var est = playing ? (_lastRealPos + Math.max(0, gap)) : raw;
            var len = activePlayer.length || 0;
            if (len > 0 && est > len)
                est = len;

            // 应用歌词时间偏移量
            var adjusted = est + root.lyricsOffset;

            var newIndex = -1;
            for (var i = lyricsLines.length - 1; i >= 0; i--) {
                if (lyricsLines[i].time === 0)
                    continue;
                if (adjusted >= lyricsLines[i].time) {
                    newIndex = i;
                    break;
                }
            }
            if (newIndex !== currentLineIndex)
                currentLineIndex = newIndex;
        }
    }

    // -------------------------------------------------------------------------
    // 显示选项辅助：假名检测 / 双语分组过滤 / 当前原文-翻译对
    // -------------------------------------------------------------------------

    function _hasKana(s) {
        if (!s)
            return false;
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i);
            if ((c >= 0x3040 && c <= 0x30FF) || (c >= 0xFF66 && c <= 0xFF9D))
                return true;
        }
        return false;
    }

    function _isBlocked(t) {
        if (!t || _blocklist.length === 0)
            return false;
        var s = t.toLowerCase();
        for (var i = 0; i < _blocklist.length; i++) {
            if (s.includes(_blocklist[i].toLowerCase()))
                return true;
        }
        return false;
    }

    // 缓存首行的 "歌名 - 歌手" 元数据头，不算歌词
    function _isHeaderLine(t) {
        if (!t || !currentTitle || !currentArtist)
            return false;
        return t.includes(currentTitle) && t.includes(currentArtist);
    }

    // 将歌词按时间戳分组（容差 0.35s，兼容双语行毫秒级偏差），按语言过滤并剔除屏蔽行
    function rebuildDisplayLines() {
        var mode = lyricLanguage;
        if (lyricsLines.length === 0) {
            displayLines = [];
            _syncDisplayIndex();
            _rebuildCurrentPair();
            return;
        }
        var out = [];
        var i = 0;
        while (i < lyricsLines.length) {
            if (_isBlocked(lyricsLines[i].text) || _isHeaderLine(lyricsLines[i].text) || lyricsLines[i].time === 0) {
                i++;
                continue;
            }
            var t0 = lyricsLines[i].time;
            var group = [];
            while (i < lyricsLines.length && Math.abs(lyricsLines[i].time - t0) < 0.35) {
                if (!_isBlocked(lyricsLines[i].text) && !_isHeaderLine(lyricsLines[i].text))
                    group.push(i);
                i++;
            }
            if (group.length === 0)
                continue;
            var origIdx = group[0];
            for (var g = 0; g < group.length; g++) {
                if (_hasKana(lyricsLines[group[g]].text)) {
                    origIdx = group[g];
                    break;
                }
            }
            var transIdx = -1;
            for (var g2 = 0; g2 < group.length; g2++) {
                if (group[g2] !== origIdx && !_hasKana(lyricsLines[group[g2]].text)) {
                    transIdx = group[g2];
                    break;
                }
            }
            if (transIdx === -1 && group.length > 1)
                transIdx = (group[0] === origIdx) ? group[1] : group[0];

            if (mode === "original") {
                var entryO = lyricsLines[origIdx];
                entryO.src = origIdx;
                out.push(entryO);
                continue;
            }
            if (mode === "translation") {
                var pickT = transIdx !== -1 ? transIdx : origIdx;
                var entryT = lyricsLines[pickT];
                entryT.src = pickT;
                out.push(entryT);
                continue;
            }
            // both（原文|翻译）：同时间组拼接为一行
            var oText = lyricsLines[origIdx].text || "";
            var tText = transIdx !== -1 ? (lyricsLines[transIdx].text || "") : "";
            var combined = oText;
            if (tText && tText !== oText)
                combined = combined ? combined + " | " + tText : tText;
            if (combined) {
                var entryB = { time: t0, text: combined };
                entryB.src = origIdx;
                out.push(entryB);
            }
        }
        displayLines = out;
        _syncDisplayIndex();
        _rebuildCurrentPair();
    }

    function _syncDisplayIndex() {
        if (currentLineIndex < 0 || displayLines.length === 0) {
            currentDisplayIndex = -1;
            return;
        }
        var idx = -1;
        for (var j = 0; j < displayLines.length; j++) {
            var src = displayLines[j].src !== undefined ? displayLines[j].src : j;
            if (src <= currentLineIndex)
                idx = j;
            else
                break;
        }
        currentDisplayIndex = idx;
    }

    // 当前时间组的 { 原文, 翻译 } 文本对（居中分栏模式使用）
    function _rebuildCurrentPair() {
        if (lyricsLines.length === 0 || currentLineIndex < 0) {
            currentPair = null;
            return;
        }
        var t0 = lyricsLines[currentLineIndex].time;
        var start = currentLineIndex;
        while (start > 0 && Math.abs(lyricsLines[start - 1].time - t0) < 0.35)
            start--;
        var end = currentLineIndex;
        while (end < lyricsLines.length - 1 && Math.abs(lyricsLines[end + 1].time - t0) < 0.35)
            end++;
        var orig = "";
        var trans = "";
        var origIdx = -1;
        for (var k = start; k <= end; k++) {
            var tx = lyricsLines[k].text || "";
            if (!tx || _isBlocked(tx))
                continue;
            if (!orig && _hasKana(tx)) {
                orig = tx;
                origIdx = k;
            } else if (!trans && !_hasKana(tx))
                trans = tx;
        }
        if (!orig) {
            // 无假名语言（中/韩/英）：清空重来，组内首行为原文、下一非屏蔽行为翻译
            orig = "";
            trans = "";
            origIdx = -1;
            for (var k2 = start; k2 <= end; k2++) {
                var tx2 = lyricsLines[k2].text || "";
                if (!tx2 || _isBlocked(tx2))
                    continue;
                if (!orig) {
                    orig = tx2;
                    origIdx = k2;
                } else if (!trans)
                    trans = tx2;
            }
        }
        if (!trans) {
            // 两行都含假名（如重复的拟声词带引号）等情况：取组内原文以外的另一非屏蔽行
            for (var k3 = start; k3 <= end; k3++) {
                var tx3 = lyricsLines[k3].text || "";
                if (k3 === origIdx || !tx3 || _isBlocked(tx3))
                    continue;
                trans = tx3;
                break;
            }
        }
        currentPair = { orig: orig, trans: trans };
    }

    function currentDisplayText() {
        if (displayLines.length > 0 && currentDisplayIndex >= 0 && currentDisplayIndex < displayLines.length)
            return displayLines[currentDisplayIndex].text || "";
        return "";
    }

    function pillSingleText() {
        if (isBrowserVideo)
            return currentTitle || "";
        var t = currentDisplayText();
        if (t !== "")
            return t;
        if (lyricsLines.length === 0 || currentLineIndex < 0 ||
            (currentLineIndex >= 0 && lyricsLines[currentLineIndex] &&
             _isInstrumentalMarker(lyricsLines[currentLineIndex].text)))
            return currentTitle || (root.pureInstrumental
                ? (root.isEnglish ? "Instrumental" : "纯音乐")
                : (root.isEnglish ? "No Lyrics" : "暂无歌词"));
        return "";
    }

    // -------------------------------------------------------------------------
    // Status chip helpers
    // -------------------------------------------------------------------------

    readonly property var _chipMeta: ({
            [status.searching]: {
                color: Theme.secondary,
                icon: "hourglass_top",
                label: root.isEnglish ? "Searching…" : "搜索中…"
            },
            [status.found]: {
                color: root._cardAccent,
                icon: "check_circle",
                label: root.isEnglish ? "Found - Synced Lyrics" : "已找到 - 同步歌词"
            },
            [status.notFound]: {
                color: Theme.warning,
                icon: "cancel",
                label: root.isEnglish ? "Not Found" : "未找到"
            },
            [status.error]: {
                color: Theme.error,
                icon: "error",
                label: root.isEnglish ? "Error" : "错误"
            },
            [status.skippedConfig]: {
                color: Theme.warning,
                icon: "block",
                label: root.isEnglish ? "Skipped - Not Configured" : "已跳过 - 未配置"
            },
            [status.skippedFound]: {
                color: Theme.warning,
                icon: "block",
                label: root.isEnglish ? "Skipped - Found" : "已跳过 - 已找到"
            },
            [status.cacheHit]: {
                color: root._cardAccent,
                icon: "check_circle",
                label: root.isEnglish ? "Cache Hit - From Cache" : "缓存命中 - 从缓存加载"
            },
            [status.cacheMiss]: {
                color: Theme.warning,
                icon: "cancel",
                label: root.isEnglish ? "Cache Miss" : "缓存未命中"
            },
            [status.cacheDisabled]: {
                color: Theme.surfaceVariantText,
                icon: "do_not_disturb_on",
                label: root.isEnglish ? "Disabled" : "已禁用"
            }
        })

    function _chip(val) {
        return _chipMeta[val] ?? {
            color: Theme.surfaceContainerHighest,
            icon: "radio_button_unchecked",
            label: root.isEnglish ? "Idle" : "空闲"
        };
    }

    function chipColor(val) {
        return _chip(val).color;
    }
    function chipIcon(val) {
        return _chip(val).icon;
    }
    function chipLabel(val) {
        return _chip(val).label;
    }

    // -------------------------------------------------------------------------
    // Bar Pills: show current lyric line
    // -------------------------------------------------------------------------

    horizontalBarPill: {
        const show = (root.hasPlayer || root.idleClock);
        return show ? hPillComponent : null;
    }

    Component {
        id: hPillComponent
        Item {
            id: hPillRoot
            readonly property bool centered: root.coverPosition === "center"
            readonly property bool rightAligned: root.coverPosition === "right"
            readonly property bool dualMode: centered
            readonly property int fontSize: pluginData.lyricsFontSize || Theme.fontSizeMedium
            readonly property bool infoPaused: root.pausedState

            // 前奏阶段：正在播放但还没到第一句歌词
            readonly property bool introPhase: root.hasPlayer && root.isPlaying
                && root.displayLines.length > 0
                && root._lastRealPos < (root.displayLines[0]?.time ?? 0)

            // 纯音乐/无歌词：显示标题+作者而非 ♪ 符号
            readonly property bool instrumentalPhase: root.hasPlayer && root.isPlaying && !root.lyricsLoading
                && (root.lyricsLines.length === 0 ||
                    (root.currentLineIndex >= 0
                     && root.lyricsLines[root.currentLineIndex]
                     && root._isInstrumentalMarker(root.lyricsLines[root.currentLineIndex].text)))

            // 组件上滚轮调整系统音量（不拦截点击）
            // MouseArea removed for debugging - check if it blocks click propagation

            // 时钟固定宽度：以最宽占位串度量，数字变化不再抖动
            TextMetrics {
                id: _clockMetrics
                font.pixelSize: hPillRoot.fontSize
                font.family: Theme.fontFamily
                font.weight: Font.Bold
                text: {
                    const base = SettingsData.showSeconds ? "00:00:00" : "00:00";
                    return SettingsData.use24HourClock ? base : base + " PM";
                }
            }

            // 左右文本等宽（取较大者），保证封面始终居中
            readonly property real sideWidth: root.idleClock
                ? Math.ceil(_clockMetrics.advanceWidth) + 2
                : Math.max(centerLeftText.implicitWidth, centerRightText.implicitWidth)

            // 宽度完全随内容自适应，不留空位（动画只在文本层做，避免双层滞后导致封面漂移）
            implicitWidth: centered ? centerLayout.implicitWidth : leftLayout.implicitWidth
            implicitHeight: parent.widgetThickness ?? 44

            // 状态栏圆形封面（可旋转）
            component PillCover: Rectangle {
                width: 40
                height: 40
                radius: 20
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceContainerHighest
                clip: true

                DankAlbumArt {
                    anchors.fill: parent
                    activePlayer: root.activePlayer
                    showAnimation: false
                }

                RotationAnimation on rotation {
                    running: root.vinylSpin && root.isPlaying
                    from: 0
                    to: 360
                    duration: 8000
                    loops: Animation.Infinite
                }
            }

            // ── 靠左/靠右模式：封面在一侧，歌词在另一侧 ──
            Row {
                id: leftLayout
                visible: !hPillRoot.centered
                layoutDirection: hPillRoot.rightAligned ? Qt.RightToLeft : Qt.LeftToRight
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                PillCover {
                    visible: root.hasPlayer
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    layoutDirection: Qt.LeftToRight
                    spacing: 8
                    width: Math.min(implicitWidth, 350)

                    StyledText {
                        text: root.isBrowserVideo ? "🎬 " : ""
                        font.pixelSize: hPillRoot.fontSize
                        visible: root.isBrowserVideo && !hPillRoot.infoPaused
                    }

                    StyledText {
                        text: {
                            if (root.idleClock)
                                return root.clockText();
                            if (hPillRoot.introPhase) {
                                var iartist = root.currentArtist || "";
                                return iartist ? ((root.currentTitle || "") + " - " + iartist) : (root.currentTitle || "");
                            }
                            if (hPillRoot.infoPaused) {
                                var artist = root.currentArtist || "";
                                return artist ? ((root.currentTitle || "") + " - " + artist) : (root.currentTitle || "");
                            }
                            if (root.isBrowserVideo)
                                return root.currentTitle || "";
                            return root.currentDisplayText();
                        }
                        font.pixelSize: hPillRoot.fontSize
                        font.family: Theme.fontFamily
                        color: root.idleClock ? root._cardAccent : Theme.widgetTextColor
                        font.weight: Font.Bold
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                        elide: root.lyricEllipsis ? Text.ElideRight : Text.ElideNone
                        width: root.lyricEllipsis ? Math.min(implicitWidth, 350 - 48) : implicitWidth
                        visible: text !== ""
                    }

                    StyledText {
                        text: {
                            if (root.isBrowserVideo)
                                return "";
                            if (root.lyricsLines.length === 0 ||
                                (root.currentLineIndex >= 0 && root.lyricsLines[root.currentLineIndex] &&
                                 root._isInstrumentalMarker(root.lyricsLines[root.currentLineIndex].text))) {
                                return root.currentTitle || (root.pureInstrumental
                                    ? (root.isEnglish ? "Instrumental" : "纯音乐")
                                    : (root.isEnglish ? "No Lyrics" : "暂无歌词"));
                            }
                            return "";
                        }
                        font.pixelSize: hPillRoot.fontSize + 2
                        font.family: Theme.fontFamily
                        color: Theme.widgetTextColor
                        font.weight: Font.Bold
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 373)
                        visible: text !== "" && root.hasPlayer && !hPillRoot.infoPaused
                    }
                }
            }

            // ── 居中模式：左右等宽，封面始终精确居中 ──
            Row {
                id: centerLayout
                visible: hPillRoot.centered
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingM

                StyledText {
                    id: centerLeftText
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: root.idleClock ? Text.AlignHCenter : Text.AlignRight
                    text: {
                        if (root.idleClock)
                            return root.clockText();
                        if (hPillRoot.infoPaused || hPillRoot.introPhase || hPillRoot.instrumentalPhase)
                            return root.currentTitle || "";
                        if (hPillRoot.dualMode)
                            return root.currentPair?.orig ?? "";
                        return root.pillSingleText();
                    }
                    font.pixelSize: hPillRoot.fontSize
                    font.family: Theme.fontFamily
                    color: root.idleClock ? root._cardAccent : Theme.widgetTextColor
                    font.weight: Font.Bold
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: root.lyricEllipsis ? Text.ElideRight : Text.ElideNone
                    width: root.lyricEllipsis ? Math.min(hPillRoot.sideWidth, 300) : hPillRoot.sideWidth

                    Behavior on width {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    visible: text !== ""
                }

                PillCover {
                    visible: root.hasPlayer
                }

                StyledText {
                    id: centerRightText
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    text: {
                        if (hPillRoot.infoPaused || hPillRoot.introPhase || hPillRoot.instrumentalPhase)
                            return root.currentArtist || "";
                        if (hPillRoot.dualMode)
                            return root.currentPair?.trans ?? "";
                        return "";
                    }
                    font.pixelSize: hPillRoot.fontSize
                    font.family: Theme.fontFamily
                    color: Theme.widgetTextColor
                    font.weight: Font.Bold
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: root.lyricEllipsis ? Text.ElideRight : Text.ElideNone
                    width: root.lyricEllipsis ? Math.min(hPillRoot.sideWidth, 300) : hPillRoot.sideWidth

                    Behavior on width {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    visible: text !== ""
                }
            }
        }
    }


    verticalBarPill: root.activePlayer ? vPillComponent : null

    Component {
        id: vPillComponent
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "lyrics"
                size: Theme.iconSize
                color: root.lyricsLines.length > 0 ? root._cardAccent : Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: "♪"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // -------------------------------------------------------------------------
    // API Status Indicators Component (must be defined before use)
    // -------------------------------------------------------------------------
    component ApiStatusIndicators: Row {
        id: apiIndicators
        spacing: 8

        // 纯音乐识别指示器（无歌词且标题/歌手带纯音乐标记时覆盖各源状态）
        Rectangle {
            visible: root.pureInstrumental
            width: 96
            height: 28
            radius: 6
            color: Theme.withAlpha(Theme.tertiary, 0.25)
            border.color: Theme.tertiary
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                    name: "music_off"
                    size: Theme.iconSizeSmall
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isEnglish ? "Instrumental" : "纯音乐"
                    font.pixelSize: 12
                    color: Theme.tertiary
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // 网易云指示器 - 带图标的圆角矩形（优先显示）
        Rectangle {
            visible: !root.pureInstrumental
            width: 64
            height: 28
            radius: 6
            color: Theme.withAlpha(root._apiStatusColor(root.neteaseStatus), 0.25)
            border.color: root._apiStatusColor(root.neteaseStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                name: "cloud"
                size: Theme.iconSizeSmall
                color: root._apiStatusColor(root.neteaseStatus)
                anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isEnglish ? "NetEase" : "网易"
                    font.pixelSize: 12
                    color: root._apiStatusColor(root.neteaseStatus)
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ToolTip.text: root._chipMeta[root.neteaseStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲")
            ToolTip.visible: neteaseMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: neteaseMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // lrclib 指示器 - 带图标的圆角矩形
        Rectangle {
            visible: !root.pureInstrumental
            width: 64
            height: 28
            radius: 6
            color: Theme.withAlpha(root._apiStatusColor(root.lrclibStatus), 0.25)
            border.color: root._apiStatusColor(root.lrclibStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                name: "library_music"
                size: Theme.iconSizeSmall
                color: root._apiStatusColor(root.lrclibStatus)
                anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "LRC"
                    font.pixelSize: 12
                    color: root._apiStatusColor(root.lrclibStatus)
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ToolTip.text: root._chipMeta[root.lrclibStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲")
            ToolTip.visible: lrclibMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: lrclibMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // 缓存指示器 - 带图标的圆角矩形
        Rectangle {
            width: 64
            height: 28
            radius: 6
            color: Theme.withAlpha(root._apiStatusColor(root.cacheStatus), 0.25)
            border.color: root._apiStatusColor(root.cacheStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                name: "storage"
                size: Theme.iconSizeSmall
                color: root._apiStatusColor(root.cacheStatus)
                anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isEnglish ? "Cache" : "缓存"
                    font.pixelSize: 12
                    color: root._apiStatusColor(root.cacheStatus)
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ToolTip.text: root.cacheStatus === status.cacheHit ? 
                root.isEnglish ? "Click to clear cache and re-search" : "点击清除缓存并重新搜索" : (root._chipMeta[root.cacheStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲"))
            ToolTip.visible: cacheMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: cacheMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.cacheStatus === status.cacheHit ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.cacheStatus === status.cacheHit) {
                        root.clearCurrentCacheAndRefetch();
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Popout: Now Playing + Lyrics Sources
    // -------------------------------------------------------------------------

    function _formatDuration(seconds) {
        if (seconds <= 0) return "—";
        var m = Math.floor(seconds / 60);
        var s = Math.floor(seconds % 60);
        return m + ":" + ("0" + s).slice(-2);
    }

    popoutContent: Component {
        PopoutComponent {
            width: popoutWidth

            Loader {
                width: parent.width
                sourceComponent: root.idleClock ? worldClockComponent : musicComponent
            }
        }
    }

    Component {
        id: musicComponent

        Item {
            width: parent ? parent.width : 400
            implicitHeight: popoutLayout.implicitHeight

            Column {
                id: popoutLayout
                width: parent.width
                spacing: Theme.spacingM

                // ── Now Playing Card ──
                Rectangle {
                id: nowPlayingCard
                width: parent.width
                height: nowPlayingContent.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: root.activePlayer
                      ? Theme.surfaceContainerHigh
                      : Theme.surfaceContainer
                clip: true

                // ============================================
                // 黑胶唱片专辑封面
                // ============================================
                // 设计说明：
                // - 尺寸：200x200，保持原有大小
                // - 样式：深灰色带纹理的黑胶唱片效果
                // - 中心：80x80的专辑封面
                // - 位置：卡片右上角，部分超出边界
                // - 旋转动画：20秒/圈，更慢更优雅
                // ============================================
                Item {
                    id: _vinylRecordContainer
                    width: 200
                    height: 200
                    visible: root.activePlayer
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -40
                    anchors.rightMargin: -35
                    z: 10

                    // 黑胶唱片主体（深灰色圆形）
                    Rectangle {
                        id: vinylRecord
                        anchors.fill: parent
                        radius: 100
                        color: "#252525"  // 深灰色底色

                        // 唱片纹理（同心圆纹路）
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                var centerX = width / 2;
                                var centerY = height / 2;

                                // 绘制同心圆纹理（6条）
                                for (var i = 2; i < 8; i++) {
                                    ctx.beginPath();
                                    ctx.arc(centerX, centerY, 45 + i * 10, 0, 2 * Math.PI);
                                    ctx.strokeStyle = "#353535";  // 稍浅的灰色纹理
                                    ctx.lineWidth = 1;
                                    ctx.stroke();
                                }
                            }
                        }

                        // 中心专辑封面容器
                        Rectangle {
                            width: 130
                            height: 130
                            radius: 65
                            anchors.centerIn: parent
                            color: "#1a1a1a"  // 中心深色背景
                            clip: true

                            // 专辑封面
                            DankAlbumArt {
                                anchors.fill: parent
                                activePlayer: root.activePlayer
                                showAnimation: true
                            }
                        }

                        // 高光效果（增加立体感）
                        Rectangle {
                            anchors.fill: parent
                            radius: 100
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#20ffffff" }
                                GradientStop { position: 0.3; color: "#00ffffff" }
                                GradientStop { position: 0.7; color: "#00ffffff" }
                                GradientStop { position: 1.0; color: "#15000000" }
                            }
                        }
                    }

                    // 旋转动画（20秒/圈，总在播放时旋转）
                    RotationAnimation on rotation {
                        id: coverRotation
                        from: 0
                        to: 360
                        duration: 20000          // 20秒转一圈（更慢）
                        loops: Animation.Infinite
                        running: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing
                    }
                }

                Row {
                    id: nowPlayingContent
                    anchors {
                        left: parent.left; right: parent.right
                        top: parent.top
                        margins: Theme.spacingM
                    }
                    spacing: Theme.spacingM
                    clip: false
                    z: 1

                    // Track info column (takes full width, cover overlays on top)
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        // Header row: icon + "Now Playing"
                        Row {
                            spacing: Theme.spacingS
                            width: parent.width

                            DankIcon {
                                name: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing
                                      ? "play_circle" : "pause_circle"
                                size: Theme.iconSize
                                color: root.activePlayer ? root._cardAccent : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: {
                                    if (!root.activePlayer) return "无活动播放器";
                                    var identity = root.activePlayer.identity || "未知播放器";
                                    if (root.isBrowserVideo) return "🎬 Firefox 视频";
                                    if (root.isMusicVideo) return "🎵 " + identity + " MV";
                                    return identity + " 正在播放";
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: root.activePlayer ? root._cardAccent : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Song title
                        StyledText {
                            width: parent.width
                            text: root.currentTitle || "—"
                            font.pixelSize: Theme.fontSizeLarge + 2
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            visible: root.activePlayer
                        }

                        // Artist & Album - 字体跟随歌词字体设置
                        Column {
                            width: parent.width
                            spacing: 4
                            visible: root.activePlayer

                            Row {
                                spacing: Theme.spacingS
                                DankIcon {
                                    name: "person"
                                    size: Theme.iconSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.currentArtist || "未知艺术家"
                                    font.pixelSize: pluginData.lyricsFontSize || Theme.fontSizeMedium + 2
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                spacing: Theme.spacingS
                                visible: root.currentAlbum !== ""
                                DankIcon {
                                    name: "album"
                                    size: Theme.iconSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.currentAlbum
                                    font.pixelSize: pluginData.lyricsFontSize || Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // API 状态指示器 - 移动到歌曲信息下方，左对齐
                        ApiStatusIndicators {
                            visible: root.activePlayer && root.showStatusIndicators
                        }

                        // Spacer to ensure vertical separation from cover art
                        Item {
                            width: 1
                            height: _vinylRecordContainer.visible ? 24 : 0
                        }

                        // Progress bar with timestamps
                        Column {
                            width: parent.width
                            spacing: 4
                            visible: root.activePlayer && root.currentDuration > 0

                        // ============================================
                        // DMS Wave Progress (M3WaveProgress)
                        // ============================================
                        // 与 DMS 自带媒体面板一致的动态波浪进度条：
                        // - 播放时正弦波浪随 FrameAnimation 逐帧流动
                        // - 已播放部分用 accent 色填充，未播放为半透明轨道
                        // - 播放头为圆头 pill，拖动时实时预览，松手才 seek
                        // ============================================
                        M3WaveProgress {
                            id: macProgressBar
                            width: parent.width
                            height: 32
                            anchors.horizontalCenter: parent.horizontalCenter

                            readonly property real ratio: {
                                void root._forceUpdate; // 依赖轮询触发更新
                                if (!root.activePlayer || !root.activePlayer.length) return 0;
                                return Math.min(1, (root.activePlayer.position || 0) / root.activePlayer.length);
                            }
                            property real dragRatio: -1

                            value: dragRatio >= 0 ? dragRatio : ratio
                            actualValue: ratio
                            showActualPlaybackState: waveMouse.pressed
                            isPlaying: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing
                            fillColor: root._cardAccent
                            playheadColor: root._cardAccent
                            trackColor: root._cardAccentTrack
                            actualProgressColor: root._cardAccentSubtle

                            MouseArea {
                                id: waveMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.activePlayer && root.activePlayer.canSeek && root.activePlayer.length > 0

                                onPressed: (mouse) => {
                                    if (!root.activePlayer) return;
                                    macProgressBar.dragRatio = Math.max(0, Math.min(1, mouse.x / parent.width));
                                }
                                onPositionChanged: (mouse) => {
                                    if (pressed && root.activePlayer)
                                        macProgressBar.dragRatio = Math.max(0, Math.min(1, mouse.x / parent.width));
                                }
                                onReleased: (mouse) => {
                                    if (!root.activePlayer) return;
                                    macProgressBar.dragRatio = -1;
                                    if (root.activePlayer.canSeek && root.activePlayer.length > 0) {
                                        const target = mouse.x / parent.width * root.activePlayer.length;
                                        root.activePlayer.position = Math.max(0.1, Math.min(target, root.activePlayer.length * 0.99));
                                    }
                                }
                                onCanceled: macProgressBar.dragRatio = -1
                            }
                        }

                            // Poll MPRIS position to keep progress bar and time text updated
                            Timer {
                                id: progressPollTimer
                                interval: 100
                                running: root.activePlayer !== null
                                repeat: true
                                onTriggered: {
                                    root._forceUpdate = !root._forceUpdate;
                                }
                            }

                            Row {
                                width: parent.width

                                StyledText {
                                    id: _currentTime
                                    text: {
                                        void root._forceUpdate; // depend on polling toggle
                                        if (!activePlayer)
                                            return "0:00";
                                        const rawPos = Math.max(0, activePlayer.position || 0);
                                        const pos = activePlayer.length ? rawPos % Math.max(1, activePlayer.length) : rawPos;
                                        const minutes = Math.floor(pos / 60);
                                        const seconds = Math.floor(pos % 60);
                                        const timeStr = minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                                        return timeStr;
                                    }
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.weight: Font.Bold
                                    color: root._cardAccent
                                }

                                Item { width: parent.width - _currentTime.implicitWidth - _endTime.implicitWidth; height: 1 }

                                StyledText {
                                    id: _endTime
                                    text: {
                                        if (!activePlayer || !activePlayer.length)
                                            return "0:00";
                                        const dur = Math.max(0, activePlayer.length || 0);
                                        const minutes = Math.floor(dur / 60);
                                        const seconds = Math.floor(dur % 60);
                                        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                                    }
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.weight: Font.Bold
                                    color: root._cardAccent
                                }
                            }

                            // Playback controls - 放大但保持原有样式
                            Row {
                                width: parent.width
                                height: 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: Theme.spacingXL

                                // Previous button（增大到52x52）
                                MouseArea {
                                    width: 52
                                    height: 52
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: {
                                        if (root.activePlayer)
                                            root.activePlayer.previous();
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "skip_previous"
                                        size: 32
                                        color: root._cardAccent
                                    }
                                }

                                // Play/Pause button（增大到64x64）
                                MouseArea {
                                    width: 64
                                    height: 64
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: {
                                        if (root.activePlayer) {
                                            if (root.activePlayer.playbackState === MprisPlaybackState.Playing)
                                                root.activePlayer.pause();
                                            else
                                                root.activePlayer.play();
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 32
                                        color: root._cardAccent
                                        opacity: 0.1
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                                        size: 40
                                        color: root._cardAccent
                                    }
                                }

                                // Next button（增大到52x52）
                                MouseArea {
                                    width: 52
                                    height: 52
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: {
                                        if (root.activePlayer)
                                            root.activePlayer.next();
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "skip_next"
                                        size: 32
                                        color: root._cardAccent
                                    }
                                }
                            }
                        }

                    }
                }
            }

                // ── 工具栏：设置 + 歌词微调 ──
                Row {
                    width: parent.width
                    height: 36
                    spacing: Theme.spacingS

                    // 设置按钮
                    Rectangle {
                        width: settingsRow.implicitWidth + Theme.spacingM * 2
                        height: 36
                        radius: Theme.cornerRadius
                        color: settingsBtnMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        Row {
                            id: settingsRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: "settings"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: root.isEnglish ? "Settings" : "设置"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: settingsBtnMA
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof PopoutService !== "undefined")
                                    PopoutService.openSettingsWithTab("plugins");
                            }
                        }
                    }

                    // 歌词微调
                    Row {
                        id: offsetRow
                        height: 36
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            id: offsetMinusMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.lyricsOffset = Math.round((root.lyricsOffset - 0.1) * 10) / 10
                            cursorShape: Qt.PointingHandCursor

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: offsetMinusMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "remove"; size: 16
                                color: Theme.surfaceText
                            }
                        }

                        StyledText {
                            text: (root.lyricsOffset >= 0 ? "+" : "") + root.lyricsOffset.toFixed(1) + "s"
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: "monospace"
                            color: root.lyricsOffset !== 0 ? root._cardAccent : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            id: offsetPlusMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.lyricsOffset = Math.round((root.lyricsOffset + 0.1) * 10) / 10
                            cursorShape: Qt.PointingHandCursor

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: offsetPlusMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "add"; size: 16
                                color: Theme.surfaceText
                            }
                        }

                        MouseArea {
                            id: offsetResetMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.lyricsOffset !== 0
                            onClicked: root.lyricsOffset = 0
                            cursorShape: Qt.PointingHandCursor

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: offsetResetMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "restart_alt"; size: 16
                                color: Theme.error
                            }
                        }

                        MouseArea {
                            id: offsetSaveMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.lyricsOffset !== 0 && root.currentTitle !== "" && root.lyricsLines.length > 0
                            onClicked: {
                                root.writeToCache(root.currentTitle, root.currentArtist || "", root.lyricsLines, root.lyricSource);
                                console.info("[Lyrics] 偏移已保存: +" + root.lyricsOffset + "s -> \"" + root.currentTitle + "\"");
                            }
                            cursorShape: Qt.PointingHandCursor

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: offsetSaveMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "save"; size: 16
                                color: root._cardAccent
                            }

                            ToolTip.text: root.isEnglish ? "Save Lyrics Offset" : "保存歌词偏移"
                            ToolTip.visible: offsetSaveMA.containsMouse
                            ToolTip.delay: 500
                        }

                        MouseArea {
                            id: openCacheMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                if (root.currentTitle) {
                                    var cachePath = root._cacheFilePath(root.currentTitle, root.currentArtist || "")
                                    root.cacheProbe.probePath = cachePath
                                    root.cacheProbe.path = cachePath
                                    root.cacheProbe.load()
                                }
                            }
                            cursorShape: Qt.PointingHandCursor

                            ToolTip.text: root.isEnglish ? "View Lyrics File" : "查看歌词文件"
                            ToolTip.visible: openCacheMA.containsMouse
                            ToolTip.delay: 500

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: openCacheMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "folder_open"; size: 16
                                color: Theme.surfaceText
                            }
                        }

                        MouseArea {
                            id: scanLibMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                if (root.scanLibRunning) return
                                var script = Qt.resolvedUrl("./import-embedded-lyrics.sh").toString().replace("file://", "")
                                var libDir = root.musicLibraryPath
                                scanLibProcess.command = ["bash", script, libDir]
                                scanLibProcess.running = true
                            }
                            cursorShape: Qt.PointingHandCursor

                            ToolTip.text: scanLibRunning ? root.isEnglish ? "Importing..." : "导入中..." : root.isEnglish ? "Import Lyrics" : "导入缓存"
                            ToolTip.visible: scanLibMA.containsMouse
                            ToolTip.delay: 500

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: scanLibMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "library_music"; size: 16
                                color: Theme.surfaceText
                            }
                        }
                    }

                    // 导入缓存状态提示
                    StyledText {
                        text: root.scanLibRunning ? root.isEnglish ? "Importing..." : "导入中..." :
                              root.scanLibStatus === "ok" ? root.isEnglish ? "Import Succeeded" : "导入成功" :
                              root.scanLibStatus === "fail" ? root.isEnglish ? "Import Failed" : "导入失败" : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.scanLibStatus === "fail" ? Theme.error : root._cardAccent
                        visible: root.scanLibStatus !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    Component {
        id: worldClockComponent

        Item {
            id: wcRoot
            property real cw: parent ? parent.width : 400
            width: cw
            implicitHeight: worldRow.implicitHeight

            Column {
                id: worldRow
                width: wcRoot.cw
                spacing: Theme.spacingS

                Repeater {
                    model: root._clockTimezonesArr

                    Rectangle {
                        width: wcRoot.cw
                        height: wcCol.implicitHeight + Theme.spacingM * 1.6
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            id: wcCol
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData[0]
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.widgetTextColor
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root._tzTime(modelData[1])
                                font.pixelSize: Theme.fontSizeLarge + 8
                                font.weight: Font.Bold
                                color: Theme.widgetTextColor
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root._tzDateStr(modelData[1])
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.widgetTextColor
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: root.idleClock ? 360 : 420
    popoutHeight: root.idleClock ? 320 : 380

    function _apiStatusColor(statusVal) {
        switch (statusVal) {
            case status.error:
                return Theme.error;      // 错误状态使用主题错误色
            case status.searching:
                return Theme.warning;    // 搜索中状态使用主题警告色
            case status.found:
            case status.cacheHit:
                return root._cardAccent;    // 找到和缓存命中使用主色
            case status.none:
            case status.skippedConfig:
            default:
                return Theme.surfaceVariantText;  // 默认状态使用表面变体文本色
        }
    }

    // -------------------------------------------------------------------------
    // Reusable source status card
    // -------------------------------------------------------------------------

    component SourceCard: Rectangle {
        id: sourceCard
        property string icon: ""
        property string label: ""
        property int sourceStatus: 0

        height: 44
        radius: Theme.cornerRadius
        color: sourceStatus === 0
               ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.3)
               : Theme.withAlpha(root.chipColor(sourceStatus), 0.06)
        visible: true

        Row {
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
            }
            spacing: Theme.spacingS

            // Source icon
            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: sourceCard.sourceStatus === 0
                   ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)
                   : Theme.withAlpha(root.chipColor(sourceCard.sourceStatus), 0.15)
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                anchors.centerIn: parent
                name: sourceCard.icon
                size: Theme.iconSizeSmall
                color: sourceCard.sourceStatus === 0
                       ? Theme.surfaceVariantText
                       : root.chipColor(sourceCard.sourceStatus)
                }
            }

            // Label
            StyledText {
                text: sourceCard.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
                width: 90
            }

            // Status chip – fills remaining width
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - parent.spacing * 2 - 28 - 90
                height: 22

                Rectangle {
                visible: sourceCard.sourceStatus !== 0
                anchors.fill: parent
                radius: 11
                color: Theme.withAlpha(root.chipColor(sourceCard.sourceStatus), 0.15)

                Row {
                    id: statusChipContent
                    anchors.centerIn: parent
                    spacing: 4

                    DankIcon {
                        name: root.chipIcon(sourceCard.sourceStatus)
                        size: Theme.iconSizeXSmall
                        color: root.chipColor(sourceCard.sourceStatus)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root._chipMeta[sourceCard.sourceStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲")
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: root.chipColor(sourceCard.sourceStatus)
                        anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                }
                }

                // Idle label when no status
                Rectangle {
                visible: sourceCard.sourceStatus === 0
                anchors.fill: parent
                radius: 11
                color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.3)

                StyledText {
                    anchors.centerIn: parent
                    text: root.isEnglish ? "Idle" : "空闲"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                }
                }
            }
        }
    }

}
