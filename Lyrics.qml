import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    layerNamespacePlugin: "lyricsEmbed"
    property bool cachingEnabled: pluginData.cachingEnabled ?? true
    property bool lrclibEnabled: pluginData.lrclibEnabled ?? true
    property bool neteaseEnabled: pluginData.neteaseEnabled ?? true
    property bool customApiEnabled: pluginData.customApiEnabled ?? false
    property string customApiUrl: pluginData.customApiUrl ?? ""
    property string customApiMethod: pluginData.customApiMethod ?? "GET"
    property string language: pluginData.language ?? "auto"

    readonly property bool _systemChinese: (Qt.locale().name || "").toLowerCase().startsWith("zh")
        || (Quickshell.env("LANG") || "").toLowerCase().startsWith("zh")

    readonly property bool isEnglish: {
        var la = root.language;
        if (la === "auto")
            la = root._systemChinese ? "zh" : "en";
        return la === "en";
    }
    // MPRIS 播放器

    property string playerWhitelist: pluginData.playerWhitelist ?? ""
    readonly property var _whitelist: playerWhitelist.split(/[,，、\s]+/)
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
    // 浏览器视频检测
    
    readonly property bool isFirefox: {
        var identity = activePlayer?.identity?.toLowerCase() || "";
        return identity.includes("firefox") || identity.includes("mozilla");
    }
    
    readonly property var _mvKeywords: [
        "mv", "music video", "official video", "official mv", 
        "musicvideo", "video clip", "videoclip",
        "【mv】", "【music video】", "【官方mv】", "【官方版】",
        "official music video", "official hd", "official 4k",
        "歌词版", "歌词mv", "lyrics video", "lyric video"
    ]
    
    readonly property var _nonMvKeywords: [
        "tutorial", "review", "unboxing", "gameplay", 
        "walkthrough", "guide", "how to", "ep.", "episode",
        "教程", "评测", "开箱", "游戏", "攻略", "第", "集"
    ]
    
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
    
    readonly property bool isBrowserVideo: {
        return isFirefox && !isMusicVideo && currentTitle !== "";
    }
    
    readonly property bool shouldSearchLyrics: {
        // 不是火狐浏览器 - 正常搜索歌词
        if (!isFirefox) return true;
        
        // 是火狐浏览器且是MV - 搜索歌词
        if (isMusicVideo) return true;
        
        // 是火狐浏览器但不是MV - 不搜索歌词
        return false;
    }
    // 状态枚举

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

    QtObject {
        id: lyricState
        readonly property int idle: 0
        readonly property int loading: 1
        readonly property int synced: 2
        readonly property int notFound: 3
    }

    QtObject {
        id: lyricSrc
        readonly property int none: 0
        readonly property int lrclib: 1
        readonly property int cache: 2
        readonly property int netease: 3
        readonly property int custom: 4
        readonly property int embedded: 5
    }
    property var lyricsLines: []
    property int currentLineIndex: -1
    // 纯文本歌词没有时间轴，显示首行且不启动位置轮询
    property bool lyricsArePlain: false

    property string coverPosition: pluginData.coverPosition ?? "left"
    property string lyricLanguage: pluginData.lyricLanguage ?? "both"
    property bool lyricEllipsis: pluginData.lyricEllipsis ?? true
    property bool vinylSpin: pluginData.vinylSpin ?? true
    property bool showClockWhenIdle: pluginData.showClockWhenIdle ?? false
    property string lyricBlocklist: pluginData.lyricBlocklist ?? ""
    property string musicLibraryPath: pluginData.musicLibraryPath || (Quickshell.env("HOME") + "/Music")

    property real lyricsOffset: 0
    property bool _suppressOffsetSave: false

    property string scanLibStatus: ""
    property bool scanLibRunning: scanLibStatus === "running"

    property string clockTimezones: pluginData.clockTimezones ?? "中国时间:8,日本时间:9,太平洋时间:auto"
    property bool useAlbumAccent: pluginData.useAlbumAccent ?? true
    property bool usePillAccent: pluginData.usePillAccent ?? false
    property bool showStatusIndicators: pluginData.showStatusIndicators ?? true
    property bool scrollWheelVolume: pluginData.scrollWheelVolume ?? true
    readonly property color _cardAccent: root.useAlbumAccent ? MediaAccentService.accent : Theme.primary
    readonly property color _cardAccentTrack: Theme.withAlpha(root._cardAccent, 0.28)
    readonly property color _cardAccentSubtle: Theme.withAlpha(root._cardAccent, 0.55)

    readonly property var _blocklist: lyricBlocklist.split(/[,，、\s]+/)
        .map(function(s) { return s.trim(); })
        .filter(function(s) { return s.length > 0; })

    onLyricLanguageChanged: rebuildDisplayLines()
    onLyricBlocklistChanged: rebuildDisplayLines()

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool pausedState: hasPlayer && !isPlaying
    readonly property bool idleClock: showClockWhenIdle && !hasPlayer

    // 专辑封面 URL：优先使用 MPRIS trackArtUrl，回退到 metadata 中的 mpris:artUrl
    readonly property string albumArtUrl: {
        var p = activePlayer;
        if (!p) return "";
        if (p.trackArtUrl) return p.trackArtUrl;
        var m = p.metadata;
        return m && m["mpris:artUrl"] ? m["mpris:artUrl"].toString() : "";
    }

    // 与 DMS 内置时钟同源：SystemClock 驱动，精度跟随系统设置
    SystemClock {
        id: idleSystemClock
        precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    property var displayLines: []
    property int currentDisplayIndex: -1
    property var currentPair: null

    onLyricsLinesChanged: rebuildDisplayLines()
    onLyricsArePlainChanged: rebuildDisplayLines()
    onCurrentLineIndexChanged: {
        _syncDisplayIndex();
        _rebuildCurrentPair();
    }
    property bool lyricsLoading: lyricStatus === lyricState.loading

    property string _lastFetchedTrack: ""
    property string _lastFetchedArtist: ""
    property string _lastSyncedTrack: ""
    property string _lastSyncedArtist: ""
    property var _cancelActiveFetch: null
    property int _xhrRequestSeq: 0
    property int _activeXhrRequest: 0
    property int _fetchToken: 0

    property int lrclibStatus: status.none
    property int neteaseStatus: status.none
    property int cacheStatus: status.none

    property int lyricStatus: lyricState.idle
    property int lyricSource: lyricSrc.none

    property string currentTitle: activePlayer?.trackTitle ?? ""
    property string currentArtist: activePlayer?.trackArtist ?? ""
    property string currentAlbum: activePlayer?.trackAlbum ?? ""
    property real currentDuration: activePlayer?.length ?? 0

    property bool _forceUpdate: false
    property string currentLyricText: {
        // 处理歌曲名：去掉括号及括号内容
        var title = currentTitle || (root.pureInstrumental
            ? (root.isEnglish ? "Instrumental" : "纯音乐")
            : (root.isEnglish ? "No Lyrics" : "暂无歌词"));
        title = title.replace(/[（(].*?[）)]/g, "");  // 去掉括号及内容
        
        // 如果有歌词，显示"歌曲名 歌词"
        var line = currentLineIndex >= 0 ? lyricsLines[currentLineIndex] : null;
        if (lyricsLines.length > 0 && line && line.text) {
            return title + "  " + line.text;
        }
        return title;
    }

    readonly property bool builtinSourcesEnabled: neteaseEnabled || lrclibEnabled
    readonly property bool onlineSourcesEnabled: builtinSourcesEnabled
        || (customApiEnabled && customApiUrl && customApiUrl.trim() !== "")

    // 当前曲目是否为纯音乐：
    readonly property bool pureInstrumental: !lyricsLoading
        && lyricsLines.length === 0
        && (_isInstrumentalIdentity(currentTitle, currentArtist) || !root.onlineSourcesEnabled)
    // 定时器

    Timer {
        id: fetchDebounceTimer
        interval: 300
        onTriggered: root.fetchLyricsIfNeeded()
    }

    Timer {
        id: offsetSaveTimer
        interval: 500
        onTriggered: root._saveCurrentOffset()
    }

    onCurrentTitleChanged: {
        _resetLyricsForTrack();
        fetchDebounceTimer.restart();
    }
    onCurrentArtistChanged: fetchDebounceTimer.restart()
    onLyricsOffsetChanged: {
        if (!_suppressOffsetSave && lyricsLines.length > 0
                && lyricStatus === lyricState.synced)
            offsetSaveTimer.restart();
    }

    Timer {
        id: xhrTimeoutTimer
        repeat: false
        property int ownerId: 0
        property var onTimeout: null
        onTriggered: if (onTimeout) onTimeout()
    }

    Timer {
        id: xhrRetryTimer
        repeat: false
        property int ownerId: 0
        property var onRetry: null
        onTriggered: if (onRetry) onRetry()
    }
    function _resetLyricsState() {
        offsetSaveTimer.stop();
        lyricsLines = [];
        lyricsArePlain = false;
        currentLineIndex = -1;
        _suppressOffsetSave = true;
        lyricsOffset = 0;
        _suppressOffsetSave = false;
        lrclibStatus = status.none;
        neteaseStatus = status.none;
        cacheStatus = status.none;
        lyricStatus = lyricState.loading;
        lyricSource = lyricSrc.none;
    }
    function _setFinalNotFound(sourceStatusVal) {
        // 已禁用的源保持“未启用”状态，不伪装成请求失败
        lrclibStatus = lrclibEnabled ? sourceStatusVal : status.skippedConfig;
        neteaseStatus = neteaseEnabled ? sourceStatusVal : status.skippedConfig;
        lyricStatus = lyricState.notFound;
        root._cancelActiveFetch = null;
    }
    // 缓存管理

    readonly property string _cacheDir: (Quickshell.env("HOME") || "") + "/.cache/Lyrics"
    property bool _cacheDirReady: false

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root._cacheDir]
        running: false
    }

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

    function _sanitizeFilename(s) {
        if (!s) return "";
        var out = s.replace(/[\\\/\u0000-\u001f\u007f]/g, "_");
        out = out.trim();
        if (out.charAt(0) === ".") out = "_" + out.slice(1);
        if (out === "") out = "untitled";
        return out;
    }

    function _utf8ByteLength(s) {
        var bytes = 0;
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i);
            if (c < 0x80) bytes += 1;
            else if (c < 0x800) bytes += 2;
            else if (c >= 0xD800 && c <= 0xDBFF) {
                if (i + 1 < s.length) {
                    var d = s.charCodeAt(i + 1);
                    if (d >= 0xDC00 && d <= 0xDFFF) { bytes += 4; i++; continue; }
                }
                bytes += 3;
            }
            else bytes += 3;
        }
        return bytes;
    }

    function _truncateUtf8Bytes(s, maxBytes) {
        if (_utf8ByteLength(s) <= maxBytes) return s;
        var out = "";
        for (var i = 0; i < s.length;) {
            var c = s.charCodeAt(i);
            var n;
            if (c < 0x80) n = 1;
            else if (c < 0x800) n = 2;
            else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
                var d = s.charCodeAt(i + 1);
                if (d >= 0xDC00 && d <= 0xDFFF) n = 4;
                else n = 3;
            }
            else n = 3;
            if (_utf8ByteLength(out) + n > maxBytes) break;
            if (n === 4) {
                var lo = s.charCodeAt(i + 1);
                out += s.charAt(i) + String.fromCharCode(lo);
                i += 2;
            } else {
                out += s.charAt(i);
                i += 1;
            }
        }
        return out + "...";
    }

    function _cacheFilePath(title, artist) {
        var key = _cacheKey(title, artist);
        var readable = _sanitizeFilename(title) + " - " + _sanitizeFilename(artist);
        readable = _truncateUtf8Bytes(readable, 190);
        return _cacheDir + "/" + readable + "_" + key + ".json";
    }

