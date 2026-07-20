# Zoomer（RemObjects Elements 迁移版）

Zoomer 是一个面向 macOS 和 Windows 的桌面放大镜。它截取鼠标所在显示器的一帧画面，并提供缩放、平移、水平翻转、激光笔与聚光等演示辅助功能；截图不会保存或传输。

本分支正在将 `main` 的 .NET 10/C# 实现重构为 RemObjects Elements 项目，源码语言统一使用 Mercury（`.vb`）。目前仓库只有三个项目的初始模板，尚不能替代 `main` 中可运行的应用；现阶段工作的重点是确定边界、迁移顺序和构建约定。

## 项目职责

### `Shared`：共用功能

`Shared` 承担原 `Zoomer.Core` 的职责，保存不依赖平台 UI 的功能，并同时供 macOS 与 Windows 应用层使用：

- 工作模式的状态与执行流程；
- 缩放、平移、居中、重置、预设倍率和水平翻转变换；
- 激光笔、聚光与绘图轨迹的状态及生命周期；
- 屏幕选择、截图、全局快捷键和工作窗口等平台能力的抽象；
- 可独立验证的核心行为与后续共用测试。

共用层不直接引用 Cocoa、WPF 或平台截图 API。它的作用是让两个应用层只实现平台适配，不重复业务规则。

### `WPFApp`：Windows 应用层

`WPFApp` 负责 Windows 专属能力：

- 应用生命周期、托盘菜单与 `Ctrl+Alt+Z` 全局快捷键；
- 显示器发现、桌面截图与错误提示；
- WPF 工作窗口、图像合成、鼠标/触控板/键盘输入和指针管理；
- Windows 构建、运行与发布。

仓库中的模板目前仍名为 `WPFApplication`，后续开始迁移实现时会统一重命名为 `WPFApp`。

### `MacApp`：macOS 应用层与原生能力

`MacApp` 负责 macOS 专属能力，并吸收原 `native/Zoomer.Native` 库的职责：

- 应用生命周期、菜单与 `⌥⌘Z` 全局快捷键；
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

平台快捷键、输入映射、权限流程和渲染细节以 `../zoomer`（即仓库 `main`）为验收参考。

## 技术栈与开发环境

- 语言：RemObjects Mercury（Visual Basic 风格语法）
- 工程系统：RemObjects Elements 的 `.elements` 项目和 `Zoomer.sln`
- macOS：Fire、Cocoa/Toffee、Xcode 与对应 macOS SDK
- Windows：Water 或安装 Elements 扩展的 Visual Studio、Echoes/.NET 与 WPF
- 命令行构建：EBuild；macOS 上需要另外安装 Elements External Compiler，Fire 内置的编译器不会自动注册为全局 `ebuild`

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

安装外部 Elements 编译器后，可将下面的命令作为手动构建入口；当前模板能否完整构建仍取决于本机 SDK、Elements 版本和各项目目标设置：

```sh
ebuild Zoomer.sln
```

## 待整理与迁移

1. 将 `WPFApplication` 工程、目录和程序集统一命名为 `WPFApp`。
2. 确定 WPF 的 Echoes 目标框架，并删减 `Shared` 中不需要的模板目标。
3. 建立 `Shared` 到两个应用项目的引用，以及覆盖核心行为的 Mercury 测试项目。
4. 先迁移共用状态与变换，再分别迁移 WPF 和 Cocoa 平台适配。
5. 验证截图资源所有权、线程调度、输入差异与权限失败路径。
6. 最后实现 Makefile、应用打包、签名、公证和 Windows 发布流程。

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
