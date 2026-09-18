# 架构：逻辑层 / UI 层分离 与 平台兼容策略

zappale 的代码分为三个世界：**ZappaleCore（纯逻辑）**、**平台服务（macOS 能力封装）**、**展示与 UI（SwiftUI）**。目标是 macOS 与未来 iOS（含 macOS/iOS 26）共享同一套逻辑。

```
┌─────────────────────────────────────────────────────────────┐
│ ZappaleCore（SPM library，platforms: macOS 14+ / iOS 15+）  │
│ 零 AppKit / SwiftUI / UIKit 依赖 —— 已通过 iOS 模拟器编译验证 │
│                                                             │
│ Commands/     CommandEntry、CommandQuery（查询合并）、       │
│               CustomCommand 模型与查询                      │
│ Launcher/     AppIndex（扫描/索引）、FuzzyMatch、拼音、      │
│               LauncherRankingStore（frecency）              │
│ Calculator/   CalcEngine + CalcNatural（纯函数，now 注入）   │
│ Emoji/        表情与符号目录                                 │
│ Quicklinks/   模板渲染 + 查询 + JSON 存储                    │
│ Snippets/     片段模板 + 查询 + 存储                         │
│ Clipboard/    剪贴板模型/环形存储/搜索（粘贴板轮询在平台层）  │
│ FileSearch/   谓词构建/转义/排序（MDQuery 在平台层）          │
│ Notes/        Note 模型、NotesStore、MarkdownParser          │
│ SystemActions/ 系统动作目录（数据 + 确认标记）                │
│ WindowManagement/ WindowAction + WindowPlacement（纯几何）   │
│ AICore/       AIClient（连通/流式/生图）、AIChat 消息体、     │
│               ChatHistory、AIEndpointPolicy                  │
│ Core/         AppSettings、KeychainStore、L10n、SettingsBackup、│
│               FeatureGate、HotkeySpec/HotkeyBinding、        │
│               DoubleTapDetector                             │
└──────────────────────────┬──────────────────────────────────┘
                           │ 依赖（编译期单向：app → core）
┌──────────────────────────▼──────────────────────────────────┐
│ zappale（macOS 可执行）                                     │
│                                                             │
│ 平台服务：HotkeyCenter（Carbon）、DoubleTapMonitor（CGEvent）、│
│   ClipboardManager（NSPasteboard 轮询）、Paster（AX ⌘C/⌘V）、│
│   SystemActionRunner（AppleScript/pmset/CoreAudio）、         │
│   AXWindowAccess（窗口读写）、FileSearchService（MDQuery）、   │
│   CustomCommandRunner（Process/zsh）、NotesEditorController   │
│                                                             │
│ 展示层：PaletteState（状态机 + 协调；副作用经回调/服务注入）、  │
│   PaletteView / 设置窗口 / 各编辑器（SwiftUI）                │
│                                                             │
│ 组合根：AppCore（装配服务、注入 FeatureGate、分发热键）        │
└─────────────────────────────────────────────────────────────┘
```

## 规则

1. **Core 不 import AppKit/UIKit/SwiftUI。** 平台差异代码用 `#if canImport(...)` 隔离（现例：HotkeySpec 的 UCKeyTranslate 键名翻译、NSEvent 修饰键映射）。
2. **环境一律注入**：时钟（`now`）、目录（`URL?`）、OS 版本（`FeatureGate`）都是参数，Core 不读取进程环境，全部可单测。
3. **副作用住在平台层**：Core 里的"存储"只做文件 IO（Foundation），任何 AppKit 调用（粘贴板、Workspace、AX、事件合成）都在服务里；PaletteState 通过回调（`onShouldHide` / `onPasteRequested` / `onQuickAction`）与窗口控制器解耦。
4. **跨模块访问全 public**：Core 的类型与成员公开给 app；`@testable` 下测试仍可触及内部。

## macOS 26 前向兼容与降级显示

- **FeatureGate（Core）**：注入 OS 主版本 → `isAvailable(_:)` 规则表 + `tier`（.full / .basic）+ `supportsEnhancedVisuals`。当前全部功能最低 macOS 14；未来引入 26 专属 API 时只调规则表一行。
- **三档视觉**：`PaletteBackground` 按 ① 用户开启"减弱视觉效果"（不透明基础显示）→ ② `#available(macOS 26.0, *)` 增强玻璃分支 → ③ 标准材质，运行时自动落位。26 SDK 到位后在 `GlassBackdrop` 分支内替换新材质即可，调用方零改动。
- **低版本策略**：部署下限 macOS 14；若某功能未来要求更高版本，`isAvailable` 为 false 时该入口自动隐藏（已接线：窗口管理、AI 生图），面板与设置页同步降级为"基础功能"档并明示。
- 通用设置显示当前档位与版本，用户可手动开启基础显示。

## iOS（含 iOS 26）路径

ZappaleCore 已在 iOS 模拟器目标编译通过（arm64 + iOS 18.2 SDK），验证方式：

```sh
# destination：SDK 路径按本机 Xcode 调整
cat > /tmp/ios-destination.json <<'JSON'
{
  "version": 1,
  "sdk": "$(xcrun --sdk iphonesimulator --show-sdk-path)",
  "toolchain-bin-dir": "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin",
  "extra-cc-flags": [], "extra-cxx-flags": [], "extra-cpp-flags": [],
  "extra-swiftc-flags": [], "arch": "arm64",
  "target": "arm64-apple-ios18.2-simulator"
}
JSON
swift build --destination /tmp/ios-destination.json --target ZappaleCore
```

做一个 iOS 客户端需要实现的部分（Core 之外）：

1. **Presenter**：对照 `PaletteState` 的职责（模式/选择/确认门控/通知/AI 会话状态），用 SwiftUI/UIKit 重写视图；状态机逻辑可直接调用 Core 的 `PaletteRows`、`CommandQuery`、`ChatConversation` 等。
2. **服务实现**：粘贴板（UIPasteboard 轮询替代 NSPasteboard）、应用启动（LSApplicationWorkspace/URLSession）、热键（iOS 无全局热键——双击 ⌘ 等仅桌面语义，`FeatureGate.isDesktop` 已预留）、文件搜索（无 MDQuery——用 Core 的排序逻辑 + 自建索引或仅文档目录枚举）、窗口管理/AX（iOS 不适用，规则表届时上调）。
3. **视觉**：复用同一套分区/行/键帽语义，材质用 UIKit 等价物；iOS 26 玻璃走对应 availability 分支。

## 已知边界

- `PaletteState` 仍引用 AppKit（NSWorkspace/NSPasteboard 附件/NSImage 加载）：它属于 macOS 展示协调层。iOS presenter 不复用该文件，而是复用它调用的全部 Core 组件——这是"逻辑/UI 分离"的契约边界，而非泄漏。
- `SettingsBackup` 的 AppCore 便捷入口在 app 层（`SettingsBackupConvenience.swift`），显式参数版在 Core。
- Carbon 常量以裸值集中在 `CarbonModifierFlags`（HotkeyCenter 仍直接 import Carbon——它本来就是 macOS 专属）。
