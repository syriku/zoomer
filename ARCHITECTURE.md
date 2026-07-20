# Shared 与 MacApp 的工作区契约

本文件定义 Elements 迁移阶段的第一个跨项目边界。它以 `../zoomer` 的用户行为为基线，但不复制旧版 `Zoomer.Core` 通过多个构造参数取得平台服务的结构。

## 所有权

| 层 | 负责内容 |
| --- | --- |
| `Shared.Core` | 工作模式状态机、变换规则、命令解释、状态通知、请求编号和截图资源所有权规则。 |
| `MacApp` | 应用生命周期、菜单栏、全局快捷键、权限与系统设置入口、鼠标所在显示器的发现、ScreenCaptureKit、AppKit 窗口/视图/输入/渲染，以及主线程调度。 |

`WPFApplication` 暂不实现；以后它会注册同一份 Shared 契约的 Echoes/WPF actual，而不是让 Shared 依赖 WPF。

## expect/actual 注册

`Shared` 对外提供以下稳定 API：

```vb
WorkspaceActuals.registerPlatformActual(actual)
WorkspaceActuals.createSessionUsingRegisteredPlatform()
```

`MacApp` 必须在 `AppDelegate` 启动完成时注册唯一的 `IWorkspacePlatformActual`，然后创建 `WorkspaceSession`。会话在构造时取得 actual 的快照；运行期间不能交换 actual。重复注册或未注册即创建会话都属于启动配置错误。

`Shared` 是 Mercury 保留字，因此 Mercury 消费项目导入公开命名空间时必须写为 `Imports [Shared].Core`；方括号只转义源代码标识符，不改变 API 的实际命名空间。

`IWorkspacePlatformActual` 是平台的唯一入口：

```text
screenRecordingPermission() -> WorkspacePermissionState
requestScreenRecordingPermission()
captureDisplayWithRequestId(requestId, completion: completion)
createWorkspaceSurface() -> IWorkspaceSurfaceActual
```

应用菜单自身打开“屏幕录制”系统设置、注册快捷键或刷新状态文字时，直接使用 MacApp 的实现；这些不是 Shared 的 API。

`IWorkspaceSurfaceActual` 表示一次工作模式展示：

```text
CommandRequested(command)
DismissRequested()
TargetDisplayDisconnected()
presentFrame(frame, onDisplay: display) -> WorkspacePresentationResult
renderTransform(transform, showHud: showHud)
dismissPresentation()
```

三个回调成员是可写的委托属性，而不是 Mercury `Event`：MacApp 在展示期间赋入回调，Shared 在关闭时清空它们。这样既表达单一会话的所有权，也能在 Toffee 后端可靠生成代码。原生输入先映射为 `WorkspaceCommand`，再通过 `CommandRequested` 交给 `WorkspaceSession`。初始命令集覆盖关闭、滚轮缩放、捏合缩放、平移、倍率重置、完全重置、居中、预设倍率和水平翻转。激光笔、聚光与绘图属于 MacApp 的渲染/输入实现；后续需要共享规则时再扩展为独立的 Shared 状态契约。

## 生命周期与资源规则

1. Mac 菜单或全局快捷键调用 `WorkspaceSession.requestPresentation()`。
2. Shared 检查权限并向 actual 请求截图；actual 选择鼠标所在显示器，并在主线程调用 completion。
3. Shared 忽略过时请求，并立即释放其截图帧。成功帧在 `presentFrame` 成功返回前仍由 Shared 所有。
4. `presentFrame` 成功后，surface 独占帧并负责在关闭时释放；失败时 Shared 释放帧并回到空闲状态。
5. surface 的关闭、显示器断开和输入事件都回到 Shared 会话；会话只更新共享状态，并通过 `renderTransform` 让 surface 重绘。

macOS 截图尺寸使用显示器逻辑点尺寸乘以 `backingScaleFactor`，并显式传给 `SCStreamConfiguration`；否则 ScreenCaptureKit 的默认配置会在 Retina 显示器上产生逻辑尺寸截图。工作区视图始终保持为视口大小，缩放、偏移和翻转只参与绘制；鼠标、滚轮和捏合事件因此始终以稳定的视口坐标作为 Shared 变换锚点。

`IWorkspaceFrame.releaseFrame()` 是显式所有权转移点，不能依赖 ARC、GC 或平台图像对象的隐式生命周期。MacApp 必须保证其 capture completion、窗口操作和 surface 事件发生在主线程；Shared 不引入平台调度器。

## 命名规则

所有跨层方法使用 Mercury 分部方法名。典型声明为：

```vb
Sub captureDisplayWithRequestId(requestId As Int64, completion completion As WorkspaceCaptureCompletion)
Function presentFrame(frame As IWorkspaceFrame, onDisplay display As WorkspaceDisplay) As WorkspacePresentationResult
Sub renderTransform(transform As WorkspaceTransform, showHud showHud As Boolean)
```

调用时保留标签：`actual.captureDisplayWithRequestId(requestId, completion: completion)`、`surface.presentFrame(frame, onDisplay: display)`。
