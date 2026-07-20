Namespace Core

  Public Class WorkspaceSession
    Private ReadOnly _platformActual As IWorkspacePlatformActual
    Private ReadOnly _transformModel As WorkspaceTransformModel = New WorkspaceTransformModel()
    Private _surface As IWorkspaceSurfaceActual
    Private _requestId As Int64
    Private _state As WorkspaceState = WorkspaceState.Idle
    Private _statusText As String = "空闲"
    Private _isDisposed As Boolean

    Public Property StateChanged As WorkspaceStateChanged

    Public Sub New(platformActual As IWorkspacePlatformActual)
      If Not assigned(platformActual) Then
        Throw New Exception("平台工作区实现不能为空")
      End If

      _platformActual = platformActual
    End Sub

    Public Property State As WorkspaceState
      Get
        Return _state
      End Get
    End Property

    Public Property StatusText As String
      Get
        Return _statusText
      End Get
    End Property

    Public Property RequestId As Int64
      Get
        Return _requestId
      End Get
    End Property

    Public Property Transform As WorkspaceTransform
      Get
        Return _transformModel.Transform()
      End Get
    End Property

    Public Property RenderState As WorkspaceRenderState
      Get
        Return New WorkspaceRenderState(Transform(), showHud: False)
      End Get
    End Property

    Public Property IsDisposed As Boolean
      Get
        Return _isDisposed
      End Get
    End Property

    Public Sub requestPresentation()
      ensureNotDisposed()
      If _state <> WorkspaceState.Idle Then
        Exit Sub
      End If

      Dim permission As WorkspacePermissionState
      Try
        permission = _platformActual.screenRecordingPermission()
      Catch
        setState(WorkspaceState.Idle, statusText: "无法检查屏幕录制权限")
        Exit Sub
      End Try

      If permission <> WorkspacePermissionState.Granted Then
        Try
          _platformActual.requestScreenRecordingPermission()
        Catch
          setState(WorkspaceState.Idle, statusText: "无法请求屏幕录制权限")
          Exit Sub
        End Try

        setState(WorkspaceState.Idle, statusText: statusTextForPermission(permission))
        Exit Sub
      End If

      _requestId = _requestId + 1
      Dim requestId = _requestId
      setState(WorkspaceState.Capturing, statusText: "正在截屏")

      Try
        _platformActual.captureDisplayWithRequestId(requestId, completion: AddressOf captureDidComplete)
      Catch
        If Not _isDisposed AndAlso _state = WorkspaceState.Capturing AndAlso requestId = _requestId Then
          setState(WorkspaceState.Idle, statusText: "无法截取当前显示器")
        End If
      End Try
    End Sub

    Public Sub dismissWorkspace()
      If _state = WorkspaceState.Idle OrElse _state = WorkspaceState.Dismissing Then
        Exit Sub
      End If

      _requestId = _requestId + 1
      setState(WorkspaceState.Dismissing, statusText: "正在关闭")
      dismissCurrentSurface()
      _transformModel.resetTransform()
      setState(WorkspaceState.Idle, statusText: "空闲")
    End Sub

    Public Sub handleCommand(command As WorkspaceCommand)
      If _isDisposed OrElse _state <> WorkspaceState.Presenting OrElse Not assigned(command) Then
        Exit Sub
      End If

      Select Case command.Kind()
        Case WorkspaceCommandKind.Dismiss
          dismissWorkspace()

        Case WorkspaceCommandKind.ScrollZoom
          If _transformModel.zoomByScrollDelta(command.FirstValue(), atX: command.SecondValue(), atY: command.ThirdValue()) Then
            renderCurrentTransform(showHud: True)
          End If

        Case WorkspaceCommandKind.Magnify
          If _transformModel.zoomByMagnification(command.FirstValue(), atX: command.SecondValue(), atY: command.ThirdValue()) Then
            renderCurrentTransform(showHud: True)
          End If

        Case WorkspaceCommandKind.Pan
          If _transformModel.translateBy(command.FirstValue(), deltaY: command.SecondValue()) Then
            renderCurrentTransform(showHud: False)
          End If

        Case WorkspaceCommandKind.ResetScale
          _transformModel.resetScale()
          renderCurrentTransform(showHud: True)

        Case WorkspaceCommandKind.ResetWorkspace
          _transformModel.resetTransform()
          renderCurrentTransform(showHud: True)

        Case WorkspaceCommandKind.Center
          If _transformModel.centerInViewport(command.FirstValue(), height: command.SecondValue()) Then
            renderCurrentTransform(showHud: False)
          End If

        Case WorkspaceCommandKind.PresetScale
          If _transformModel.setPresetScale(command.FirstValue(), atX: command.SecondValue(), atY: command.ThirdValue()) Then
            renderCurrentTransform(showHud: True)
          End If

        Case WorkspaceCommandKind.ToggleHorizontalFlip
          _transformModel.toggleHorizontalFlip()
          renderCurrentTransform(showHud: False)
      End Select
    End Sub

    Public Sub disposeSession()
      If _isDisposed Then
        Exit Sub
      End If

      _isDisposed = True
      _requestId = _requestId + 1
      If _state <> WorkspaceState.Idle Then
        setState(WorkspaceState.Dismissing, statusText: "正在关闭")
      End If

      dismissCurrentSurface()
      _transformModel.resetTransform()
      setState(WorkspaceState.Idle, statusText: "已关闭")
    End Sub

    Private Sub captureDidComplete(result As WorkspaceCaptureResult)
      If Not assigned(result) Then
        If Not _isDisposed AndAlso _state = WorkspaceState.Capturing Then
          setState(WorkspaceState.Idle, statusText: "无法截取当前显示器")
        End If
        Exit Sub
      End If

      If _isDisposed OrElse _state <> WorkspaceState.Capturing OrElse result.RequestId() <> _requestId Then
        releaseFrameIfPresent(result.Frame())
        Exit Sub
      End If

      If Not result.IsSuccess() Then
        releaseFrameIfPresent(result.Frame())
        setState(WorkspaceState.Idle,
          statusText: statusTextForFailure(result.Failure(), fallback: "无法截取当前显示器"))
        Exit Sub
      End If

      presentCapture(result)
    End Sub

    Private Sub presentCapture(result As WorkspaceCaptureResult)
      Dim surface As IWorkspaceSurfaceActual = Null
      Dim presentationResult As WorkspacePresentationResult = Null

      Try
        surface = _platformActual.createWorkspaceSurface()
        If Not assigned(surface) Then
          Throw New Exception("平台未创建工作区界面")
        End If

        wireSurface(surface)
        presentationResult = surface.presentFrame(result.Frame(), onDisplay: result.Display())
      Catch
        dismissUnownedSurface(surface)
        releaseFrameIfPresent(result.Frame())
        setState(WorkspaceState.Idle, statusText: "无法创建工作区界面")
        Exit Sub
      End Try

      If Not assigned(presentationResult) OrElse Not presentationResult.IsSuccess() Then
        dismissUnownedSurface(surface)
        releaseFrameIfPresent(result.Frame())
        Dim failure As WorkspaceFailure = Null
        If assigned(presentationResult) Then
          failure = presentationResult.Failure()
        End If
        setState(WorkspaceState.Idle,
          statusText: statusTextForFailure(failure, fallback: "无法显示工作区"))
        Exit Sub
      End If

      ' Ownership transferred to the surface only after the successful result above.
      _surface = surface
      _transformModel.resetTransform()
      Try
        _surface.renderTransform(_transformModel.Transform(), showHud: True)
      Catch
        dismissCurrentSurface()
        _transformModel.resetTransform()
        setState(WorkspaceState.Idle, statusText: "无法显示工作区")
        Exit Sub
      End Try

      setState(WorkspaceState.Presenting, statusText: "工作模式")
    End Sub

    Private Sub wireSurface(surface As IWorkspaceSurfaceActual)
      surface.CommandRequested = AddressOf handleCommand
      surface.DismissRequested = AddressOf dismissWorkspace
      surface.TargetDisplayDisconnected = AddressOf dismissWorkspace
    End Sub

    Private Sub dismissUnownedSurface(surface As IWorkspaceSurfaceActual)
      If Not assigned(surface) Then
        Exit Sub
      End If

      unwireSurface(surface)
      Try
        surface.dismissPresentation()
      Catch
        ' Shared still owns a failed presentation frame and releases it afterwards.
      End Try
    End Sub

    Private Sub dismissCurrentSurface()
      Dim surface = _surface
      _surface = Null
      If Not assigned(surface) Then
        Exit Sub
      End If

      unwireSurface(surface)
      Try
        surface.dismissPresentation()
      Catch
        ' The actual still owns a successfully presented frame even if dismissal reports an error.
      End Try
    End Sub

    Private Sub unwireSurface(surface As IWorkspaceSurfaceActual)
      surface.CommandRequested = Null
      surface.DismissRequested = Null
      surface.TargetDisplayDisconnected = Null
    End Sub

    Private Sub renderCurrentTransform(showHud As Boolean)
      If Not assigned(_surface) Then
        Exit Sub
      End If

      Try
        _surface.renderTransform(_transformModel.Transform(), showHud: showHud)
      Catch
        dismissCurrentSurface()
        _transformModel.resetTransform()
        setState(WorkspaceState.Idle, statusText: "无法更新工作区")
      End Try
    End Sub

    Private Sub releaseFrameIfPresent(workspaceFrame As IWorkspaceFrame)
      If Not assigned(workspaceFrame) Then
        Exit Sub
      End If

      Try
        workspaceFrame.releaseFrame()
      Catch
        ' A release failure must not revive or block a stale workspace request.
      End Try
    End Sub

    Private Sub setState(state As WorkspaceState, statusText text As String)
      _state = state
      _statusText = text
      Dim stateChangedListener = StateChanged()
      If assigned(stateChangedListener) Then
        stateChangedListener(New WorkspaceStateSnapshot(state, statusText: text, requestId: _requestId, transform: _transformModel.Transform()))
      End If
    End Sub

    Private Function statusTextForPermission(permission As WorkspacePermissionState) As String
      Select Case permission
        Case WorkspacePermissionState.Denied
          Return "已拒绝屏幕录制权限"
        Case WorkspacePermissionState.Restricted
          Return "屏幕录制权限不可用"
        Case Else
          Return "需要屏幕录制权限"
      End Select
    End Function

    Private Function statusTextForFailure(failure As WorkspaceFailure, fallback fallbackText As String) As String
      If Not assigned(failure) Then
        Return fallbackText
      End If

      Dim failureMessage = failure.Message()
      If assigned(failureMessage) AndAlso failureMessage <> "" Then
        Return failureMessage
      End If

      Return WorkspaceFailure.defaultMessageForCode(failure.Code())
    End Function

    Private Sub ensureNotDisposed()
      If _isDisposed Then
        Throw New Exception("工作区会话已经关闭")
      End If
    End Sub
  End Class

End Namespace
