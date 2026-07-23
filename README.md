# Zoomer（RemObjects Elements 迁移版）

Zoomer 是一个面向 macOS 和 Windows 的桌面放大镜。它截取鼠标所在显示器的一帧画面，并提供缩放、平移、水平翻转、激光笔与聚光等演示辅助功能；截图不会保存或传输。

本分支正在将 `main` 的 .NET 10/C# 实现重构为 RemObjects Elements 项目，源码语言统一使用 Oxygene（`.pas`）。当前已建立 `Shared` 的工作区状态与变换逻辑，并实现进度相同的 `MacApp` 与 `WPFApp` 平台层：两端均已覆盖入口、全局快捷键、鼠标所在显示器截图、全屏工作区、缩放、平移、重置、居中、预设倍率、水平翻转、激光笔、隐藏鼠标指针和临时绘图轨迹。

Shared 与两个应用层的实际边界、注册方式和截图资源所有权规则见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 项目职责

### `Shared`：共用功能

`Shared` 承担原 `Zoomer.Core` 的核心职责，保存不依赖平台 UI 的功能。它是包含 `Toffee.macOS` 与 `Echoes.Core` 两个目标的 Elements library，由 `MacApp` 和 `WPFApp` 复用同一份 Oxygene API：

- 工作模式的状态机、请求编号、状态通知与截图资源所有权；
- 缩放、平移、居中、重置、预设倍率和水平翻转变换；
- `IWorkspacePlatformActual` 与 `IWorkspaceSurfaceActual` 平台契约，以及一次性 actual 注册；
- 可独立验证的核心行为与后续共用测试。

共用层不直接引用 Cocoa、WPF 或平台截图 API。它用接口和委托模拟 Kotlin Multiplatform 的 expect/actual：应用层在启动时注册实际实现，Shared 只依赖稳定契约，不重复业务规则。激光笔和绘图属于平台窗口的输入/渲染行为，因此由两个应用层分别实现。

### `WPFApp`：Windows 应用层

`WPFApp` 负责 Windows 专属能力：

- 应用生命周期、托盘菜单与 `Ctrl+Alt+Z` 全局快捷键；
- 显示器发现、桌面截图与错误提示；
- 纯 WPF 工作窗口、图像合成、鼠标/触控板/键盘输入和指针管理；
- Windows 构建、运行与发布。

Windows 托盘菜单和 `Ctrl+Alt+Z` 热键直接使用 Shell/User32 消息窗口，显示器截图直接使用 GDI 并转换为 WPF `BitmapSource`；项目不依赖 WinForms 托管层。截图、窗口和显示器变化通知均回到 WPF dispatcher 线程处理。

### `MacApp`：macOS 应用层与原生能力

`MacApp` 负责 macOS 专属能力，并吸收原 `native/Zoomer.Native` 库的职责。当前已接入菜单栏入口、`⌥⌘Z` 全局快捷键、屏幕录制权限检查、鼠标所在显示器选择、Retina 原生像素截图、AppKit 全屏工作窗口和基础缩放/平移/翻转输入：

- 应用生命周期、菜单与基于 Carbon Hot Key API 的事件驱动 `⌥⌘Z` 全局快捷键；
- 屏幕录制权限、显示器发现与 ScreenCaptureKit 截图；
- AppKit 工作窗口、自定义绘制、鼠标/触控板/键盘输入和指针管理；
- 主线程调度、应用打包、签名与公证。

这些能力通过 Oxygene 的 Cocoa 目标（Toffee 后端）直接实现，不再保留 C# 与 Objective-C 之间的 C ABI 桥接。

## 功能迁移基线

重构以 `main` 的现有行为为基线，目标包括：

- 进入工作模式后隐藏系统指针，并显示红色激光点；
- 滚轮或捏合缩放，拖动或触控板滚动平移；
- `F` 临时聚光，`D` 切换绘图模式，轨迹在松开后延迟渐隐；
- `M` 水平翻转；
- `0` 恢复 1 倍、`C` 居中、`R` 完全重置，`1`、`2`、`9` 切换预设倍率；
- `Esc` 退出工作模式。

平台快捷键、其余输入映射、权限流程和渲染细节以仓库 `main` 分支为验收参考。Windows 当前可使用 `Ctrl+Alt+Z` 或托盘菜单进入工作模式；滚轮缩放，`Ctrl+滚轮` 执行捏合式缩放，左键拖动或水平滚轮平移；`Esc` 退出，`0`、`R`、`C`、`1`、`2`、`9` 和 `M` 的行为与 Shared 命令一致。

## 技术栈与开发环境

- 语言：RemObjects Oxygene（Object Pascal 风格语法）
- 工程系统：RemObjects Elements 的 `.elements` 项目和 `Zoomer.sln`
- macOS：Fire、Cocoa/Toffee、Xcode 与对应 macOS SDK
- Windows：Water 或安装 Elements 扩展的 Visual Studio、Echoes/.NET 与 WPF

使用 Fire 在 macOS 上打开 `Zoomer.sln`，使用 Water 或安装 Elements 扩展的 Visual Studio 在 Windows 上打开该解决方案。应用的构建、运行和打包均由对应 IDE 完成。

Elements 官方资料：[Fire](https://www.remobjects.com/elements/fire/)、[Water](https://www.remobjects.com/elements/water/)、[Cocoa 平台](https://docs.elementscompiler.com/Platforms/Cocoa/)。

## 待整理与迁移

1. 在 Windows 开发机上用 Water 验证 `WPFApp` 与 Shared 的 Echoes 目标，并确定最终 .NET Desktop Runtime 版本。
2. 增加 Oxygene 测试项目，验证 Shared 状态机与变换行为。
3. 在两个平台补齐聚光与其余输入细节。
4. 继续验证截图资源所有权、线程调度、不同输入设备、显示器热插拔与权限失败路径。
5. 完善 Windows 发布、macOS 打包、签名和公证。

## 提交规范

本分支的提交标题必须使用 `[type] Subject` 格式，例如：

```text
[docs] Describe Elements project boundaries
[feat] Add shared zoom state
[fix] Release stale capture frames
```

允许的类型为 `[feat]`、`[fix]`、`[refactor]`、`[docs]`、`[test]`、`[build]` 和 `[chore]`。标题使用英文祈使句，首字母大写，不加句号。

## 贡献政策

本仓库作为作者维护的源码发布仓库，目前不接受 Pull Request、功能请求或其他外部贡献。你仍可以根据 MIT License fork、修改并自行分发本项目。

## 许可证

本项目以 [MIT License](LICENSE.txt) 开源。
