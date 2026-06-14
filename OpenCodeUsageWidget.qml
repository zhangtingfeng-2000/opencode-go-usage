import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "opencode-usage"

    property int refreshInterval: pluginData.refreshInterval || 300
    property string costColor: pluginData.costColor || "#f59e0b"
    property string warnColor: "#f97316"
    property string errorColor: "#ef4444"
    property string goodColor: "#22c55e"
    property string workspaceId: pluginData.workspaceId || ""
    property string authCookie: pluginData.authCookie || ""

    property bool loading: false
    property string lastError: ""
    property bool ready: false

    property var rollingData: ({})
    property var weeklyData: ({})
    property var monthlyData: ({})

    readonly property string dashUrl: root.workspaceId.length > 0
        ? "https://opencode.ai/workspace/" + root.workspaceId + "/go" : ""

    function formatPct(v) {
        if (v === undefined || v === null) return "0%"
        return Math.round(v) + "%"
    }

    function formatTime(sec) {
        if (!sec || sec <= 0) return "now"
        var d = Math.floor(sec / 86400)
        var h = Math.floor((sec % 86400) / 3600)
        var m = Math.floor((sec % 3600) / 60)
        if (d > 0 && h > 0) return d + "d " + h + "h"
        if (d > 0) return d + "d"
        if (h > 0 && m > 0) return h + "h " + m + "m"
        if (h > 0) return h + "h"
        if (m > 0) return m + "m"
        return "<1m"
    }

    function usageColor(pct) {
        if (pct >= 90) return errorColor
        if (pct >= 70) return warnColor
        return goodColor
    }

    function clamp(v) {
        return Math.max(0, Math.min(100, v))
    }

    Timer {
        interval: root.refreshInterval * 1000
        running: root.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onWorkspaceIdChanged: { if (ready) refresh() }
    onAuthCookieChanged: { if (ready) refresh() }

    Component.onCompleted: {
        root.ready = true
    }

    function refresh() {
        if (!root.workspaceId.trim() || !root.authCookie.trim()) {
            root.setError("请在插件设置中配置 Workspace ID 和 Auth Cookie")
            return
        }
        root.loading = true
        root.setError("")

        var url = root.dashUrl
        var auth = root.authCookie.trim()
        var cmd = ["curl", "-s", "--max-time", "10", "-L",
            "-H", "Cookie: auth=" + auth,
            "-H", "User-Agent: Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/148.0",
            url
        ]

        Proc.runCommand("opencode.fetch", cmd, function(stdout, exitCode) {
            root.loading = false
            if (exitCode !== 0) {
                root.setError("请求失败 (exit " + exitCode + ")")
                return
            }

            var html = stdout.trim()
            if (html.length === 0) {
                root.setError("返回空页面")
                return
            }

            if (html.indexOf("/login") >= 0 || html.indexOf("sign in") >= 0 || html.indexOf("login") >= 0) {
                root.setError("Cookie 已过期或未授权，请重新配置")
                return
            }

            root.parseDashboard(html)
        }, 15000)
    }

    function extractObj(html, name) {
        var idx = html.indexOf(name)
        if (idx < 0) return null
        var colon = html.indexOf(":", idx + name.length)
        if (colon < 0) return null
        var start = html.indexOf("{", colon)
        if (start < 0) return null
        var depth = 0, end = -1
        for (var i = start; i < html.length; i++) {
            if (html[i] === "{") depth++
            else if (html[i] === "}") { depth--; if (depth === 0) { end = i; break } }
        }
        if (end < 0) return null
        var body = html.substring(start + 1, end)
        var result = {}
        var up = body.match(/usagePercent\s*:\s*(-?\d+(?:\.\d+)?)/)
        var rs = body.match(/resetInSec\s*:\s*(-?\d+(?:\.\d+)?)/)
        if (up) result.usagePercent = parseFloat(up[1])
        if (rs) result.resetInSec = parseFloat(rs[1])
        return result.usagePercent !== undefined ? result : null
    }

    function tryNames(html, names) {
        for (var i = 0; i < names.length; i++) {
            var r = root.extractObj(html, names[i])
            if (r) return r
        }
        return null
    }

    function findMonthlyFallback(html) {
        // search for any $R[n]={...} containing "month" keyword
        var re = /\$R\[\d+\]=\{([^}]+)\}/g
        var m
        while ((m = re.exec(html)) !== null) {
            var body = m[1]
            if (body.indexOf("month") >= 0) {
                var up = body.match(/usagePercent\s*:\s*(-?\d+(?:\.\d+)?)/)
                if (up) {
                    var rs = body.match(/resetInSec\s*:\s*(-?\d+(?:\.\d+)?)/)
                    var result = { usagePercent: parseFloat(up[1]) }
                    if (rs) result.resetInSec = parseFloat(rs[1])
                    return result
                }
            }
        }
        return null
    }

    function findAnyWindow(html, keyword) {
        var idx = html.indexOf(keyword)
        if (idx < 0) return null
        var start = html.indexOf("{", idx)
        if (start < 0) return null
        var depth = 0, end = -1
        for (var i = start; i < html.length; i++) {
            if (html[i] === "{") depth++
            else if (html[i] === "}") { depth--; if (depth === 0) { end = i; break } }
        }
        if (end < 0) return null
        var body = html.substring(start + 1, end)
        var up = body.match(/usagePercent\s*:\s*(-?\d+(?:\.\d+)?)/)
        if (!up) return null
        var result = { usagePercent: parseFloat(up[1]) }
        var rs = body.match(/resetInSec\s*:\s*(-?\d+(?:\.\d+)?)/)
        if (rs) result.resetInSec = parseFloat(rs[1])
        return result
    }

    function parseDashboard(html) {
        var rolling = root.tryNames(html, ["rollingUsage", "rolling_usage"])
        var weekly = root.tryNames(html, ["weeklyUsage", "weekly_usage"])
        var monthly = root.tryNames(html, ["monthlyUsage", "monthly_usage", "monthUsage"])

        if (!monthly)
            monthly = root.findMonthlyFallback(html)
        if (!monthly)
            monthly = root.findAnyWindow(html, "month")

        if (!rolling && !weekly && !monthly) {
            if (html.indexOf("usagePercent") >= 0) {
                root.setError("页面解析失败，SSR 格式可能已变更")
            } else {
                root.setError("未找到用量数据，请检查 Workspace ID")
            }
            return
        }

        root.rollingData = rolling || ({})
        root.weeklyData = weekly || ({})
        root.monthlyData = monthly || ({})

        if (html.indexOf("month") < 0 && !monthly)
            root.setError("页面中未找到月度数据，可能当前套餐无月度用量限制")
    }

    function setError(msg) {
        root.lastError = msg || ""
    }

    function safeDiv(a, b) {
        if (!b || b === 0) return 0
        return (a / b) * 100
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "bar_chart"
                size: Theme.iconSize - 7
                color: root.lastError ? Theme.error : (Theme.widgetIconColor || Theme.primary)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: {
                    if (!root.ready) return "?"
                    if (root.loading) return "..."
                    var d = root.rollingData
                    if (d && d.usagePercent !== undefined) return root.formatPct(d.usagePercent)
                    return "N/A"
                }
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: root.lastError ? Theme.error : (root.rollingData.usagePercent !== undefined ? root.usageColor(root.rollingData.usagePercent) : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: {
                    if (root.loading || !root.ready) return ""
                    var d = root.rollingData
                    if (d && d.resetInSec !== undefined) return "·" + root.formatTime(d.resetInSec)
                    return ""
                }
                font.pixelSize: Theme.fontSizeSmall
                visible: !root.loading
                color: root.usageColor(root.rollingData.usagePercent || 0)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: "bar_chart"
                size: 20
                color: root.lastError ? Theme.error : (Theme.widgetIconColor || Theme.primary)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: {
                    if (!root.ready) return "?"
                    if (root.loading) return "..."
                    var d = root.rollingData
                    if (d && d.usagePercent !== undefined) return root.formatPct(d.usagePercent)
                    return "N/A"
                }
                color: root.lastError ? Theme.error : (root.rollingData.usagePercent !== undefined ? root.usageColor(root.rollingData.usagePercent) : Theme.surfaceVariantText)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        Column {
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            Rectangle {
                width: parent.width
                height: 68
                radius: Theme.cornerRadius * 1.5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) }
                    GradientStop { position: 1.0; color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08) }
                }
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: 40; height: 40
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent; radius: 20
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        }
                        DankIcon { name: "bar_chart"; size: 22; color: Theme.primary; anchors.centerIn: parent }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        StyledText { text: "OpenCode Go"; font.bold: true; font.pixelSize: Theme.fontSizeLarge; color: Theme.surfaceText }
                        StyledText { text: root.workspaceId.length > 0 ? root.workspaceId : "未配置"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; elide: Text.ElideMiddle; width: 180 }
                    }
                }

                Item {
                    width: 38; height: 38
                    anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                    scale: refreshArea.pressed ? 0.9 : (refreshArea.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onPressed: function(mouse) { refreshRipple.trigger(mouse.x, mouse.y) }
                        onClicked: root.refresh()
                    }

                    Rectangle {
                        anchors.fill: parent; radius: Theme.cornerRadius
                        color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4)
                        border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, refreshArea.containsMouse ? 0.3 : 0.15)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    DankIcon {
                        id: refreshIcon; name: "refresh"; size: 20; color: Theme.primary; anchors.centerIn: parent
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: root.loading
                        }
                    }

                    DankRipple {
                        id: refreshRipple; rippleColor: Theme.surfaceText; cornerRadius: Theme.cornerRadius; anchors.fill: parent
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: root.lastError.length > 0 ? 60 : 0
                radius: Theme.cornerRadius; color: Theme.errorContainer
                visible: root.lastError.length > 0
                StyledText {
                    anchors.centerIn: parent; width: parent.width - Theme.spacingL * 2
                    text: root.lastError; wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter; color: Theme.onErrorContainer
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Row {
                width: parent.width; spacing: Theme.spacingS; visible: root.loading
                DankIcon {
                    name: "sync"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: parent.visible
                    }
                }
                StyledText { text: "获取用量数据..."; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
            }

            Column {
                width: parent.width; spacing: Theme.spacingM; visible: !root.loading

                StyledRect {
                    width: parent.width; height: Math.max(100, columnRolling.implicitHeight + Theme.spacingL * 2)
                    radius: Theme.cornerRadius * 1.5; clip: true
                    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                    border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)

                    Column {
                        id: columnRolling
                        anchors.fill: parent; anchors.margins: Theme.spacingM; spacing: Theme.spacingS

                        StyledText { text: "滚动窗口 (5小时)"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }

                        Row {
                            width: parent.width; height: 28; spacing: Theme.spacingS

                            Rectangle {
                                width: parent.width * 0.7; height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 6; color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.6)

                                Rectangle {
                                    width: parent.width * (root.clamp(root.rollingData.usagePercent || 0) / 100)
                                    height: parent.height; radius: 6
                                    color: root.usageColor(root.rollingData.usagePercent || 0)
                                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                }
                            }

                            StyledText {
                                text: root.formatPct(root.rollingData.usagePercent)
                                font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold
                                color: root.usageColor(root.rollingData.usagePercent || 0)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.rollingData.resetInSec !== undefined
                                ? "重置: " + root.formatTime(root.rollingData.resetInSec)
                                : ""
                            font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
                        }
                    }
                }

                StyledRect {
                    width: parent.width; height: Math.max(120, columnWindows.implicitHeight + Theme.spacingL * 2)
                    radius: Theme.cornerRadius * 1.5; clip: true
                    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                    border.width: 1; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)

                    Column {
                        id: columnWindows
                        anchors.fill: parent; anchors.margins: Theme.spacingM; spacing: Theme.spacingS

                        StyledText { text: "窗口用量"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }

                        Rectangle { width: parent.width; height: 1; color: Theme.surfaceVariantText; opacity: 0.15 }

                        Column {
                            width: parent.width; spacing: Theme.spacingS

                            Row {
                                width: parent.width; spacing: Theme.spacingM
                                Item { width: 50; height: 1 }
                                StyledText { text: "用量"; width: 70; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
                                StyledText { text: "重置"; width: 80; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
                            }

                            Row {
                                width: parent.width; spacing: Theme.spacingM
                                StyledText { text: "5小时"; width: 50; font.pixelSize: Theme.fontSizeSmall; color: root.usageColor(root.rollingData.usagePercent || 0); elide: Text.ElideRight }
                                StyledText { text: root.formatPct(root.rollingData.usagePercent); width: 70; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; color: Theme.surfaceText; elide: Text.ElideRight }
                                StyledText { text: root.formatTime(root.rollingData.resetInSec); width: 80; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; color: Theme.surfaceVariantText; elide: Text.ElideRight }
                            }

                            Row {
                                width: parent.width; spacing: Theme.spacingM
                                StyledText { text: "本周"; width: 50; font.pixelSize: Theme.fontSizeSmall; color: root.usageColor(root.weeklyData.usagePercent || 0); elide: Text.ElideRight }
                                StyledText { text: root.formatPct(root.weeklyData.usagePercent); width: 70; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; color: Theme.surfaceText; elide: Text.ElideRight }
                                StyledText { text: root.formatTime(root.weeklyData.resetInSec); width: 80; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; color: Theme.surfaceVariantText; elide: Text.ElideRight }
                            }

                            Row {
                                width: parent.width; spacing: Theme.spacingM
                                StyledText { text: "本月"; width: 50; font.pixelSize: Theme.fontSizeSmall; color: root.usageColor(root.monthlyData.usagePercent || 0); elide: Text.ElideRight }
                                StyledText { text: root.formatPct(root.monthlyData.usagePercent); width: 70; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; color: Theme.surfaceText; elide: Text.ElideRight }
                                StyledText { text: root.formatTime(root.monthlyData.resetInSec); width: 80; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; color: Theme.surfaceVariantText; elide: Text.ElideRight }
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: Theme.spacingXS }
        }
    }

    popoutWidth: 340
    popoutHeight: 0
}
