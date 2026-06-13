# FineTune 运行原理

参考源固定为 `ronitsingh10/FineTune` 的 `main` commit
`8c5b7fc830748ba6faafde5e0f5223288ba2fbe1`。本文件用于指导 PeakHalo 的
GPLv3 兼容音频模块迁移，不作为 FineTune 品牌、图标或产品身份的复制清单。

## 1. 启动和对象所有权

FineTune 是一个 LSUIElement 菜单栏 App。`FineTuneApp` 在初始化时创建所有长生命周期服务：

- `SettingsManager` 读写 `Application Support/FineTune/settings.json`。
- `AutoEQProfileManager` 管理 AutoEQ 搜索、下载、导入和缓存。
- `AudioRecordingPermission` 管理 Screen & System Audio Recording 权限。
- `AudioEngine` 是音频域唯一协调器，持有进程监听、设备监听、设备音量、tap 控制器、设置和状态。
- `AccessibilityPermissionService`、`MediaKeyMonitor`、`HUDWindowController`、`ShortcutsRegistry` 负责媒体键、全局快捷键和 HUD。
- `MenuBarIconCoordinator` 根据当前默认输出音量、静音和设备切换状态更新菜单栏图标。
- `URLHandler` 挂到 AppDelegate 的 URL open 入口，调用 `AudioEngine` 的公开能力。

启动阶段还会安装 `CrashGuard`，并调用 `OrphanedTapCleanup.destroyOrphanedDevices()` 清理上次崩溃遗留的私有 aggregate device。

## 2. 权限状态机

`AudioRecordingPermission` 是一个 MainActor observable 状态机，状态只有 `unknown`、`authorized`、`denied`。

- `refreshStatus()` 使用 TCC SPI `TCCAccessPreflight` 查询 `kTCCServiceAudioCapture`。
- `request()` 只在非 authorized 时调用 TCC SPI `TCCAccessRequest`。
- App 重新激活时刷新权限状态，覆盖用户从系统设置里改权限的场景。
- `AudioEngine` 只有在权限 authorized 后才启动 `AudioProcessMonitor` 并恢复已保存的 App tap。

这点很关键：播放设备 picker 或音量按钮不直接请求权限；它们只读权限状态。权限请求集中在启动或明确权限入口，避免每次点击切换设备都弹授权。

## 3. 应用监听

`AudioProcessMonitor` 不是枚举 `NSWorkspace.runningApplications` 后猜测谁在播放，而是读取 CoreAudio 的
`kAudioHardwarePropertyProcessObjectList`。

每个 CoreAudio process object 会读取：

- `kAudioProcessPropertyPID`
- `kAudioProcessPropertyIsRunning`
- `kAudioProcessPropertyBundleID`

然后用两层逻辑把 helper 进程合并回主 App：

- 先调用私有 responsibility API `responsibility_get_pid_responsible_for_pid`。
- 失败后用 `sysctl(KERN_PROC_PID)` 沿父进程树向上找 `.app` bundle。

Safari WebKit、Chrome/Brave Helper、Electron helper、XPC service 都通过这个逻辑归并到主应用。最终 `AudioApp` 以主 App PID 为 id，保留所有相关 CoreAudio process object IDs。系统音频守护进程通过 bundle prefix 和进程名前缀过滤，不进入用户 App 列表。

监听由三层组成：

- CoreAudio process list listener 监听进程集合变化。
- 每个 process object 监听 `kAudioProcessPropertyIsRunning`。
- 10 秒定时刷新兜底，防止 HAL 生命周期通知丢失。

## 4. 设备监听

`AudioDeviceMonitor` 维护输出、输入设备和 UID/ID 快速索引。

- 读取 `kAudioHardwarePropertyDevices`。
- 按 stream direction 区分 input/output。
- 过滤 FineTune 自己创建的私有 aggregate device，避免把内部 tap 输出暴露给 UI。
- 监听默认输出、默认输入和设备列表变化。
- 对设备列表刷新做 debounce，因为 HAL 在设备插拔时会短暂返回不稳定状态。
- Bluetooth 设备会监听采样率和 data source，以处理 A2DP/SCO 切换。

设备 UID 是持久化主键，AudioObjectID 只用于当前会话实际 CoreAudio 写入。

## 5. 设备音量后端

