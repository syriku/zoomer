# Zoomer (.NET)

Zoomer 是一个 .NET 10/C# 桌面放大镜，支持 macOS 和 Windows。它会截取鼠标所在显示器的一帧画面，并允许缩放和平移；截图不会保存或传输。

## 系统要求

- 开发环境：.NET SDK 10.0.301
- macOS：macOS 14.0 或更高版本，以及 Xcode Command Line Tools（含 macOS SDK）
- Windows：Windows 10 22H2 或 Windows 11 x64
- Windows 客户机必须安装 [.NET 10 Desktop Runtime x64](https://dotnet.microsoft.com/download/dotnet/10.0)

## 使用

### macOS

- `⌥⌘Z` 进入工作模式
- 鼠标滚轮缩放；触控板双指滚动平移、捏合缩放；左键拖动平移
- 进入后会隐藏鼠标指针，并以红色激光笔显示其位置；按住 `F` 聚光鼠标所在位置，松开恢复
- 按 `M` 水平翻转截图，再按一次恢复
- 按 `0` 复位到 1 倍（也支持 `⌘0`）；按 `1`、`2`、`9` 分别切换到 1.5、2、0.7 倍；Esc 退出工作模式

首次使用需要在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中授权 Zoomer。

### Windows

- `Ctrl+Alt+Z` 进入工作模式，也可使用托盘菜单
- 鼠标滚轮缩放，Windows 映射的 `Ctrl+滚轮` 触控板捏合执行缩放
- 左键拖动平移，触控板水平滚动执行水平平移
- 进入后会隐藏鼠标指针，并以红色激光笔显示其位置；按住 `F` 聚光鼠标所在位置，松开恢复
- 按 `M` 水平翻转截图，再按一次恢复
- 按 `0` 复位到 1 倍（也支持 `Ctrl+0`）；按 `1`、`2`、`9` 分别切换到 1.5、2、0.7 倍；Esc 退出工作模式

Windows 桌面截图路径无需单独的屏幕录制权限。若全局快捷键已被其他程序占用，托盘状态会显示注册失败，手动入口仍然可用。
Windows 工作窗口使用 WPF 保留模式渲染，在支持的设备上由 GPU 合成缩放和平移；无硬件加速时会自动回退到软件渲染。

## 开发

```sh
make build
make test
make native
```

生成可直接运行且不依赖目标机安装 .NET 的 macOS universal2 App：

```sh
make app
open artifacts/app/Zoomer.app
```

在 Windows 上生成依赖 .NET 10 Desktop Runtime 的 x64 单文件应用：

```sh
make windows
```

也可直接运行对应的 `dotnet publish` 命令。输出为 `artifacts/windows/win-x64/Release/Zoomer.exe`，其中不包含 .NET 运行时。

## 签名与公证

开发构建默认使用 ad-hoc 签名。正式构建设置 Developer ID 身份：

```sh
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make app
```

先用 `xcrun notarytool store-credentials` 将公证凭据保存到 Keychain，然后运行：

```sh
NOTARY_PROFILE="zoomer-notary" ./scripts/notarize.sh
```

输出为 `artifacts/Zoomer.zip`。证书、Team ID 和公证凭据不会写入仓库。

## 架构

- `src/Zoomer.Core`：状态机、变换模型和可测试接口。
- `src/Zoomer.App`：平台入口、macOS C ABI 适配和 Windows WPF/WinForms 混合实现。
- `native/Zoomer.Native`：AppKit、ScreenCaptureKit、Carbon 和 CoreGraphics 薄桥接。
- `tests/Zoomer.Core.Tests`：无外部测试框架依赖的核心行为测试。

## 贡献政策

本仓库作为作者维护的源码发布仓库，目前不接受 Pull Request、功能请求或其他外部贡献。你仍可以根据 MIT License fork、修改并自行分发本项目。

## 许可证

本项目以 [MIT License](LICENSE.txt) 开源。
