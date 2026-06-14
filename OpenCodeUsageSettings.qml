import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "opencodeGoUsage"

    Column {
        width: parent.width
        spacing: Theme.spacingL

        StyledText {
            width: parent.width
            text: "OpenCode Go Usage"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "通过抓取 opencode.ai 仪表盘获取 Go 套餐用量数据（滚动窗口5小时/本周/本月）。"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            text: "需要先登录 https://opencode.ai ，从浏览器开发者工具中获取 Workspace ID 和 Cookie。\n\nWorkspace ID 格式: wrk_xxxxx\nauth Cookie 值: 从 Cookie 中提取 auth 字段的值（以 Fe26.2** 开头）"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            lineHeight: 1.5
        }

        StyledRect {
            width: parent.width
            height: columnAuth.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: columnAuth
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                StringSetting {
                    settingKey: "workspaceId"
                    label: "Workspace ID"
                    description: "从 opencode.ai 仪表盘 URL 获取，格式: wrk_xxxxx"
                    placeholder: "wrk_xxxxx"
                    defaultValue: ""
                }

                StringSetting {
                    settingKey: "authCookie"
                    label: "Auth Cookie"
                    description: "浏览器 Cookie 中 auth 字段的值"
                    placeholder: "Fe26.2**..."
                    defaultValue: ""
                }
            }
        }

        StyledRect {
            width: parent.width
            height: columnDisplay.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: columnDisplay
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                SliderSetting {
                    settingKey: "refreshInterval"
                    label: "刷新间隔"
                    description: "数据刷新频率（秒）"
                    defaultValue: 300
                    minimum: 30
                    maximum: 3600
                    unit: "sec"
                    leftIcon: ""
                }
            }
        }
    }
}
