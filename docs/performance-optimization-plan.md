# Vibe Island 性能优化落地方案

本文档用于定义 Vibe Island 进入 production-ready 前的性能优化实施范围。本文档只描述落地方案，不包含基线测量阶段。

## 目标

本轮优化聚焦于五个方面：

1. 合并轮询链路，减少空闲态与常驻态的外部命令开销。
2. 消除 terminal backend 的重复探测与短时间重复刷新。
3. 收敛 UI 侧的常驻定时器、重复能力探测和无效全量刷新。
4. 清理无效或低收益的 watcher，并把解析链路继续向增量模式收敛。
5. 调整全局事件监听的生命周期，减少长期挂载的系统级监听器。

## 对应 Beads 任务

当前方案已经拆分为以下 issue：

1. `vibe-island-ax6`：统一会话刷新调度与自适应轮询
2. `vibe-island-sab`：缓存 terminal backend 刷新并消除重复探测
3. `vibe-island-6a3`：收敛进程扫描与 UI 刷新开销
4. `vibe-island-emm`：清理无效 watcher 与 session 事件分支
5. `vibe-island-tz6`：按需启停全局事件监听

## 工作流 A：统一刷新调度与自适应轮询

当前 terminal 会话刷新、Codex 扫描和 Opencode 扫描各自持有独立的 2 秒定时器。这会导致空闲态下持续运行多套定时任务，并重复触发进程树扫描。

本工作流将引入统一的刷新协调器，负责：

1. 接管 terminal、Codex、Opencode 三条刷新链路。
2. 依据 UI 是否展开、是否存在等待审批或处理中会话、是否仍有可见会话，动态调整刷新频率。
3. 在 provider 可见性变化、会话注意力状态变化、用户显式操作后触发即时刷新。
4. 当对应 provider 不可见时，直接跳过该 provider 的轮询扫描。

预期改动区域：

- `CodexIsland/Services/Session/CodexSessionMonitor.swift`
- `CodexIsland/Services/Terminal/TerminalSessionMonitor.swift`
- `CodexIsland/Services/Session/CodexSessionScanner.swift`
- `CodexIsland/Services/Session/OpencodeSessionScanner.swift`
- `CodexIsland/UI/Views/NotchView.swift`

## 工作流 B：backend 探测缓存与重复 subprocess 收敛

当前 terminal backend 刷新会在短时间内重复执行 availability 检查、session 枚举和 reachability 探测。Kitty、iTerm 和 Accessibility fallback 都存在短窗口内重复 shell-out 的情况。

本工作流将完成以下收敛：

1. 在 composite backend 内将 availability 探测和 snapshot 刷新合并为单轮 refresh。
2. 为 backend refresh 结果引入短 TTL 缓存，避免同一轮 UI 刷新内重复探测。
3. 为 Kitty remote-control 端点发现、socket reachability、窗口列表增加短 TTL 缓存。
4. 保留 fallback 能力，但避免在单次 refresh 内重复进入同一 fallback 链路。

预期改动区域：

- `CodexIsland/Services/Terminal/CompositeTerminalBackend.swift`
- `CodexIsland/Services/Terminal/KittyRemoteControlService.swift`
- `CodexIsland/Services/Terminal/KittyHybridBackend.swift`
- `CodexIsland/Services/Terminal/ItermAppleScriptBackend.swift`
- `CodexIsland/Services/Terminal/AccessibilityWindowBackend.swift`

## 工作流 C：进程树扫描缓存、UI 刷新收敛与共享能力探测

当前多条链路会在同一轮刷新中反复调用 `ps`、`lsof`、tmux 判断和工作目录探测；UI 侧则存在每个 row 各自持有 timer、每个 row 各自做一次能力探测、以及 state 未变化时仍全量发布的问题。

本工作流将完成以下内容：

1. 在单轮扫描中缓存 cwd 和 tmux 判断，避免同一轮内重复 `lsof`。
2. 收敛 terminal session 刷新时的无意义 timestamp 抖动，避免 SwiftUI 因值变化被迫重渲染。
3. 将实例列表、notch header、chat processing 指示器上的分散 timer 收敛到共享动画时钟。
4. 将 `yabai` 可用性探测上移到父视图，避免每个实例 row 各自执行探测。
5. 让 `SessionStore` 仅在排序后 state 真正变化时才向 UI 发布。

预期改动区域：

- `CodexIsland/Services/Shared/ProcessTreeBuilder.swift`
- `CodexIsland/Services/Window/YabaiController.swift`
- `CodexIsland/Utilities/TerminalVisibilityDetector.swift`
- `CodexIsland/Services/Terminal/ProcessTreeTerminalFallbackBackend.swift`
- `CodexIsland/Services/Terminal/TerminalSessionMonitor.swift`
- `CodexIsland/Services/State/SessionStore.swift`
- `CodexIsland/UI/Views/CodexInstancesView.swift`
- `CodexIsland/UI/Views/ChatView.swift`
- `CodexIsland/UI/Views/NotchHeaderView.swift`
- `CodexIsland/UI/Components/ProcessingSpinner.swift`

## 工作流 D：watcher 清理与解析链路收敛

当前 `AgentFileWatcher` 已不再驱动真实状态更新，但仍保留完整 watcher 代码路径；同时 subagent 工具解析仍采用整文件同步读入的方式，不适合长时间运行。

本工作流将完成以下内容：

1. 删除或停用已经不再生效的 agent watcher 入口。
2. 清理对应的 `SessionEvent`、bridge 和无效分支，减少维护噪音。
3. 保持主 transcript 的增量解析路径不回退。
4. 为后续继续把 subagent 工具解析改为真正增量模式打下结构基础。

预期改动区域：

- `CodexIsland/Services/Session/AgentFileWatcher.swift`
- `CodexIsland/Models/SessionEvent.swift`
- `CodexIsland/Services/State/SessionStore.swift`
- `CodexIsland/Services/Session/ConversationParser.swift`

## 工作流 E：全局事件监听生命周期优化

当前事件监听 singleton 在初始化时直接注册全局鼠标监听，包含 `mouseMoved`、`mouseDown`、`mouseUp` 和 `mouseDragged`。其中 `mouseDragged` 长期常驻的收益很低，生命周期可以显著收紧。

本工作流将完成以下内容：

1. 将事件监听从“singleton 初始化即启动”调整为显式启停。
2. 保留 notch hover/click 行为所需的基础监听，但把拖拽相关监听改成按需启停。
3. 在 window / view model 生命周期结束时释放对应监听，避免无主监听器常驻。

预期改动区域：

- `CodexIsland/Events/EventMonitor.swift`
- `CodexIsland/Events/EventMonitors.swift`
- `CodexIsland/Core/NotchViewModel.swift`

## 建议实施顺序

推荐按以下顺序落地，以降低回归风险：

1. 工作流 A：先合并轮询。
2. 工作流 B：再消除 backend 重复探测。
3. 工作流 C：随后收敛 UI 刷新与进程扫描缓存。
4. 工作流 D：清理 watcher 和无效事件路径。
5. 工作流 E：最后调整全局事件监听生命周期。

## 完成定义

完成本轮优化后，应满足以下工程目标：

1. 应用空闲时不再维持三套独立 2 秒定时刷新。
2. 单轮 terminal refresh 不再重复触发 availability 与 snapshot 两套探测流程。
3. UI 中不再存在按 row 分散创建的重复 timer 与重复 `yabai` 探测。
4. 已失效的 watcher 与事件分支被移除或停用。
5. 全局 `mouseDragged` 监听不再在整个应用生命周期内常驻。
