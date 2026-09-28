# 新番桌面小组件 · Anime Airing Widget

一个 Windows 桌面悬浮小组件：**每天**告诉你今天有哪些**新番**在播、**几点播（北京时间）**、**叫什么**、**什么标签**、**在哪个平台放**；
登录 Bangumi 后，还会把你**正在追**的番用 ★ 标注出来，并给出它们各自的播出时间。


<img width="606" height="636" alt="image" src="https://github.com/user-attachments/assets/f6fe4f1d-9c75-4488-bad5-42b46c8a913f" />


---

## 1. 快速开始

1. 双击 **`run.cmd`**（无窗口后台启动，窗口会出现在屏幕右上角）。
2. 右键托盘图标（或右键小组件空白处）可以 **刷新 / 设置 / 隐藏 / 退出**；拖动头部可移动，拖右下角可改变高度。
   外观为**深紫黑底 + 白字 + 紫色高亮**；每页默认显示 **3 部**，滚轮 / ↑↓ / PgUp / PgDn 翻页，每行显示**中文名 + 日文名 + 标签**。
   顶部栏 / 页签条 / 底部栏都是**实心面板**，滚屏时内容被裁剪在列表区内，不会与上下栏重叠；**设置 → 主题背景** 可一键更换配色（深紫 / 纯黑 / 深蓝 / 墨绿 / 暗红 / 浅色 / 自定义背景色）。
3. 想追番标注：点 **设置 → Bangumi 登录**，粘贴访问令牌即可（见第 5 节）。
4. 出错排查：双击 **`debug.cmd`**（带控制台，会先刷新一次并打印日志尾部）。

要求：Windows + Windows PowerShell 5.1（系统自带，无需安装任何东西）。
路径**可以带空格**（`run.cmd` 内部已全部加引号）。

---

## 2. 数据来源

| 内容 | 来源 | 说明 |
| --- | --- | --- |
| 新番名单、**播出时间**、星期、首播日、题材标签、改编类型、版权平台、封面、官网/PV、制作与声优 | **yuc.wiki（長門番堂 / 长门有C 新番表）** | 抓取当季 + 即将开播季的 `/YYYYMM/` 页面并解析 |
| 中文名 / 日文名 / 评分 / 放送电视台 / 标签 / 条目链接 | **Bangumi API**（api.bgm.tv） | `/calendar`、`/v0/subjects/{id}`、搜索接口 |
| **我的在看（追番）** | **Bangumi**（Token 或公开用户名） | `/v0/users/-/collections` 或 `/v0/users/{用户名}/collections` |

**「只展示新番」** 是如何保证的：名单本身只来自 yuc.wiki 的「本季新番表」（不含长篇连载），
再用 Bangumi 每日放送日历交叉验证「是否仍在播」，把已经完结的往季作品剔除
（`dropEndedAfterDays` 天内首播的仍保留，避免刚播完就消失）。

---

## 3. 时间显示（重点）

yuc.wiki 用的是**日本时间**，且深夜档会写成 `24:00`、`25:28` 这种「超过 24 点」的写法。

小组件默认显示 **北京时间（= 日本时间 − 1 小时）**，并自动处理跨日：

| 原站（JST） | 小组件（北京时间） | 说明 |
| --- | --- | --- |
| 周一 24:00 | 周一 23:00 | 同一天 |
| 周三 25:00 | **周四 00:00** | 跨到第二天，星期也跟着变 |
| 周四 25:28 | **周五 00:28** | 同上 |

因此按「周几」浏览时，用的是**北京时间实际播出的那一天**；每行第二行仍保留 `JST 25:00` 原始时间（可在设置里关闭）。

---

## 4. 目录结构

```
anime-widget/
├─ run.cmd                    启动（无窗口）
├─ debug.cmd                  带控制台启动 + 先刷新一次 + 打印日志
├─ config.json                全部设置（设置对话框会写回这里）
├─ src/
│  ├─ AnimeWidget.ps1         入口（单实例、截图自检）
│  └─ lib/
│     ├─ Util.ps1             工具：路径、JSON、HTML 文本、名称归一化、后台任务
│     ├─ Http.ps1             网络层：直连 / 系统代理 / 自定义代理 + 缓存 + TLS 处理
│     ├─ Yuc.ps1              yuc.wiki 新番表解析
│     ├─ Bangumi.ps1          Bangumi API 客户端（日历/详情/搜索/收藏/OAuth）
│     ├─ Data.ps1             配置、合并、过滤、每日刷新、状态存取
│     ├─ Ui.ps1               小组件界面（自绘）
│     ├─ UiRuntime.ps1        事件、定时器、托盘、后台刷新
│     └─ UiDialogs.ps1        详情 / 设置 / 登录对话框
├─ tools/                     自检与调试脚本（见第 9 节）
└─ data/                      运行时生成：state.json、缓存、日志、授权信息
```

