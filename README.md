# zappale

macOS 原生轻量启动器。Swift 6 / SwiftUI / AppKit，零第三方依赖。
界面语言在**设置 → 通用**切换（跟随系统 / 简体中文 / English，切换即时生效）。

macOS 原生轻量启动器。Swift 6 / SwiftUI / AppKit，零第三方依赖。
界面遵循 **macOS Sequoia 设计语言**；功能逻辑规格参照开源项目
[Tinycast](https://github.com/conversun/tinycast-cn)（仅行为规格参考，代码全部原创实现）。

## 功能（v0.6 · M6 AI 图片能力 + Markdown 笔记）

- **应用启动器** — 模糊搜索 + 拼音（全拼/首字母，系统 ICU 罗马化）+ 使用频次（frecency）排序；运行中徽标；右键退出应用；一层子目录扫描 + bundle id 去重
- **呼出面板** — 默认**双击 ⌘**（需辅助功能权限）；或改用常规快捷键（默认 ⌥Space 可改）；设置中录制
- **文件搜索（Spotlight）** — 借系统 Spotlight 索引搜索文件名，不自建索引；作用域文件夹可在设置中管理（默认 桌面/文稿/下载）；面板 Tab 循环 应用→剪贴板→文件；150ms 防抖异步查询；↵ 打开、⌘↵ 在 Finder 中显示、右键拷贝路径
- **剪贴板历史** — 文本 / 图片 / 文件三类（多选整批捕获与写回）；0.5s 轮询；↵ 粘贴回原应用（需辅助功能权限，未授权降级为复制）；↵/⌘↵ 一对动作可互换；⌘P 固定、⌫ 删除；链接/颜色自动识别徽标；图片尺寸显示；可搜索、可固定
- **快捷键管理** — 设置中录制：面板呼出方式、剪贴板历史热键（默认 ⌘⇧V）、每应用独立热键（前台隐藏/后台激活/未运行启动）；应用内冲突检测 + 系统级冲突检测
- **表情与符号** — 精选目录（表情九大类 + 键位/排版符号），中英双语关键词搜索，回车复制
- **笔记** — Markdown 文件（App Support/zappale/notes），面板搜索标题与内容、最近笔记、新建笔记动作；浮动编辑器支持 **编辑/预览双模式**（内置轻量 Markdown 渲染：标题/粗斜体/代码/列表/引用/链接/分隔线）、自动保存、工具栏新建/删除
- **AI 对话** — BYOK 流式对话（OpenAI 兼容 / Anthropic SSE）+ **对话历史**（最近 30 段，可恢复继续，气泡可复制）；无结果时"询问 AI"入口；off = fully off
- **AI 图片识别** — 对话中 **⌘V 粘贴图片** 作为附件（缩略图预览、可移除），多模态发送（OpenAI image_url / Anthropic base64），附件随消息落盘展示
- **AI 文生图 / 图生图** — 对话屏"生图"子模式：无附件走 images/generations，带附件走 images/edits（multipart）；结果图落盘 ai-media 并在气泡展示（右键拷贝 / Finder 显示）
- **表情与符号（网格）** — 10 列网格 + 悬停/选中态；←→↑↓ 键盘导航（↑↓ 按行移动）
- **内联计算器** — 四则 / 幂 / 函数 / 百分比（`200+10%`、`20% of 50`）/ 量纲算术 / 单位换算（长度/质量/温度/时长/数据/**压力/功率/数据速率**）/ 进制 / 日期推算（`today + 3 weeks`）/ 倒计时（`days till 2026-12-25`）/ 时区（`time in Tokyo`、`东京时间`）
- **片段 Snippets** — 可复用文本模板（{query}/{clipboard}/{date} 占位符 + keyword 参数模式）；↵ 复制、⌘↵ 粘贴回前一个应用；设置页管理
- **自定义命令** — 命名 shell 命令（/bin/zsh -c，10s 超时，输出截取）；可选运行前确认与独立热键；↵ 运行、⌘↵ 复制输出
- **窗口管理** — Rectangle 式布局：半屏/四分/三分之二/居中/最大化/留边最大化/还原/跨屏移动（AX 驱动，纯几何引擎可测）；设置开关 + 权限引导
- **AI 快捷动作** — 翻译 / 润色 / 总结选中文字：⌘C 取选中 → AI → 结果贴回原位（仅 AI 开启时出现，需辅助功能权限）
- **备份** — 设置导出/导入 JSON（快捷链接、片段、命令、热键、作用域、偏好；不含 API Key）
- **快捷链接** — URL 模板 + `{query}` `{clipboard}` `{date}` 占位符；keyword 参数模式（输入 `gh swift` 直接搜 GitHub）；设置页增删改
- **系统动作** — 锁定 / 睡眠 / 熄屏 / 重启 / 关机 / 清倒废纸篓 / 深浅外观切换 / 隐藏文件 / 静音与音量 / 重启 Finder·Dock / 退出所有应用；破坏性动作面板内二次确认
- **回退出口** — 无结果时提供 Google 搜索 / 直接打开网址
- **面板交互** — Tab 四屏循环（应用→剪贴板→文件→表情）；Esc 先清空后关闭（对话屏先返回）；⌘1-9 快速激活；行点击 / 悬停 / 右键菜单；滚动边缘渐隐；鼠标所在屏幕居中
- **设置** — Sequoia 系统设置风格侧栏：通用 / 快捷键 / 应用程序 / 文件搜索 / 剪贴板 / 快捷链接 / AI
- **AI（BYOK）** — 连接测试；默认关闭，off = fully off

## 开发

```sh
swift build          # 编译
swift test           # 56 项单元测试
scripts/build-app.sh # 组装 build/QuickAgent.app（release + 自签名）
```

## 安装运行

```sh
scripts/build-app.sh
cp -R build/QuickAgent.app /Applications/
open /Applications/QuickAgent.app
```

应用常驻菜单栏，**双击 ⌘** 或 ⌥Space 呼出面板（可在设置中更换）。语言切换：设置 → 通用 → 界面语言。

## 架构（详见 ARCHITECTURE.md）

```
ZappaleCore/          纯逻辑模块（零 AppKit/SwiftUI/UIKit；已通过 iOS 模拟器编译验证）
  Commands/ Launcher/ Calculator/ Emoji/ Quicklinks/ Snippets/ Clipboard/
  FileSearch/ Notes/ SystemActions/ WindowManagement/ AICore/ Core/ Hotkey(描述层)

zappale/              macOS 应用层
  App/                入口、AppCore 组合根（注入 FeatureGate）、设置窗口
  Palette/            NSPanel + Sequoia UI + PaletteState 协调层
  Clipboard/ FileSearch/ Hotkey/ Notes/ SystemActions/ WindowManagement/ Commands/
                      平台服务：粘贴板轮询、MDQuery、Carbon 热键、CGEvent 双击监听、
                      AppleScript/CoreAudio 执行器、AX 窗口、zsh 命令、笔记编辑器
```

- 部署下限 macOS 14；FeatureGate 按注入的 OS 版本给功能分档（完整/基础），低版本自动隐藏高级功能入口
- macOS 26 前向：`#available(macOS 26.0, *)` 增强玻璃分支 + 用户可开"减弱视觉效果"基础显示
- iOS 兼容路径与 destination 验证命令见 ARCHITECTURE.md

关键不变量（对齐 Tinycast 的行为规格）：

- 面板一行 = CommandEntry 一个；分区标题不占选择索引；AI 对话屏不参与 Tab 循环
- 双击 ⌘ 检测：按下-抬起-按下 ≤0.4s 且无其他修饰键；需要辅助功能权限，未授权自动降级为不可用并在设置页引导
- 单个纯词（无数字）永不触发计算卡——那是应用名
- 计算卡解析失败一律返回 nil，回落为普通搜索
- 剪贴板：自有写入打内部标记，轮询跳过；密码类（Concealed/Transient）永不入库；文件 URL 先于文本读取；易失目录（/tmp 等）文件不入库；多文件整批入库整批写回
- 文件搜索：借 Spotlight 索引不自建；MDQuery 谓词转义防注入；模糊结果封顶分档，永远排在包含命中之后
- 快捷键：HotkeySpec 无修饰键无效；应用内保存前冲突检测；系统级注册失败（被占用）上报设置页；热键设置变化全量重注
- frecency 加分有上限，只能让同档结果换位，不能压过更强匹配
- 破坏性系统动作的确认在协调层，无法被 Runner 绕过
- 快捷链接远程模板强制 HTTPS（deeplink scheme 放行）
- API key 仅存登录 Keychain；远程端点强制 HTTPS（loopback 除外）；请求无磁盘缓存

## 与 tinycast 功能对照

| 能力 | 状态 |
| --- | --- |
| 应用启动器（模糊/拼音/频次/运行徽标/退出） | ✅ |
| 全局热键 + 双击修饰键呼出 | ✅ |
| 每应用热键 | ✅ |
| Spotlight 文件搜索（作用域可管理） | ✅ |
| 剪贴板历史（多文件/固定/粘贴回注/敏感跳过） | ✅ |
| 计算器（量纲/单位/进制/百分比/日期/时区） | ✅（货币汇率暂缓：需网络拉取与码表维护） |
| 快捷链接（模板 + keyword 参数） | ✅ |
| 片段（模板展开；击键自动展开暂缓） | ✅ |
| 自定义命令（脚本 + 热键 + 确认） | ✅ |
| 窗口管理（Rectangle 式布局动作） | ✅（34 动作全集收敛为 16 个高频动作） |
| 系统动作（电源/外观/音频/Finder 等） | ✅ |
| 笔记（md 存储 + 浮动编辑器 + 面板搜索） | ✅ |
| 表情与符号搜索 | ✅（精选目录，旗帜类暂缺） |
| AI 对话（BYOK 流式） | ✅（历史持久化暂缓） |
| AI 快捷动作（选中文字翻译/润色/总结） | ✅ |
| 备份导出 / 导入 | ✅ |
| 双语界面（中/英切换） | ✅ |
| 日历与会议（EventKit） | 后续 |
| 菜单栏搜索 / 窗口切换器 | 后续（复用 AX 底座） |
| Raycast 扩展运行时 | 后续（独立专项） |
| 剪贴板图片 OCR / 文本识别 | 后续（需 Helper 进程隔离） |

## 路线图

- **M6** 片段击键自动展开、AI 对话历史落盘、菜单栏搜索与窗口切换器（复用 AX 底座）
- **M7** Raycast 扩展运行时、剪贴板 OCR（Helper 进程）、日历与会议、货币汇率


## 安全不变量

- AI 能力默认关闭；off = fully off（无入口、无请求、无落盘）；对话仅存内存，收起面板即新会话
- 剪贴板历史落 Application Support，密码类型条目永不捕获
- 每次网络请求使用私有 ephemeral URLSession，无磁盘缓存
