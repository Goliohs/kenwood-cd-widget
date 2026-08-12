pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string _script: Quickshell.shellDir + "/scripts/cd-player.sh"

    property string themeColor: "amber"

    readonly property color colLcdAmber:    "#FFBF00"
    readonly property color colLcdWhite:   "#FFFFFF"
    readonly property color colLcdCyan:    "#00FFFF"
    readonly property color colLcdActive:  themeColor === "white" ? colLcdWhite : (themeColor === "cyan" ? colLcdCyan : colLcdAmber)

    readonly property color colLcdAmberDim: "#3a2a05"
    readonly property color colLcdWhiteDim: "#2a2a2a"
    readonly property color colLcdCyanDim:  "#003a3a"
    readonly property color colLcdDim:      themeColor === "white" ? colLcdWhiteDim : (themeColor === "cyan" ? colLcdCyanDim : colLcdAmberDim)

    readonly property color colLcdAmberBg:  "#0f0a00"
    readonly property color colLcdWhiteBg:  "#1a1a1a"
    readonly property color colLcdCyanBg:   "#001a1a"
    readonly property color colLcdBg:       themeColor === "white" ? colLcdWhiteBg : (themeColor === "cyan" ? colLcdCyanBg : colLcdAmberBg)

    readonly property color colLcdAmberSeg: "#FFBF00"
    readonly property color colLcdWhiteSeg: "#FFFFFF"
    readonly property color colLcdCyanSeg:  "#00FFFF"
    readonly property color colLcdSeg:      themeColor === "white" ? colLcdWhiteSeg : (themeColor === "cyan" ? colLcdCyanSeg : colLcdAmberSeg)

    readonly property color colLcdAmberGhost: "#1f1505"
    readonly property color colLcdWhiteGhost:  "#1a1a1a"
    readonly property color colLcdCyanGhost:   "#001515"
    readonly property color colLcdGhost:       themeColor === "white" ? colLcdWhiteGhost : (themeColor === "cyan" ? colLcdCyanGhost : colLcdAmberGhost)

    readonly property color colPanel:       "#1A1A1A"
    readonly property color colPianoBlack:  "#0a0a0a"
    readonly property color colChrome:      "#a8a8a8"
    readonly property color colChromeEdge:  "#5a5a5a"
    readonly property color colBtnFace:     "#1f1f1f"
    readonly property color colBtnEdge:     "#0a0a0a"
    readonly property color colBtnIcon:     "#cfcfcf"
    readonly property color colBg:          "#000000"

    readonly property string fontSegment7: "DSEG7 Classic"
    readonly property string fontSegment14: "DSEG14 Classic"
    readonly property string fontMono: "JetBrains Mono"

    function cycleTheme() {
        if (themeColor === "amber") themeColor = "white"
        else if (themeColor === "white") themeColor = "cyan"
        else themeColor = "amber"
    }



    property string cdState: "no-cd"
    property int trackNum: 0
    property int trackCount: 0
    property string state: "stopped"
    property int pos: 0
    property int total: 0
    property var tracks: []
    property string songTitle: ""
    property string songArtist: ""
    property string songAlbum: ""

    signal cdInserted
    signal cdRemoved
    signal trackChanged(int n)
    signal playStateChanged(string newState)

    property string _statusBuf: ""
    property string _trackBuf: ""

    function refresh() {
        _statusBuf = ""
        statusProc.running = true
    }

    function refreshTrackList() {
        _trackBuf = ""
        trackProc.running = true
    }

    function _runCmd(subcmd) {
        cmdProc.command = ["bash", _script, subcmd]
        cmdProc.running = true
    }

    function launch()  { _runCmd("launch"); refresh() }
    function close()   { _runCmd("close");  refresh() }
    function toggle()  { _runCmd("toggle"); refresh() }
    function next()    { _runCmd("next");   refresh() }
    function prev()    { _runCmd("prev");   refresh() }
    function stop()    { _runCmd("stop");   refresh() }
    function eject()   { _runCmd("eject");  refresh() }

    function _formatTime(sec) {
        if (sec < 0 || isNaN(sec)) return "--:--"
        var m = Math.floor(sec / 60)
        var s = Math.floor(sec % 60)
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    readonly property string posStr: _formatTime(pos)
    readonly property string totalStr: _formatTime(total)

    readonly property string displayLine: {
        if (cdState !== "audio-cd") return "NO DISC"
        if (songArtist.length > 0 && songTitle.length > 0)
            return songArtist + " - " + songTitle
        if (songTitle.length > 0) return songTitle
        if (trackNum > 0) return "TRACK " + trackNum
        return "AUDIO CD"
    }

    readonly property string clockStr: {
        var now = new Date()
        var h = now.getHours()
        var m = now.getMinutes()
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }

    property var _clockTick: new Date()

    function _tickClock() { root._clockTick = new Date() }

    Process {
        id: statusProc
        command: ["bash", _script, "state"]
        stdout: SplitParser {
            onRead: data => root._statusBuf += data + "\n"
        }
        onRunningChanged: {
            if (!running && root._statusBuf.length > 0) {
                var prevState = root.state
                var prevCd = root.cdState
                var prevTrack = root.trackNum
                try {
                    var obj = JSON.parse(root._statusBuf.trim().split("\n").filter(function(l){return l.startsWith("{")})[0])
                    root.cdState = obj.cdState || "no-cd"
                    root.trackNum = parseInt(obj.trackNum) || 0
                    root.state = obj.state || "stopped"
                    root.pos = parseInt(obj.pos) || 0
                    root.total = parseInt(obj.total) || 0
                    root.songTitle = obj.title || ""
                    root.songArtist = obj.artist || ""
                    root.songAlbum = obj.album || ""
                } catch (e) { /* keep last */ }
                if (root.cdState !== prevCd) {
                    if (root.cdState === "audio-cd") root.cdInserted()
                    else root.cdRemoved()
                }
                if (root.trackNum !== prevTrack) root.trackChanged(root.trackNum)
                if (root.state !== prevState) root.playStateChanged(root.state)
                root._statusBuf = ""
            }
        }
    }

    Process {
        id: trackProc
        command: ["bash", _script, "list"]
        stdout: SplitParser {
            onRead: data => root._trackBuf += data + "\n"
        }
        onRunningChanged: {
            if (!running && root._trackBuf.length > 0) {
                var items = []
                var lines = root._trackBuf.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line.startsWith("{")) {
                        try { items.push(JSON.parse(line)) } catch (e) { }
                    }
                }
                root.trackCount = items.length
                root.tracks = items
                root._trackBuf = ""
            }
        }
    }

    Process {
        id: cmdProc
        command: []
        stdout: SplitParser {}
        onRunningChanged: {
            if (!running) root.refresh()
        }
    }

    Component.onCompleted: {
        root.refresh()
        root.refreshTrackList()
        pollTimer.start()
        clockTimer.start()
        eqTimer.start()
    }

    Timer {
        id: pollTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        id: clockTimer
        interval: 10000
        repeat: true
        running: true
        onTriggered: root._tickClock()
    }

    Timer {
        id: trackListTimer
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.refreshTrackList()
    }

    property var _eqSeed: 0
    property var _eqBars: [0,0,0,0,0,0,0,0,0,0,0]
    function _tickEq() {
        if (root.state !== "playing") { root._eqBars = [0,0,0,0,0,0,0,0,0,0,0]; return }
        root._eqSeed = (root._eqSeed + 1) % 100000
        var seed = root._eqSeed
        var bars = []
        for (var i = 0; i < 11; i++) {
            var center = 5
            var dist = Math.abs(i - center)
            var base = 1.0 - dist / 7.0
            var wob = 0.35 * (Math.sin(seed * 0.13 + i * 1.7) * 0.5 + Math.random() * 0.5)
            bars.push(Math.max(0.05, Math.min(1.0, base + wob * (1.05 - base * 0.4))))
        }
        root._eqBars = bars
    }

    Timer {
        id: eqTimer
        interval: 90
        repeat: true
        running: true
        onTriggered: root._tickEq()
    }
}
