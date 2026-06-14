# OpenCode Go Usage — DankMaterialShell Plugin

在 DankBar 上显示 OpenCode Go 套餐用量，支持 5 小时滚动窗口、本周和本月用量监控。

## 效果

Bar 上显示当前滚动窗口用量百分比及重置倒计时：

```
📊 56% · 1h 30m
```

点击弹出详情面板，展示三个窗口的进度条和用量表格。

## 安装

```bash
mkdir -p ~/.config/DankMaterialShell/plugins
git clone https://github.com/zhangtingfeng-2000/opencode-go-usage ~/.config/DankMaterialShell/plugins/opencode-go-usage
```

重启 DankBar 或执行 `pkill quickshell`。

## 配置

在 DMS 设置 → 插件列表 → **OpenCode Go Usage** 中配置：

| 字段 | 说明 |
|------|------|
| **Workspace ID** | 从 `https://opencode.ai/workspace/{workspaceId}/go` 获取，格式 `wrk_xxxxx` |
| **Auth Cookie** | 登录 opencode.ai 后，从浏览器开发者工具 → Application → Cookies 中复制 `auth` 字段的值（以 `Fe26.2**` 开头） |
| **刷新间隔** | 数据刷新频率，默认 300 秒 |

### 获取凭证

1. 浏览器登录 [opencode.ai](https://opencode.ai)
2. 进入你的 Workspace Go 仪表盘页面
3. 打开开发者工具（F12）→ Application → Cookies
4. 复制 URL 中的 workspace ID（`wrk_...`）
5. 复制 `auth` Cookie 的值（`Fe26.2**...`）
6. 在插件设置中填入

## 数据来源

插件通过 `curl` 抓取 `https://opencode.ai/workspace/{workspaceId}/go` 页面，解析 SolidJS SSR 中嵌入的三个用量窗口：

| 窗口 | 变量名 | 说明 |
|------|--------|------|
| 滚动窗口 (5h) | `rollingUsage` | 最近 5 小时用量百分比 + 重置倒计时 |
| 本周 | `weeklyUsage` | 本周用量百分比 |
| 本月 | `monthlyUsage` | 本月用量百分比 |

## 文件结构

```
opencode-go-usage/
├── plugin.json                # DMS 插件清单
├── OpenCodeUsageWidget.qml    # 主组件（Bar pill + Popout）
├── OpenCodeUsageSettings.qml  # 设置面板
└── README.md
```

## License

MIT
