# Zoomer（RemObjects Elements 迁移版）

Zoomer 是一个面向 macOS 和 Windows 的桌面放大镜。它截取鼠标所在显示器的一帧画面，并提供缩放、平移、水平翻转、激光笔与聚光等演示辅助功能；截图不会保存或传输。

本分支正在将 `main` 的 .NET 10/C# 实现重构为 RemObjects Elements 项目，源码语言统一使用 Mercury（`.vb`）。第一阶段已建立 `Shared` 的工作区状态与变换逻辑，以及 `MacApp` 的 Cocoa/ScreenCaptureKit 实现；`WPFApplication` 仍保持模板状态。它尚不能替代 `main` 中可运行的完整应用，后续工作会按既定边界补齐交互与平台能力。

Shared 与 MacApp 的实际边界、注册方式和截图资源所有权规则见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 项目职责

### `Shared`：共用功能

`Shared` 承担原 `Zoomer.Core` 的核心职责，保存不依赖平台 UI 的功能。当前它以 Toffee/macOS 目标构建，供 `MacApp` 使用；开始 WPF 迁移时会补回 Echoes 目标，复用同一份 API：

- 工作模式的状态机、请求编号、状态通知与截图资源所有权；
- 缩放、平移、居中、重置、预设倍率和水平翻转变换；
- `IWorkspacePlatformActual` 与 `IWorkspaceSurfaceActual` 平台契约，以及一次性 actual 注册；
- 可独立验证的核心行为与后续共用测试。

共用层不直接引用 Cocoa、WPF 或平台截图 API。它用接口和委托模拟 Kotlin Multiplatform 的 expect/actual：应用层在启动时注册实际实现，Shared 只依赖稳定契约，不重复业务规则。激光笔、聚光和绘图尚未迁移，届时会根据共享规则需要扩展契约。

### `WPFApp`：Windows 应用层

`WPFApp` 负责 Windows 专属能力：

- 应用生命周期、托盘菜单与 `Ctrl+Alt+Z` 全局快捷键；
- 显示器发现、桌面截图与错误提示；
- WPF 工作窗口、图像合成、鼠标/触控板/键盘输入和指针管理；
- Windows 构建、运行与发布。

仓库中的模板目前仍名为 `WPFApplication`，后续开始迁移实现时会统一重命名为 `WPFApp`。

### `MacApp`：macOS 应用层与原生能力

`MacApp` 负责 macOS 专属能力，并吸收原 `native/Zoomer.Native` 库的职责。当前已接入菜单栏入口、`⌥⌘Z` 全局快捷键、屏幕录制权限检查、鼠标所在显示器选择、Retina 原生像素截图、AppKit 全屏工作窗口和基础缩放/平移/翻转输入：

- 应用生命周期、菜单与基于 Carbon Hot Key API 的 `⌥⌘Z` 全局快捷键；
- 屏幕录制权限、显示器发现与 ScreenCaptureKit 截图；
- AppKit 工作窗口、自定义绘制、鼠标/触控板/键盘输入和指针管理；
- 主线程调度、应用打包、签名与公证。

这些能力通过 Mercury 的 Cocoa 目标（Toffee 后端）直接实现，不再保留 C# 与 Objective-C 之间的 C ABI 桥接。

## 功能迁移基线

重构以 `main` 的现有行为为基线，目标包括：

- 进入工作模式后隐藏系统指针，并显示红色激光点；
- 滚轮或捏合缩放，拖动或触控板滚动平移；
- `F` 临时聚光，`D` 切换绘图模式，轨迹在松开后延迟渐隐；
- `M` 水平翻转；
- `0` 恢复 1 倍、`C` 居中、`R` 完全重置，`1`、`2`、`9` 切换预设倍率；
- `Esc` 退出工作模式。

平台快捷键、其余输入映射、权限流程和渲染细节以 `../zoomer`（即仓库 `main`）为验收参考。

## 技术栈与开发环境

- 语言：RemObjects Mercury（Visual Basic 风格语法）
- 工程系统：RemObjects Elements 的 `.elements` 项目和 `Zoomer.sln`
- macOS：Fire、Cocoa/Toffee、Xcode 与对应 macOS SDK
- Windows：Water 或安装 Elements 扩展的 Visual Studio、Echoes/.NET 与 WPF
- 命令行构建：EBuild；macOS 上需要另外安装 Elements External Compiler，Fire 内置的编译器不会自动注册为全局 `ebuild`

完整的 macOS app 链接还需要 Elements 的 `LDD` 工具；只有 Fire 附带的 EBuild 而没有该链接器时，可以完成源码编译检查，但不能产出可运行的 `.app`。

Elements 官方资料：[命令行编译器安装](https://docs.elementscompiler.com/Compiler/Installing/)、[EBuild 构建](https://docs.elementscompiler.com/EBuild/Building/)、[Cocoa 平台](https://docs.elementscompiler.com/Platforms/Cocoa/)。

## 开发命令

根目录 `Makefile` 目前只保留以下待开发命令名，没有实际构建、运行、测试或清理逻辑：

```sh
make build
make test
make macapp
make wpfapp
make run-macapp
make run-wpfapp
make clean
```

安装外部 Elements 编译器后，可将下面的命令作为手动构建入口；`MacApp` 当前需要带有 Cocoa、ScreenCaptureKit 和相应 macOS SDK 的 Toffee 安装：

```sh
ebuild Zoomer.sln
```

## 待整理与迁移

1. 将 `WPFApplication` 工程、目录和程序集统一命名为 `WPFApp`，并确定 Echoes/WPF 目标框架。
2. 为 Shared 增加 Echoes 目标和 Mercury 测试项目，验证状态机与变换行为。
3. 完成 macOS 指针管理、激光笔、聚光、绘图与其余输入细节。
4. 继续验证截图资源所有权、线程调度、不同输入设备与权限失败路径。
5. 再实现 WPF actual、应用层和 Windows 发布流程。
6. 最后实现 Makefile、应用打包、签名与公证。

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