/**
     * 从缓存读取歌词
     */
    function readFromCache(title, artist, callback) {
        var newPath = _cacheFilePath(title, artist);
        var oldPath = _cacheDir + "/" + _cacheKey(title, artist) + ".json";
        var queue = newPath === oldPath ? [newPath] : [newPath, oldPath];
        _readPathQueue(queue, callback, title, artist, newPath);
    }
    function _readPathQueue(paths, callback, title, artist, newPath) {
        if (!callback) return;
        if (!paths || paths.length === 0) {
            callback(null);
            return;
        }
        var reader = cacheReaderComponent.createObject(root, {
            callback: callback,
            pathQueue: paths.slice(1),
            cTitle: title,
            cArtist: artist,
            cNewPath: newPath
        });
        reader.path = paths[0];
    }
    function _validLyricsLines(lines) {
        if (!Array.isArray(lines) || lines.length === 0)
            return false;
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (!line || typeof line.text !== "string"
                    || typeof line.time !== "number" || !isFinite(line.time))
                return false;
        }
        return true;
    }
    function _cacheIsPlain(cached) {
        if (!cached)
            return false;
        if (typeof cached.plain === "boolean")
            return cached.plain;
        // 兼容旧缓存：纯文本歌词曾以 time=0 写入但没有 plain 字段
        var lines = cached.lines;
        if (!_validLyricsLines(lines))
            return false;
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].time !== 0)
                return false;
        }
        return true;
    }
    function writeToCache(title, artist, lines, source, offset, plain) {
        _ensureCacheDir();
        cacheWriterComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            cTitle: title,
            cArtist: artist,
            cLines: lines,
            cSource: source,
            cOffset: typeof offset === "number" ? offset : root.lyricsOffset,
            cPlain: plain === true
        });
    }
    function _saveCurrentOffset() {
        if (!cachingEnabled || !currentTitle || lyricsLines.length === 0)
            return;
        if (lyricStatus !== lyricState.synced)
            return;
        if (currentTitle !== _lastSyncedTrack || currentArtist !== _lastSyncedArtist)
            return;
        writeToCache(currentTitle, currentArtist, lyricsLines, lyricSource,
                     lyricsOffset, lyricsArePlain);
    }
    function clearCurrentCacheAndRefetch() {
        if (!currentTitle) return;

        // 立即作废并取消进行中的请求，避免删除缓存后旧响应又把缓存写回来
        _fetchToken++;
        offsetSaveTimer.stop();
        _lastSyncedTrack = "";
        _lastSyncedArtist = "";
        if (_cancelActiveFetch) {
            _cancelActiveFetch();
            _cancelActiveFetch = null;
        }

        var cacheFiles = [ _cacheFilePath(currentTitle, currentArtist),
                           _cacheDir + "/" + _cacheKey(currentTitle, currentArtist) + ".json" ];
        console.info("[Lyrics] 清除缓存: \"" + currentTitle + "\"");
        
        // 使用 Process 删除缓存文件（新可读名 + 旧 hash 名）
        var deleter = cacheDeleterProcessComponent.createObject(root, {
            cacheFiles: cacheFiles
        });
        if (deleter)
            deleter.running = true;
    }

    Component {
        id: cacheDeleterProcessComponent
        Process {
            property var cacheFiles: []
            
            command: ([]).concat(["rm", "-f"], cacheFiles)
            
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

    Component {
        id: cacheReaderComponent
        FileView {
            property var callback
            property var pathQueue: []
            property string cTitle: ""
            property string cArtist: ""
            property string cNewPath: ""
            blockLoading: true
            preload: true
            onLoaded: {
                var cb = callback
                callback = null
                var data = null
                try {
                    data = JSON.parse(text());
                } catch (e) {
                    data = null;
                }
                if (data && Array.isArray(data.lines)) {
                    // 旧缓存可能带时间轴为 0 的作词/作曲信息；读取时统一去掉
                    data.lines = data.lines.filter(function (line) {
                        return !(line && typeof line.text === "string" && root._isCreditLine(line.text));
                    });
                }
                if (data && cNewPath && path !== cNewPath && root._validLyricsLines(data.lines)) {
                    // 命中的是旧 hash 名缓存：迁移一份到新可读名
                    console.info("[Lyrics] 迁移缓存: " + _cacheDir + "/" + _cacheKey(cTitle, cArtist) + " → 可读名");
                    root.writeToCache(cTitle, cArtist, data.lines, data.source,
                                      typeof data.offset === "number" ? data.offset : 0,
                                      root._cacheIsPlain(data));
                }
                if (cb) cb(data);
                destroy();
            }
            onLoadFailed: {
                var cb = callback;
                var remain = pathQueue;
                callback = null;
                destroy();
                root._readPathQueue(remain, cb, cTitle, cArtist, cNewPath);
            }
        }
    }

    Component {
        id: cacheWriterComponent
        FileView {
            property string cTitle
            property string cArtist
            property var cLines
            property int cSource
            property real cOffset: 0
            property bool cPlain: false

            blockWrites: false
            atomicWrites: true

            Component.onCompleted: {
                setText(JSON.stringify({
                    lines: cLines,
                    source: cSource,
                    cachedAt: new Date().toISOString(),
                    offset: cOffset,
                    plain: cPlain
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
        var requestToken = ++root._fetchToken;

        // 优先级1：自定义API
        if (customApiEnabled && customApiUrl.trim() !== "") {
            // 自定义 API 每次都会重新请求，先从缓存恢复这首歌的手动偏移
            _restoreCachedOffsetAndThen(capturedTitle, capturedArtist, requestToken, function () {
                if (!root._isCurrentRequest(capturedTitle, capturedArtist, requestToken)) return;
                root._fetchFromCustomApi(capturedTitle, capturedArtist, requestToken);
            });
            return;
        }

        // 优先级2：缓存
        if (cachingEnabled) {
            _tryCacheThenFetch(capturedTitle, capturedArtist, requestToken);
        } else {
            cacheStatus = status.cacheDisabled;
            _startFetchFromSources(capturedTitle, capturedArtist, requestToken);
        }
    }
    function _restoreCachedOffsetAndThen(title, artist, token, callback) {
        if (!cachingEnabled) {
            callback();
            return;
        }
        readFromCache(title, artist, function (cached) {
            if (!root._isCurrentRequest(title, artist, token)) return;
            if (cached && typeof cached.offset === "number" && isFinite(cached.offset)) {
                root._suppressOffsetSave = true;
                root.lyricsOffset = cached.offset;
                root._suppressOffsetSave = false;
            }
            callback();
        });
    }
    function _tryCacheThenFetch(title, artist, token) {
        readFromCache(title, artist, function (cached) {
            // 守卫：歌曲或请求代次已变化
            if (!root._isCurrentRequest(title, artist, token)) return;

            if (root._validLyricsLines(cached?.lines)) {
                _applyCachedLyrics(cached, title, artist, token);
                return;
            }

            root.cacheStatus = status.cacheMiss;
            if (!root.builtinSourcesEnabled) {
                root._setFinalNotFound(status.notFound);
                return;
            }
            _startFetchFromSources(title, artist, token);
        });
    }
    function _applyCachedLyrics(cached, title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return;
        if (!root._validLyricsLines(cached?.lines)) return;
        root._suppressOffsetSave = true;
        root.lyricsArePlain = root._cacheIsPlain(cached);
        root.lyricsLines = cached.lines;
        root.lyricStatus = lyricState.synced;
        root.lyricSource = cached.source > 0 ? cached.source : lyricSrc.cache;
        root.cacheStatus = status.cacheHit;
        root.lrclibStatus = status.skippedFound;
        root.neteaseStatus = status.skippedFound;
        root._lastSyncedTrack = title;
        root._lastSyncedArtist = artist;
        // 恢复偏移量
        root.lyricsOffset = (typeof cached.offset === "number" && isFinite(cached.offset))
            ? cached.offset : 0;
        root._suppressOffsetSave = false;
        console.info("[Lyrics] ✓ 缓存: 已加载 \"" + title + "\" 的歌词 ("
                     + cached.lines.length + " 行" + (root.lyricsArePlain ? ", 纯文本" : "") + ")");
    }
    function _startFetchFromSources(title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return;
        if (!root.builtinSourcesEnabled) {
            root._setFinalNotFound(status.notFound);
            return;
        }
        if (neteaseEnabled) {
            _fetchFromNetease(title, artist, token);
        } else {
            neteaseStatus = status.skippedConfig;
            _fetchFromLrclib(title, artist, token);
        }
    }
    function _logSongChange() {
        var durationStr = currentDuration > 0
            ? (Math.floor(currentDuration / 60) + ":" + ("0" + Math.floor(currentDuration % 60)).slice(-2))
            : "未知";
        console.info("[Lyrics] ▶ 歌曲切换: \"" + currentTitle + "\" - " + currentArtist +
                    (currentAlbum ? " [" + currentAlbum + "]" : "") + " (" + durationStr + ")");
    }
    function _redactUrl(url) {
        // 只保留协议和主机名；路径、userinfo、查询参数和片段都可能携带 token
        var match = String(url || "").match(/^(https?:\/\/)([^\/?#\s]*)(.*)$/i);
        if (!match)
            return "<redacted>";
        var authority = match[2];
        var at = authority.lastIndexOf("@");
        var host = at !== -1 ? authority.slice(at + 1) : authority;
        return match[1] + host + "/<redacted>";
    }
    function _redactText(text) {
        // 错误信息偶尔会带完整 URL，统一做脱敏
        return String(text || "").replace(/https?:\/\/[^\s"'<>]+/gi, function (url) {
            return _redactUrl(url);
        });
    }
    function _xhrRequest(url, method, timeoutMs, onSuccess, onError, customHeaders, postData) {
        const MAX_RETRIES = 2;
        const RETRY_DELAY = 3000;

        var requestId = ++root._xhrRequestSeq;
        root._activeXhrRequest = requestId;
        var retriesLeft = MAX_RETRIES;
        var cancelled = false;
        var currentXhr = null;
        var httpMethod = (method || "GET").toUpperCase();
        if (httpMethod !== "GET" && httpMethod !== "POST")
            httpMethod = "GET";

        function _isActive() {
            return !cancelled && root._activeXhrRequest === requestId;
        }
        function _finish() {
            if (root._activeXhrRequest === requestId)
                root._activeXhrRequest = 0;
            xhrTimeoutTimer.stop();
            xhrRetryTimer.stop();
        }
        function _attempt() {
            if (!_isActive()) return;
            currentXhr = new XMLHttpRequest();
            var done = false;

            // 设置超时；ownerId 防止旧请求触发新请求的定时器
            xhrTimeoutTimer.stop();
            xhrTimeoutTimer.ownerId = requestId;
            xhrTimeoutTimer.interval = timeoutMs;
            xhrTimeoutTimer.onTimeout = function () {
                if (xhrTimeoutTimer.ownerId !== requestId || !_isActive() || done)
                    return;
                done = true;
                currentXhr.abort();
                _retry("timeout");
            };
            xhrTimeoutTimer.start();

            // 状态处理
            currentXhr.onreadystatechange = function () {
                if (!_isActive() || currentXhr.readyState !== XMLHttpRequest.DONE || done)
                    return;

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

                _finish();
                onSuccess(currentXhr.responseText, currentXhr.status);
            };

            // 发送请求
            try {
                currentXhr.open(httpMethod, url);

                if (customHeaders) {
                    for (var key in customHeaders) {
                        currentXhr.setRequestHeader(key, customHeaders[key]);
                    }
                } else {
                    currentXhr.setRequestHeader("User-Agent", "DankMaterialShell Lyrics/1.7.4");
                    currentXhr.setRequestHeader("Accept", "application/json");
                }

                if (httpMethod === "POST" && postData) {
                    currentXhr.setRequestHeader("Content-Type", "application/json");
                    currentXhr.send(JSON.stringify(postData));
                } else {
                    currentXhr.send();
                }
            } catch (e) {
                if (done)
                    return;
                done = true;
                _finish();
                var errorText = "请求异常: " + e;
                // 延迟回调，避免调用方还没拿到 cancel 函数就同步启动回退请求
                Qt.callLater(function () {
                    if (!cancelled)
                        onError(errorText);
                });
            }
        }

        function _retry(errMsg) {
            if (!_isActive()) return;

            if (retriesLeft > 0) {
                retriesLeft--;
                console.warn("[Lyrics] 请求失败，重试中 (" + (MAX_RETRIES - retriesLeft) + "/" + MAX_RETRIES + "): " + _redactUrl(url));
                xhrRetryTimer.stop();
                xhrRetryTimer.ownerId = requestId;
                xhrRetryTimer.interval = RETRY_DELAY;
                xhrRetryTimer.onRetry = function () {
                    if (xhrRetryTimer.ownerId !== requestId || !_isActive())
                        return;
                    _attempt();
                };
                xhrRetryTimer.start();
            } else {
                _finish();
                onError(errMsg);
            }
        }

        if (typeof url !== "string" || !/^https?:\/\//i.test(url)) {
            _finish();
            Qt.callLater(function () {
                if (!cancelled)
                    onError("无效的请求地址");
            });
            return function () { cancelled = true; };
        }

        _attempt();

        return function cancel() {
            cancelled = true;
            if (root._activeXhrRequest === requestId)
                root._activeXhrRequest = 0;
            xhrTimeoutTimer.stop();
            xhrRetryTimer.stop();
            if (currentXhr) currentXhr.abort();
        };
    }

    function _xhrGet(url, timeoutMs, onSuccess, onError, customHeaders) {
        return _xhrRequest(url, "GET", timeoutMs, onSuccess, onError, customHeaders, null);
    }
    // 歌词源：lrclib.net

    function _fetchFromLrclib(expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;
        if (!_checkSourceEnabled("lrclib", lrclibEnabled, neteaseEnabled)) return;
        if (_checkAlreadySynced("lrclib")) return;

        lrclibStatus = status.searching;
        console.info("[Lyrics] lrclib: 正在搜索 \"" + expectedTitle + "\"");

        var url = _buildLrclibUrl(expectedTitle, expectedArtist);

        root._cancelActiveFetch = _xhrGet(url, 20000,
            function (responseText, httpStatus) {
                _handleLrclibResponse(responseText, expectedTitle, expectedArtist, token);
            },
            function (errMsg) {
                _handleLrclibError(errMsg, expectedTitle, expectedArtist, token);
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

    function _handleLrclibResponse(responseText, expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _fallbackAfterLrclib(status.error, "空响应", expectedTitle, expectedArtist, token);
            return;
        }

        try {
            var result = JSON.parse(rawData);

            if (result.statusCode === 404 || result.error) {
                _fallbackAfterLrclib(status.notFound, "未找到", expectedTitle, expectedArtist, token);
                return;
            }

            if (result.syncedLyrics
                    && _applyLyricsFromSource(result.syncedLyrics, lyricSrc.lrclib,
                                              expectedTitle, expectedArtist, token))
                return;

            if (result.plainLyrics
                    && _applyPlainLyrics(result.plainLyrics, lyricSrc.lrclib,
                                         expectedTitle, expectedArtist, token))
                return;

            _fallbackAfterLrclib(status.notFound, "无歌词数据", expectedTitle, expectedArtist, token);

        } catch (e) {
            _fallbackAfterLrclib(status.error, "解析失败: " + e, expectedTitle, expectedArtist, token);
        }
    }

    function _handleLrclibError(errMsg, expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;
        console.warn("[Lyrics] lrclib: 请求失败 — " + errMsg);
        _fallbackAfterLrclib(status.error, errMsg, expectedTitle, expectedArtist, token);
    }

    function _fallbackAfterLrclib(statusVal, reason, title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return;
        lrclibStatus = statusVal;
        console.info("[Lyrics] lrclib: " + reason + " - \"" + title + "\"");

        // 仅在网易云尚未尝试过时回退；否则两个源会无限互相重试。
        if (neteaseEnabled && neteaseStatus === status.none) {
            _fetchFromNetease(title, artist, token);
        } else {
            _setFinalNotFound(statusVal);
        }
    }
    // 歌词源：网易云音乐

    function _fetchFromNetease(expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;
        if (!_checkSourceEnabled("netease", neteaseEnabled, false)) {
            _setFinalNotFound(status.notFound);
            return;
        }
        if (_checkAlreadySynced("netease")) return;

        neteaseStatus = status.searching;
        console.info("[Lyrics] 网易云: 搜索 \"" + expectedTitle
                     + (expectedArtist ? " - " + expectedArtist : "") + "\"");

        // 带上歌手搜索并多取几条结果，再在本地做标题/歌手/专辑匹配
        var searchTerm = expectedArtist ? expectedTitle + " " + expectedArtist : expectedTitle;
        var searchUrl = "https://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag=&s="
                      + encodeURIComponent(searchTerm) + "&type=1&offset=0&total=true&limit=10";

        var customHeaders = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0",
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://music.163.com/"
        };

        root._cancelActiveFetch = _xhrRequest(searchUrl, "GET", 15000,
            function (responseText, httpStatus) {
                _handleNeteaseSearchResponse(responseText, expectedTitle, expectedArtist, token);
            },
            function (errMsg) {
                _handleNeteaseError("搜索失败: " + errMsg, expectedTitle, expectedArtist, token);
            },
            customHeaders
        );
    }

    function _handleNeteaseSearchResponse(responseText, expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空搜索响应", expectedTitle, expectedArtist, token);
            return;
        }

        try {
            var result = JSON.parse(rawData);
            var songs = result?.result?.songs;

            if (!Array.isArray(songs) || songs.length === 0) {
                _handleNeteaseError("未找到歌曲", expectedTitle, expectedArtist, token);
                return;
            }

            var matchedSong = _findBestMatch(songs, expectedTitle, expectedArtist, currentAlbum);
            if (!matchedSong) {
                _handleNeteaseError("未找到标题和歌手匹配的歌曲", expectedTitle, expectedArtist, token);
                return;
            }
            var songId = matchedSong.id;
            var songName = matchedSong.name;
            var artistList = matchedSong.artists;
            if (!Array.isArray(artistList) || artistList.length === 0)
                artistList = matchedSong.ar;
            if (!Array.isArray(artistList))
                artistList = [];
            var artistName = artistList
                .map(function (a) { return (a && a.name) || ""; })
                .filter(function (n) { return n !== ""; })
                .join(" / ") || "未知";

            if (songId === undefined || songId === null || songId === "") {
                _handleNeteaseError("歌曲 ID 无效", expectedTitle, expectedArtist, token);
                return;
            }

            console.info("[Lyrics] 网易云: 匹配 \"" + songName + "\" - " + artistName);

            _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, songName, artistName, token);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle, expectedArtist, token);
        }
    }

    function _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, matchedName, matchedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;

        // Query NetEase directly instead of routing the song id through a third-party proxy.
        var lyricUrl = "https://music.163.com/api/song/lyric?id=" + encodeURIComponent(songId)
                     + "&lv=1&kv=1&tv=-1";

        var customHeaders = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0",
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://music.163.com/"
        };

        root._cancelActiveFetch = _xhrGet(lyricUrl, 15000,
            function (responseText, httpStatus) {
                _handleNeteaseLyricResponse(responseText, expectedTitle, expectedArtist,
                                            matchedName, matchedArtist, token);
            },
            function (errMsg) {
                _handleNeteaseError("歌词请求失败: " + errMsg, expectedTitle, expectedArtist, token);
            },
            customHeaders
        );
    }

    function _handleNeteaseLyricResponse(responseText, expectedTitle, expectedArtist,
                                         matchedName, matchedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空搜索响应", expectedTitle, expectedArtist, token);
            return;
        }

        try {
            var result = JSON.parse(rawData);

            var lyricText = result.lrc?.lyric || result.lyric || "";
            if (typeof lyricText !== "string" || lyricText.trim() === "") {
                _handleNeteaseError("该歌曲无歌词", expectedTitle, expectedArtist, token);
                return;
            }

            var lines = parseLrc(lyricText);
            if (lines.length > 0) {
                _applyLyricsLines(lines, lyricSrc.netease, expectedTitle, expectedArtist, false, token);
                console.info("[Lyrics] 网易云: 匹配 \"" + matchedName + "\" - " + matchedArtist);
                return;
            }

            if (_applyPlainLyrics(lyricText, lyricSrc.netease, expectedTitle, expectedArtist, token)) {
                console.info("[Lyrics] 网易云: 匹配 \"" + matchedName + "\" - " + matchedArtist + " (纯文本)");
                return;
            }

            _handleNeteaseError("LRC解析失败", expectedTitle, expectedArtist, token);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle, expectedArtist, token);
        }
    }

    function _handleNeteaseError(reason, title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return;
        neteaseStatus = status.error;
        console.warn("[Lyrics] 网易云: " + reason + " - \"" + title + "\"");

        // 网易云失败时，回退到 lrclib。只有在该源尚未尝试过时才继续，
        // 否则两个源失败后会互相回调，形成无限请求循环。
        if (lrclibEnabled && lrclibStatus === status.none) {
            console.info("[Lyrics] 网易云失败，尝试 lrclib...");
            _fetchFromLrclib(title, artist, token);
        } else {
            _setFinalNotFound(status.error);
        }
    }
    // 歌词源：自定义 API

    function _fetchFromCustomApi(expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;

        var apiBase = customApiUrl.trim();
        if (!/^https?:\/\//i.test(apiBase)) {
            _fallbackToBuiltin("URL 无效", expectedTitle, expectedArtist, token);
            return;
        }

        console.info("[Lyrics] 自定义API: 获取 \"" + expectedTitle + "\"");

        var url = apiBase
            .replace(/{title}/g, encodeURIComponent(expectedTitle))
            .replace(/{artist}/g, encodeURIComponent(expectedArtist))
            .replace(/{album}/g, encodeURIComponent(currentAlbum || ""));
        var method = (customApiMethod || "GET").toUpperCase();
        if (method !== "GET" && method !== "POST")
            method = "GET";

        var postData = method === "POST" ? {
            title: expectedTitle,
            artist: expectedArtist,
            album: currentAlbum || ""
        } : null;

        root._cancelActiveFetch = _xhrRequest(url, method, 20000,
            function (responseText, httpStatus) {
                _handleCustomApiResponse(responseText, expectedTitle, expectedArtist, token);
            },
            function (errMsg) {
                if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;
                console.warn("[Lyrics] 自定义API: 失败 - " + _redactText(errMsg));
                _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist, token);
            },
            null,
            postData
        );
    }

    function _handleCustomApiResponse(responseText, expectedTitle, expectedArtist, token) {
        if (!root._isCurrentRequest(expectedTitle, expectedArtist, token)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _fallbackToBuiltin("空歌词响应", expectedTitle, expectedArtist, token);
            return;
        }

        try {
            var result = JSON.parse(rawData);
            var lyricText = result.lyrics || result.lyric || result.lrc || result.content || result.data;

            if (!lyricText || typeof lyricText !== "string" || lyricText.trim() === "") {
                _fallbackToBuiltin("响应中无歌词", expectedTitle, expectedArtist, token);
                return;
            }

            if (_applyLyricsFromSource(lyricText, lyricSrc.custom, expectedTitle, expectedArtist, token))
                return;
            if (_applyPlainLyrics(lyricText, lyricSrc.custom, expectedTitle, expectedArtist, token))
                return;

            _fallbackToBuiltin("解析失败", expectedTitle, expectedArtist, token);

        } catch (e) {
            _fallbackToBuiltin("解析失败: " + e, expectedTitle, expectedArtist, token);
        }
    }

    function _fallbackToBuiltin(reason, title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return;
        console.warn("[Lyrics] 自定义API: " + reason + "，回退到内置源");
        _fetchFromCacheOrBuiltin(title, artist, token);
    }

    function _fetchFromCacheOrBuiltin(title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return;
        if (cachingEnabled) {
            readFromCache(title, artist, function (cached) {
                if (!root._isCurrentRequest(title, artist, token)) return;
                if (root._validLyricsLines(cached?.lines)) {
                    _applyCachedLyrics(cached, title, artist, token);
                    return;
                }
                root.cacheStatus = status.cacheMiss;
                if (!root.builtinSourcesEnabled) {
                    root._setFinalNotFound(status.notFound);
                    return;
                }
                // 缓存未命中后按正常顺序继续（网易云 → lrclib），
                // 不能直接跳到 lrclib 而跳过网易云。
                _startFetchFromSources(title, artist, token);
            });
        } else {
            cacheStatus = status.cacheDisabled;
            if (!root.builtinSourcesEnabled) {
                root._setFinalNotFound(status.notFound);
                return;
            }
            _startFetchFromSources(title, artist, token);
        }
    }
    // 歌词处理辅助函数

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
        // 既检查已发起的请求，也检查当前 MPRIS 曲目，避免换歌防抖期间
        // 旧请求的回调把上一首歌词写到新曲目上。
        return title === root._lastFetchedTrack
            && artist === root._lastFetchedArtist
            && title === root.currentTitle
            && artist === root.currentArtist;
    }
    function _isCurrentRequest(title, artist, token) {
        // 同一首歌可能因清缓存/重新搜索而发起多次请求，必须同时校验代次。
        return token === root._fetchToken && root._isCurrentTrack(title, artist);
    }
    function _findBestMatch(songs, expectedTitle, expectedArtist, expectedAlbum) {
        if (!Array.isArray(songs) || songs.length === 0)
            return null;
        function normalize(str) {
            if (!str) return "";
            return String(str).toLowerCase()
                .replace(/[\(（\[【].*?[\)）\]】]/g, "")
                .replace(/[\s\-_/.,，。·'’"“”]+/g, "");
        }
        function songArtistText(song) {
            var list = song.artists;
            if (!Array.isArray(list) || list.length === 0)
                list = song.ar || [];
            if (typeof list === "string")
                return list;
            if (!Array.isArray(list))
                return "";
            var names = [];
            for (var i = 0; i < list.length; i++) {
                var a = list[i];
                var n = a && (a.name || a);
                if (n) names.push(String(n));
            }
            return names.join(" / ");
        }
        function artistMatches(expected, actual) {
            var e = normalize(expected);
            var a = normalize(actual);
            if (!e) return true;
            // 结果没有歌手信息时只能依赖标题；有歌手信息则必须匹配
            if (!a) return true;
            return a === e || a.indexOf(e) !== -1 || e.indexOf(a) !== -1;
        }

        var nTitle = normalize(expectedTitle);
        var nArtist = normalize(expectedArtist);
        var nAlbum = normalize(expectedAlbum);
        var best = null;
        var bestScore = -1;

        for (var i = 0; i < songs.length; i++) {
            var song = songs[i];
            if (!song || typeof song !== "object")
                continue;
            var songName = normalize(song.name);
            var titleExact = songName !== "" && songName === nTitle;
            var titleFuzzy = titleExact || (nTitle !== "" && songName !== ""
                && (songName.indexOf(nTitle) !== -1 || nTitle.indexOf(songName) !== -1));
            if (!titleFuzzy)
                continue;

            var actualArtist = songArtistText(song);
            if (!artistMatches(expectedArtist, actualArtist))
                continue;

            var actualAlbum = normalize(song.album?.name || song.album);
            var albumExact = nAlbum !== "" && actualAlbum === nAlbum;

            var score = titleExact ? 50 : 20;
            if (nArtist && actualArtist && artistMatches(expectedArtist, actualArtist))
                score += 30;
            if (albumExact)
                score += 20;
            if (titleExact && nArtist && actualArtist)
                score += 20;

            // 时长接近时优先，避免同名不同版本
            if (root.currentDuration > 0 && song.duration > 0) {
                var diff = Math.abs(song.duration / 1000 - root.currentDuration);
                if (diff <= 3) score += 15;
                else if (diff > 30) score -= 10;
            }

            if (score > bestScore) {
                best = song;
                bestScore = score;
            }
        }

        if (best) {
            console.info("[Lyrics] 网易云: 匹配 \"" + best.name + "\" - "
                         + songArtistText(best) + (bestScore >= 80 ? " (精确)" : ""));
        } else {
            console.info("[Lyrics] 网易云: 没有标题/歌手同时匹配的结果");
        }
        return best;
    }

    function _isLrcMetadataLine(text) {
        return /^\s*\[[a-zA-Z#]+:.*\]\s*$/.test(text || "");
    }

    function _isCreditLine(text) {
        if (!text) return false;
        var s = String(text).trim();
        if (!s) return false;
        // 只过滤带冒号的制作信息，避免误伤以“曲终”“词不达意”等开头的正常歌词
        if (/^(作词|作曲|编曲|制作人|制作|出品|发行|监制|混音|母带|录音|和声|演唱|原唱|词|曲)\s*[:：]/.test(s))
            return true;
        return /^(lyrics?|lyricist|composer|composed|arranger|arranged|producer|mixed|mastered|written|music)\b(?:\s+by)?\s*[:：]/i.test(s);
    }

    function _plainTextToLines(plainText) {
        if (!plainText || typeof plainText !== "string")
            return [];
        return plainText
            .split(/\r?\n/)
            .map(function(line) { return { time: 0, text: line.trim() }; })
            .filter(function(l) {
                return l.text !== ""
                    && !_isLrcMetadataLine(l.text)
                    && !_isInstrumentalMarker(l.text)
                    && !_isCreditLine(l.text);
            });
    }

    function _applyLyricsFromSource(lrcText, source, title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return false;
        var lines = parseLrc(lrcText);
        if (lines.length === 0) return false;
        _applyLyricsLines(lines, source, title, artist, false, token);
        return true;
    }

    function _applyPlainLyrics(plainText, source, title, artist, token) {
        if (!root._isCurrentRequest(title, artist, token)) return false;
        var lines = _plainTextToLines(plainText);
        if (lines.length === 0) return false;
        _applyLyricsLines(lines, source, title, artist, true, token);
        return true;
    }

    function _applyLyricsLines(lines, source, title, artist, isPlain, token) {
        if (!root._isCurrentRequest(title, artist, token)) return false;
        if (!root._validLyricsLines(lines)) return false;

        root.lyricsArePlain = isPlain === true;
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
                        source === lyricSrc.custom ? "自定义API" :
                        source === lyricSrc.embedded ? "内嵌歌词" : "未知";

        console.info("[Lyrics] ✓ " + sourceName + ": 已找到歌词 (" + lines.length + " 行"
                     + (root.lyricsArePlain ? ", 纯文本" : "") + ") - \"" + title + "\"");

        if (cachingEnabled) {
            writeToCache(title, artist, lines, source, root.lyricsOffset, root.lyricsArePlain);
        }
        return true;
    }

    // -------------------------------------------------------------------------
    // LRC parser
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
        // 独立的 OST 缩写，避免把 "ghost" 之类误判为纯音乐；括号和中文也能作为边界
        if (/(^|[^a-z0-9])ost([^a-z0-9]|$)/.test(hay))
            return true;
        return false;
    }

    function parseLrc(lrcText) {
        var result = [];
        if (!lrcText || typeof lrcText !== "string")
            return result;

        // 支持 [mm:ss]、[mm:ss.x]、[mm:ss.xx]、[mm:ss.xxx] 和 [mm:ss:xx]
        var tagRegex = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
        var rawLines = String(lrcText).split(/\r?\n/);

        for (var li = 0; li < rawLines.length; li++) {
            var line = rawLines[li].trim();
            if (!line)
                continue;

            var matches = [];
            var match;
            tagRegex.lastIndex = 0;
            while ((match = tagRegex.exec(line)) !== null)
                matches.push(match);
            if (matches.length === 0)
                continue;

            var text = line.replace(/\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g, "").trim();
            if (!text || _isInstrumentalMarker(text) || _isCreditLine(text))
                continue;

            // 同一行可以带多个时间戳（如副歌复用），每个都要生成条目
            for (var mi = 0; mi < matches.length; mi++) {
                var m = matches[mi];
                var fraction = m[3] || "";
                var millis = 0;
                if (fraction.length === 1)
                    millis = parseInt(fraction, 10) * 100;
                else if (fraction.length === 2)
                    millis = parseInt(fraction, 10) * 10;
                else if (fraction.length === 3)
                    millis = parseInt(fraction, 10);

                result.push({
                    time: parseInt(m[1], 10) * 60 + parseInt(m[2], 10) + millis / 1000,
                    text: text,
                    // 保留源顺序，避免同一时间戳的原文/翻译被不稳定排序打乱
                    _order: result.length
                });
            }
        }

        result.sort(function (a, b) {
            return a.time - b.time || a._order - b._order;
        });
        for (var ri = 0; ri < result.length; ri++)
            delete result[ri]._order;
        return result;
    }

    // -------------------------------------------------------------------------
    // Position tracking for synced lyrics
    // -------------------------------------------------------------------------

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
    function _resetLyricsForTrack() {
        currentLineIndex = -1;
        _lastRealPos = -1;
        _lastPosStamp = 0;
        if (lyricsArePlain) {
            // 纯文本没有时间轴，换曲时先清空，避免短暂显示上一首的正文
            offsetSaveTimer.stop();
            lyricsArePlain = false;
            lyricsLines = [];
        }
        rebuildDisplayLines();
    }

    Timer {
        id: positionTimer
        interval: 200
        running: isPlaying && lyricsLines.length > 0 && !lyricsArePlain
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

    function _isHeaderLine(t) {
        if (!t || !currentTitle || !currentArtist)
            return false;
        return t.includes(currentTitle) && t.includes(currentArtist);
    }

    function rebuildDisplayLines() {
        var mode = lyricLanguage;
        if (lyricsLines.length === 0) {
            displayLines = [];
            _syncDisplayIndex();
            _rebuildCurrentPair();
            return;
        }
        if (root.lyricsArePlain) {
            // 纯文本没有时间轴：保留全部可显示行，固定显示首行；居中分栏显示前两行
            var plainOut = [];
            for (var p = 0; p < lyricsLines.length; p++) {
                var plainText = lyricsLines[p].text || "";
                if (!plainText || _isBlocked(plainText) || _isHeaderLine(plainText))
                    continue;
                plainOut.push({ time: 0, text: plainText, src: p });
            }
            displayLines = plainOut;
            var firstSrc = plainOut.length > 0 ? plainOut[0].src : -1;
            if (currentLineIndex !== firstSrc)
                currentLineIndex = firstSrc;
            _syncDisplayIndex();
            _rebuildCurrentPair();
            return;
        }
        var out = [];
        var i = 0;
        while (i < lyricsLines.length) {
            if (_isBlocked(lyricsLines[i].text) || _isHeaderLine(lyricsLines[i].text)) {
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

    function _rebuildCurrentPair() {
        if (root.lyricsArePlain) {
            if (displayLines.length === 0) {
                currentPair = null;
                return;
            }
            currentPair = {
                orig: displayLines[0].text || "",
                trans: displayLines.length > 1 ? (displayLines[1].text || "") : ""
            };
            return;
        }
        if (lyricsLines.length === 0 || currentLineIndex < 0
                || currentLineIndex >= lyricsLines.length) {
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
                label: root.isEnglish ? "Found - Lyrics" : "已找到 - 歌词"
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

            readonly property bool introPhase: root.hasPlayer && root.isPlaying
                && !root.lyricsArePlain
                && root.displayLines.length > 0
                && root._lastRealPos < (root.displayLines[0]?.time ?? 0)

            readonly property bool instrumentalPhase: root.hasPlayer && root.isPlaying && !root.lyricsLoading
                && (root.lyricsLines.length === 0 ||
                    (root.currentLineIndex >= 0
                     && root.lyricsLines[root.currentLineIndex]
                     && root._isInstrumentalMarker(root.lyricsLines[root.currentLineIndex].text)))

            readonly property bool blockedPhase: root.hasPlayer && root.isPlaying && !root.lyricsLoading
                && root.currentLineIndex >= 0
                && root.lyricsLines[root.currentLineIndex]
                && root._isBlocked(root.lyricsLines[root.currentLineIndex].text)

            // 组件上滚轮调整播放器音量（不拦截点击）
            MouseArea {
                id: wheelVolumeArea
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onWheel: (wheel) => {
                    if (!root.scrollWheelVolume || !root.activePlayer) return
                    if (root.activePlayer.volumeSupported === false) return
                    var step = 0
                    if (wheel.pixelDelta && wheel.pixelDelta.y !== 0) {
                        step = wheel.pixelDelta.y * 0.01
                    } else if (wheel.angleDelta && wheel.angleDelta.y !== 0) {
                        step = (wheel.angleDelta.y / 120) * 0.05
                    }
                    if (step === 0) return
                    var cur = root.activePlayer.volume || 0
                    var next = Math.min(1, Math.max(0, cur + step))
                    root.activePlayer.volume = Math.round(next * 100) / 100
                    wheel.accepted = true
                }
            }

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
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceContainerHighest
                clip: true

                Timer {
                    id: artBounceTimer
                    interval: 0
                    onTriggered: {
                        var c = artLoader.sourceComponent;
                        artLoader.sourceComponent = null;
                        artLoader.sourceComponent = c;
                    }
                }

                Connections {
                    target: root
                    function onCurrentTitleChanged() {
                        artBounceTimer.restart();
                    }
                }

                Loader {
                    id: artLoader
                    anchors.fill: parent
                    sourceComponent: artSourceComponent
                }

                Component {
                    id: artSourceComponent
                    DankCircularImage {
                        anchors.fill: parent
                        imageSource: root.albumArtUrl
                        fallbackIcon: "music_note"
                    }
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
                    spacing: Theme.spacingS
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
                    color: !root.idleClock && root.usePillAccent ? MediaAccentService.accent : Theme.widgetTextColor
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
                        if (hPillRoot.infoPaused || hPillRoot.introPhase || hPillRoot.instrumentalPhase || hPillRoot.blockedPhase)
                            return root.currentTitle || "";
                        if (hPillRoot.dualMode)
                            return root.currentPair?.orig ?? "";
                        return root.pillSingleText();
                    }
                    font.pixelSize: hPillRoot.fontSize
                    font.family: Theme.fontFamily
                    color: !root.idleClock && root.usePillAccent ? MediaAccentService.accent : Theme.widgetTextColor
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
                        if (hPillRoot.infoPaused || hPillRoot.introPhase || hPillRoot.instrumentalPhase || hPillRoot.blockedPhase)
                            return root.currentArtist || "";
                        if (hPillRoot.dualMode) {
                            var t = root.currentPair?.trans ?? "";
                            return t || (root.currentPair?.orig ?? "");
                        }
                        return "";
                    }
                    font.pixelSize: hPillRoot.fontSize
                    font.family: Theme.fontFamily
                    color: !root.idleClock && root.usePillAccent ? MediaAccentService.accent : Theme.widgetTextColor
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
                color: root.lyricsLines.length > 0 && root.usePillAccent ? MediaAccentService.accent : Theme.widgetTextColor
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
        spacing: Theme.spacingS

        // 纯音乐识别指示器（无歌词且标题/歌手带纯音乐标记时覆盖各源状态）
        Rectangle {
            visible: root.pureInstrumental
            width: 96
            height: 28
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.tertiary, 0.25)
            border.color: Theme.tertiary
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: "music_off"
                    size: Theme.iconSizeSmall
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isEnglish ? "Instrumental" : "纯音乐"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.tertiary
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // 网易云指示器 - 带图标的圆角矩形（优先显示）
        Rectangle {
            id: neteaseChip
            visible: !root.pureInstrumental
            width: 64
            height: 28
            radius: Theme.cornerRadius
            color: Theme.withAlpha(root._apiStatusColor(root.neteaseStatus), 0.25)
            border.color: root._apiStatusColor(root.neteaseStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                name: "cloud"
                size: Theme.iconSizeSmall
                color: root._apiStatusColor(root.neteaseStatus)
                anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isEnglish ? "NetEase" : "网易"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root._apiStatusColor(root.neteaseStatus)
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: neteaseMouse
                anchors.fill: parent
                hoverEnabled: true
            }

            LyricsTooltipHost {
                text: root._chipMeta[root.neteaseStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲")
                target: neteaseChip
                hoverArea: neteaseMouse
            }
        }

        // lrclib 指示器 - 带图标的圆角矩形
        Rectangle {
            id: lrclibChip
            visible: !root.pureInstrumental
            width: 64
            height: 28
            radius: Theme.cornerRadius
            color: Theme.withAlpha(root._apiStatusColor(root.lrclibStatus), 0.25)
            border.color: root._apiStatusColor(root.lrclibStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                name: "library_music"
                size: Theme.iconSizeSmall
                color: root._apiStatusColor(root.lrclibStatus)
                anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "LRC"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root._apiStatusColor(root.lrclibStatus)
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: lrclibMouse
                anchors.fill: parent
                hoverEnabled: true
            }

            LyricsTooltipHost {
                text: root._chipMeta[root.lrclibStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲")
                target: lrclibChip
                hoverArea: lrclibMouse
            }
        }

        // 缓存指示器 - 带图标的圆角矩形
        Rectangle {
            id: cacheChip
            width: 64
            height: 28
            radius: Theme.cornerRadius
            color: Theme.withAlpha(root._apiStatusColor(root.cacheStatus), 0.25)
            border.color: root._apiStatusColor(root.cacheStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                name: "storage"
                size: Theme.iconSizeSmall
                color: root._apiStatusColor(root.cacheStatus)
                anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isEnglish ? "Cache" : "缓存"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root._apiStatusColor(root.cacheStatus)
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

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

            LyricsTooltipHost {
                text: root.cacheStatus === status.cacheHit ?
                    root.isEnglish ? "Click to clear cache and re-search" : "点击清除缓存并重新搜索" : (root._chipMeta[root.cacheStatus]?.label ?? (root.isEnglish ? "Idle" : "空闲"))
                target: cacheChip
                hoverArea: cacheMouse
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
                // 黑胶唱片专辑封面
                // 设计说明：
                // - 尺寸：200x200，保持原有大小
                // - 样式：深灰色带纹理的黑胶唱片效果
                // - 中心：80x80的专辑封面
                // - 位置：卡片右上角，部分超出边界
                // - 旋转动画：20秒/圈，更慢更优雅
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

                    // 黑胶唱片主体
                    Rectangle {
                        id: vinylRecord
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.surfaceContainerHighest

                        // 唱片纹理（同心圆纹路）
                        Canvas {
                            anchors.fill: parent
                            property color grooveColor: Theme.outlineVariant
                            onGrooveColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d");
                                var centerX = width / 2;
                                var centerY = height / 2;

                                for (var i = 2; i < 8; i++) {
                                    ctx.beginPath();
                                    ctx.arc(centerX, centerY, 45 + i * 10, 0, 2 * Math.PI);
                                    ctx.strokeStyle = grooveColor;
                                    ctx.lineWidth = 1;
                                    ctx.stroke();
                                }
                            }
                        }

                        // 中心专辑封面容器
                        Rectangle {
                            width: 130
                            height: 130
                            radius: width / 2
                            anchors.centerIn: parent
                            color: Theme.surfaceContainerHigh
                            clip: true

                            Timer {
                                id: popArtBounceTimer
                                interval: 0
                                onTriggered: {
                                    var c = popArtLoader.sourceComponent;
                                    popArtLoader.sourceComponent = null;
                                    popArtLoader.sourceComponent = c;
                                }
                            }

                            Connections {
                                target: root
                                function onCurrentTitleChanged() {
                                    popArtBounceTimer.restart();
                                }
                            }

                            // 专辑封面
                            Loader {
                                id: popArtLoader
                                anchors.fill: parent
                                sourceComponent: popArtSourceComponent
                            }

                            Component {
                                id: popArtSourceComponent
                                DankCircularImage {
                                    anchors.fill: parent
                                    imageSource: root.albumArtUrl
                                    fallbackIcon: "music_note"
                                }
                            }
                        }

                        // 高光效果（增加立体感）
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.surfaceText, 0.08) }
                                GradientStop { position: 0.3; color: Theme.withAlpha(Theme.surfaceText, 0.0) }
                                GradientStop { position: 0.7; color: Theme.withAlpha(Theme.surfaceText, 0.0) }
                                GradientStop { position: 1.0; color: Theme.withAlpha(Theme.shadowStrong, 0.10) }
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
                            spacing: Theme.spacingXS
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
                            spacing: Theme.spacingXS
                            visible: root.activePlayer && root.currentDuration > 0
                        // DMS Wave Progress (M3WaveProgress)
                        // 与 DMS 自带媒体面板一致的动态波浪进度条：
                        // - 播放时正弦波浪随 FrameAnimation 逐帧流动
                        // - 已播放部分用 accent 色填充，未播放为半透明轨道
                        // - 播放头为圆头 pill，拖动时实时预览，松手才 seek
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

                            Timer {
                                id: progressPollTimer
                                interval: 100
                                running: root.activePlayer !== null
                                repeat: true
                                onTriggered: {
                                    root._forceUpdate = !root._forceUpdate;
                                    if (pvSliderBox.visible && !pvSlider.isDragging && root.activePlayer)
                                        pvSlider.value = Math.round((root.activePlayer.volume || 0) * 100);
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

                            // Volume slider - 显示并调整播放器音量
                            Item {
                                id: pvSliderBox
                                width: parent.width
                                height: 48
                                visible: root.activePlayer && root.activePlayer.volumeSupported !== false

                                DankSlider {
                                    id: pvSlider
                                    anchors.fill: parent
                                    minimum: 0
                                    maximum: 100
                                    step: 1
                                    showValue: false
                                    leftIcon: "volume_down"
                                    rightIcon: "volume_up"
                                    trackColor: root._cardAccentTrack
                                    onSliderValueChanged: (v) => {
                                        if (root.activePlayer)
                                            root.activePlayer.volume = v / 100;
                                    }
                                }

                                function _syncFromPlayer() {
                                    pvSlider.value = root.activePlayer
                                        ? Math.round((root.activePlayer.volume || 0) * 100)
                                        : 0;
                                }

                                Component.onCompleted: _syncFromPlayer()
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
                                        radius: width / 2
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

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: scanLibMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "library_music"; size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                            }
                            LyricsTooltipHost {
                                text: root.scanLibRunning
                                    ? (root.isEnglish ? "Importing..." : "导入中...")
                                    : (root.isEnglish ? "Import Lyrics" : "导入缓存")
                                target: scanLibMA
                                hoverArea: scanLibMA
                            }
                        }

                        MouseArea {
                            id: openCacheMA
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                root._ensureCacheDir()
                                Quickshell.execDetached(["gio", "open", root._cacheDir])
                            }
                            cursorShape: Qt.PointingHandCursor

                            Rectangle {
                                anchors.fill: parent; radius: Theme.cornerRadius
                                color: openCacheMA.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.centerIn: parent; name: "folder_open"; size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                            }
                            LyricsTooltipHost {
                                text: root.isEnglish ? "Open Lyrics Cache Folder" : "打开歌词缓存目录"
                                target: openCacheMA
                                hoverArea: openCacheMA
                            }
                        }

                        StyledText {
                            text: root.currentTitle ? root._cacheKey(root.currentTitle, root.currentArtist || "") : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: "monospace"
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideMiddle
                            width: Math.min(implicitWidth, 220)
                            visible: text !== ""
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
                radius: width / 2
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
                radius: height / 2
                color: Theme.withAlpha(root.chipColor(sourceCard.sourceStatus), 0.15)

                Row {
                    id: statusChipContent
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: root.chipIcon(sourceCard.sourceStatus)
                        size: Theme.iconSizeSmall
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
                radius: height / 2
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

    // Local wrapper around DankTooltipV2. DMS 1.6.x does not ship
    // DankTooltipHost yet, so keep the hover/delay handling here instead of
    // depending on a component that is only available on newer builds.
    component LyricsTooltipHost: Item {
        id: tooltipHost

        property var text: null
        property Item target: null
        property var hoverArea: null
        property string side: "bottom"

        readonly property bool hovered: hoverArea ? hoverArea.containsMouse === true : false

        visible: false
        width: 0
        height: 0

        function present() {
            if (!tooltip || !tooltipHost.text || !tooltipHost.target?.visible)
                return;
            tooltip.show(String(tooltipHost.text), tooltipHost.target, 0, 0, tooltipHost.side);
        }

        function dismiss() {
            if (tooltip)
                tooltip.hide();
        }

        onHoveredChanged: {
            if (hovered) {
                delayTimer.restart();
            } else {
                delayTimer.stop();
                dismiss();
            }
        }

        onTextChanged: {
            if (!text) {
                dismiss();
                return;
            }
            if (hovered) {
                if (delayTimer.running)
                    delayTimer.restart();
                else
                    present();
            }
        }

        onTargetChanged: {
            if (!target?.visible) {
                dismiss();
                return;
            }
            if (hovered && !delayTimer.running)
                present();
        }

        onVisibleChanged: {
            if (!visible) {
                delayTimer.stop();
                dismiss();
            }
        }

        Timer {
            id: delayTimer
            interval: 500
            onTriggered: tooltipHost.present()
        }

        DankTooltipV2 {
            id: tooltip
        }
    }

}