`data/` 下的内容：

| 文件 | 说明 |
| --- | --- |
| `state.json` | 最近一次抓取合并后的全部条目（界面离线也能显示） |
| `cache/*.body|.meta.json` | 每个 URL 的原始响应缓存（yuc 页面 6 小时、Bangumi 条目 1 天） |
| `auth.json` | **Bangumi Token / App Secret（明文）**，见第 5 节安全说明 |
| `window.json` | 窗口位置与尺寸 |
| `widget.log` | 运行日志（排查问题看这里） |

---

## 5. Bangumi 登录（追番标注）

三种方式，任选其一：

### 方式一 · 访问令牌（推荐，30 秒）
1. 打开 <https://next.bgm.tv/demo/access-token> 生成个人令牌；
2. 小组件 → **设置 → 登录 / 管理 → 方式一**，粘贴令牌，点 **校验并保存**；
3. 校验成功后小组件会读取你的「在看」，在对应番剧上标注 **★ 在追** 和它的播出时间，
   顶部会出现 **★N** 页签（只看在追）。

### 方式二 · OAuth 网页授权（需自建应用）
1. 在 <https://bgm.tv/dev/app> 创建应用，回调地址填 `http://localhost:3721/callback`（端口可改）；
2. 小组件 → **登录 / 管理 → 方式二**，填 `App ID` / `App Secret` / 端口，点 **开始网页授权**；
3. 浏览器会自动打开授权页，同意后本机 `127.0.0.1` 上的一次性监听会收到回调并换取 Token
   （不需要管理员权限，也不占用系统端口服务）。Token 过期会**自动用 refresh_token 续期**。

### 方式三 · 只读公开收藏（不登录）
填 Bangumi 用户名并勾选 **公开读取**，即可读取该用户公开的「在看」列表（前提是对方未隐藏收藏）。

> **关于写操作**：详情窗口与右键菜单里有「加入我的在看」，会用 Token 调
> `POST /v0/users/-/collections/{id}`。令牌必须带有收藏写权限，否则会提示失败——失败不会影响其他功能。

> **安全提示**：`auth.json` 以**明文**保存令牌与 App Secret，仅保存在本机 `data` 目录。
> 不要把这个文件（或整个 `data` 目录）分享给别人；注销按钮会清空它。

<img width="606" height="636" alt="image" src="https://github.com/user-attachments/assets/00034b77-3e0a-4a65-9e44-d965fa3add33" />

---

## 6. 设置项（`config.json` / 设置对话框）

| 分组 | 项 | 默认 | 说明 |
| --- | --- | --- | --- |
| 数据源 | `useYuc` / `useBangumi` | 均开 | 关掉某一个后只用另一个 |
| 网络 | `proxyMode` | `auto` | `auto`＝按站点记住可用通道（先自定义代理 → 系统代理 → 直连）；也可固定 `direct`/`system`/`custom` |
| 网络 | `proxyUrl` | `http://127.0.0.1:7897` | 自定义 HTTP 代理（Clash 混合端口即可） |
| 网络 | `allowInsecureTls` | `true` | 忽略 HTTPS 证书错误，代理做中间人 / 自签证书时必需 |
| 网络 | `timeoutSec` | `25` | 单次请求超时 |
| 显示 | `showJstTime` | `true` | 每行显示 `JST hh:mm` |
| 显示 | `showStreaming` | `true` | 显示「网络放送 / 其他」栏目（Netflix 等） |
| 显示 | `topMost` / `opacity` | 置顶 / **1.0** | 窗口置顶与不透明度；**1.0 时文字最清晰**（半透明会关闭 ClearType 并产生残影） |
| 外观 | `theme` | `deep-purple` | 背景主题：`deep-purple` / `black` / `deep-blue` / `dark-green` / `dark-red` / `light` / `custom` |
| 外观 | `bgCustom` | `#14121E` | `theme = custom` 时使用的自定义背景色，其余颜色按亮度自动推导 |
| 刷新 | `refreshHours` | `6` | 后台自动刷新间隔 |
| 刷新 | `dailyRefreshAt` | `04:10` | 每天该时刻后首次检查必定刷新（跨日也会自动刷新） |
| 解析 | `resolveBangumiIds` / `maxResolvePerRefresh` | 开 / 30 | 为 yuc 名单里的新番自动匹配 Bangumi 条目（补评分/电视台），每次上限，逐次补齐 |
| 账号 | `username` / `usePublicCollections` | 空 / 关 | 公开收藏读取（方式三） |
| 账号 | `oauthAppId` / `oauthAppSecret` / `oauthRedirectPort` | 空 / 3721 | OAuth 方式 |
| 窗口 | `width` | 404 | 宽度 |
| 窗口 | `rowsPerView` | 3 | **每页显示几部番**（窗口高度随之变化，设置里可改 1~20） |
| 窗口 | `height` | 348 | 默认高度由 `rowsPerView` 计算；手动拉高后会被记住 |