`DeviceVolumeMonitor` 把每个设备分配到一个音量后端：

- hardware：CoreAudio 硬件或 virtual main volume 可写。
- DDC：显示器类设备使用 VCP `0x62` 控制外接显示器音量。
- software：硬件/显示器都不可控时，FineTune 通过 tap 软件增益模拟设备音量。

后端在刷新设备列表时计算并缓存。滑块和静音按钮不会同步全量扫描设备，也不会重探所有 DDC 显示器。

DDC 静音语义：

- mute 保存当前非零音量，然后写 0。
- unmute 恢复保存音量，没有保存值时使用默认值。
- 滑到 0 视为 muted。
- 从 0 拉高自动解除 muted。

## 6. 路由意图和持久化

FineTune 把“用户选择意图”和“当前可用 CoreAudio 设备”分开：

- `DeviceSelectionMode.single`：单输出设备。
- `DeviceSelectionMode.multi`：多输出设备。
- System Audio / follows default：跟随 macOS 默认输出。
- explicit route：固定到用户选择的设备，不随默认输出变化。

设置里同时保存：

- App 音量、静音、boost。
- App 设备选择模式。
- App 选择的设备 UID 列表。
- pinned/ignored App。
- 隐藏设备、设备优先级、输入设备锁定。
- EQ、AutoEQ、loudness、HUD、快捷键、外观等全局设置。

设备断开时，显式选择不会被覆盖；运行时临时 fallback 到默认输出。设备重连后再恢复到用户原选择。

## 7. Tap 和 aggregate 生命周期

`ProcessTapController` 是每个 App 的运行中处理链路。

创建链路时：

- 对 follows default 场景，优先创建 stream-specific tap：
  `CATapDescription(processes:deviceUID:stream:)`。
- 对 explicit route 场景，使用 `CATapDescription(stereoMixdownOfProcesses:)`。
- 创建私有 aggregate device，把目标输出 subdevices 和 tap list 组合起来。
- 调用 `waitUntilReady(timeout: 2.0)` 等待 aggregate 可用。
- 创建 IOProc 并启动 aggregate。

切换输出时，优先创建并启动新链路；新链路成功后再销毁旧链路。失败时保留旧链路。这样 picker 点击不会因为半路失败把 App 变成无声。

崩溃和异常退出由 `CrashGuard`、`OrphanedTapCleanup`、tap destroy 路径共同清理。

## 8. Render pipeline

IOProc render 路径处理的是实时音频，不做任何 UI 或磁盘操作。

顺序大致为：

1. 按输入/输出 buffer 布局映射样本。
2. 应用 per-app volume、mute、boost。
3. 应用 per-app EQ。
4. 应用 per-device AutoEQ。
5. 应用 loudness equalization。
6. 应用 loudness compensation。
7. soft limiter 防止削波。
8. 写入目标设备 preferred stereo channels，其余声道清零或按规则映射。

多声道 HDMI/显示器设备尤其依赖 preferred stereo channels；不能简单按 buffer index 复制，否则会出现“切换成功但听不到”。

## 9. UI 和交互

菜单栏弹窗由 `MenuBarPopupView` 组合：

- Output/Input tab。
- 输出设备行、输入设备行、Bluetooth paired device 行。
- App 行：音量、静音、boost、设备 picker、EQ 展开。
- 编辑模式：pin/ignore App、隐藏设备、设备优先级拖拽。
- Device inspector：采样率、transport、UID、hog mode、软件音量 override。
- AutoEQ picker 和导入。

设备 picker 支持 Single/Multi。System Audio 行表示跟随 macOS 默认输出，其他行是显式设备。选择后立即生效，不需要额外点击处理按钮。

Settings root 包含 General、Audio、Shortcuts、Updates、About。全局快捷键使用 `KeyboardShortcuts`，更新使用 `Sparkle`。

## 10. PeakHalo 迁移原则

PeakHalo 要融合 FineTune 能力，而不是变成 FineTune App：

- 保留 PeakHalo 的刘海/灵动岛/资源监控主体验。
- 音频模块采用 FineTune 的所有权分层和行为语义。
- App 名称、图标、窗口结构、现有资源监控设置继续属于 PeakHalo。
- GPLv3 来源和许可证必须随代码保留。

