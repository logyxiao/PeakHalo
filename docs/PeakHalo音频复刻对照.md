# PeakHalo 音频复刻对照

参考 FineTune commit：`8c5b7fc830748ba6faafde5e0f5223288ba2fbe1`。

## 已有基础

- PeakHalo 已有输出设备列表、CoreAudio/DDC 设备音量、App 音量行、设备 picker、process tap、aggregate ready 等局部实现。
- 当前实现仍是 `AudioControlStore` 直接协调多个服务，没有 FineTune 的完整 `AudioEngine` 分层。
- 当前 picker 样式已接近 FineTune，但底层权限、进程监听、路由意图和完整功能覆盖还不完整。

## 必须复刻的核心链路

| FineTune 能力 | PeakHalo 目标 |
| --- | --- |
| `AudioRecordingPermission` | 独立权限状态机，只集中请求一次，picker 点击不触发授权弹窗 |
| `AudioProcessMonitor` | 使用 CoreAudio process object list，合并 helper/XPC/browser 子进程，输出多个可控 App |
| `AudioDeviceMonitor` | 设备 UID/ID 缓存、默认设备监听、隐藏内部 aggregate、插拔 debounce |
| `DeviceVolumeMonitor` | hardware/DDC/software 音量后端缓存，滑块和静音走快路径 |
| `AudioEngine` | 统一管理权限、应用、设备、音量、tap、设置和 UI 状态 |
| `ProcessTapController` | follows default 与 explicit route 区分，支持单/多设备输出，失败保留旧链路 |
| Render pipeline | 音量、静音、boost、EQ、AutoEQ、loudness、limiter、preferred stereo channels |
| Settings | App 路由、音量、pin/ignore、设备优先级、隐藏设备、EQ/HUD/快捷键持久化 |

## 迁移顺序

1. 许可证、来源声明、运行原理文档、最低系统版本升级到 macOS 15。
2. 权限状态机从 `AudioControlStore` 拆出，避免每次点击设备 picker 触发授权。
3. 应用监听按 FineTune 合并逻辑增强，确保多个正在播放的 App 都可见。
4. 设备和音量后端缓存升级为 FineTune 式 monitor，减少滑块/静音卡顿。
5. 抽出 PeakHalo 版 `AudioEngine`，让 UI 只读写 engine 状态。
6. 扩展 route intent：System Audio、single explicit、multi explicit 分开持久化。
7. 扩展 tap/aggregate 到多输出，并接入完整 render pipeline。
8. 融合 EQ、AutoEQ、loudness、soft limiter。
9. 融合媒体键、HUD、全局快捷键、URL scheme、设备 inspector、编辑模式。

## 本轮实现边界

当前已落地第 1-4 步，并开始推进第 6-7 步的路由基础：

- GPLv3 和来源声明。
- macOS 15 manifest。
- FineTune 运行原理文档。
- PeakHalo 复刻对照文档。
- 权限状态机独立化。
- 应用监听增强，减少“只监听到一个应用”和“切换设备反复授权”的问题。
- App 播放设备选择扩展为 `systemDefault` / `single` / `multi` route intent，兼容旧单设备设置。
- Picker 的 Multi 模式支持勾选多个输出设备。
- Tap aggregate 支持多个 output subdevice，主设备/clock 使用第一项，其他设备启用 drift compensation。
- 输出设备音量后端新增 `hardware` / `display` / `software` / `unavailable` 标识；硬件和 DDC 保持快路径，无法硬件/DDC 控制的设备降级为软件音量。
- 软件音量静音语义对齐 FineTune：mute 保存当前非零音量并把可见音量置 0，unmute 恢复保存值或 50%，slider 从 0 拉高自动解除 muted。
- 软件后端和 App 音量 slider 接入 FineTune 式 x²/sqrt 映射：UI 百分比表示滑块位置，底层仍保存线性 PCM gain；硬件/DDC 后端保持线性传给系统。
- 运行中的单输出 App tap 会接收软件设备 gain 更新，不重建 tap；Multi 输出暂不叠加 per-device software gain。
- App 音量、静音、boost 和软件设备 gain 更新进入 render state 后按设备采样率计算约 30ms ramp，减少快速拖动和静音切换的突变。
- Render pipeline 接入 FineTune 式 soft-knee limiter：低于 0.95 透明通过，超过阈值时渐进压缩到 ±1.0 内，降低 2x/3x/4x boost 的硬削波。
- 每个 App 增加基础 10-band EQ：频点、±12dB 范围和部分内置 preset 对齐 FineTune；EQ 设置持久化到 App 设置，运行中的 tap 直接更新 stereo render pipeline。AutoEQ、用户 preset 和 loudness 仍待迁移。
- `SystemAudioVolumeService` 增加 CoreAudio 设备列表和默认输出 listener；轮询保留为兜底，默认设备变化会更快推动 `System Default` App 路由切换。

后续步骤应继续按本文件顺序推进，避免再次在 UI picker 或 tap 单点上反复试错。