**关于 Bangumi 访问**：`api.bgm.tv` 在部分网络下无法直连，小组件默认会经
`http://127.0.0.1:7897`（Clash / Mihomo 常见混合端口）访问；如果你的代理端口不同，改 `proxyUrl` 即可。
`yuc.wiki` 一般可直连。小组件会**按站点记住上次成功的通道**，避免每次都做无效试探。

---

## 7. 每日更新是怎么工作的

* 启动时读 `data/state.json` 立即显示（离线可用）；若数据缺失/过期（默认 6 小时）则在**后台线程**刷新，界面不卡。
* 每秒钟检查一次：跨日 / 超过 `refreshHours` / 过了 `dailyRefreshAt` → 自动刷新。
* 想让它开机就跑：`Win+R` → `shell:startup` → 把 `run.cmd` 的快捷方式丢进去。
* 也可以只用命令行刷新（例如配合计划任务）：`powershell -File tools\Refresh-Once.ps1 -Root "…\anime-widget"`。

---

## 8. 交互速查

| 操作 | 效果 |
| --- | --- |
| 拖动头部 / 空白处 | 移动窗口（位置会记住） |
| 拖右下角 | 调整大小 |
| 左键点击条目 | 打开对应的 Bangumi 条目页 |
| 右键点击条目 | 打开 Bangumi / 查看详情 / 官网 / PV / 复制名称 / **加入我的在看** |
| 右键空白处 / 托盘图标 | 刷新、设置、隐藏、退出 |
| 页签 `一…日` | 切换星期（`·` 标记今天），按**北京时间**归组 |
| 页签 `★N` | 只看在追的新番 |
| 滚轮 / ↑↓ | 滚动列表（滚屏时行内容被裁剪在列表区内，不会压到标题栏） |
| PgUp / PgDn / Home / End | 整页翻页 / 跳到顶 / 跳到底 |
| ← → | 切换星期 |
| F5 | 立即刷新 |
| Esc | 隐藏到托盘 |

---

## 9. 自检与调试脚本

```powershell
# 语法检查（当前 PowerShell）
powershell -NoProfile -File tools\Test-Syntax.ps1 -Root .

# 离线解析测试：用 tools\samples 里的真实页面快照验证 yuc.wiki 解析
powershell -NoProfile -File tools\Test-Yuc.ps1 -Sample yuc_202610.html

# 离线全链路：把样本播种进缓存，跑完整合并管线（不联网）
powershell -NoProfile -File tools\Test-Pipeline.ps1

# 联网刷新一次并打印今天的结果
powershell -NoProfile -File tools\Refresh-Once.ps1 -Root . -Force

# 网络通道诊断（直连 / 代理 / 证书，打印内层异常）
powershell -NoProfile -File tools\Diagnose-Net.ps1 -Root .

# 把界面各视图与三个对话框渲染成图片（build\*.png）
powershell -NoProfile -STA -File tools\Test-Ui.ps1 -Root .
```

---


## 11. 已知限制

* 只在 **Windows** 上运行（WinForms + GDI+ 自绘）。
* yuc.wiki 的「版权平台」只标注中文圈（**巴哈姆特 / Crunchyroll / Netflix** 等，标签为 港台/环大陆/台湾/香港）；
  **内地平台（bilibili/爱奇艺等）原站并不提供**，所以「放映平台」一栏是
  「中文圈版权方 +（Bangumi 提供的）日本电视台」的组合，不是内地独播信息。
* 内地无法直连 `api.bgm.tv` 时需要本机代理（默认已配置 7897，可在设置里改）。
* 新番与 Bangumi 条目按名称模糊匹配，个别译名差异很大的作品可能匹配不到（表现是该行缺评分/电视台，但不影响时间与标签）。
* 首次刷新会为新番逐个解析 Bangumi 条目（每次上限 30 条，约 1~2 分钟），之后走缓存、几秒完成；
  剩下的条目会在后续自动刷新中继续补齐。
* 当前季页面不再提供首播日期（原站改成了 `(全12话)`），此时首播日以 Bangumi 日历/条目为准。
