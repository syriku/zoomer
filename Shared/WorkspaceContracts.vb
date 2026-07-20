Namespace Core

  Public Enum WorkspaceState
    Idle
    Capturing
    Presenting
    Dismissing
  End Enum

  Public Enum WorkspacePermissionState
    Granted
    NotDetermined
    Denied
    Restricted
  End Enum

  Public Enum WorkspaceFailureCode
    PermissionDenied = 1
    TargetDisplayUnavailable
    CaptureFailed
    CaptureCancelled
    PresentationFailed
    PlatformActualFailed
  End Enum

  Public Enum WorkspaceCommandKind
    Dismiss
    ScrollZoom
    Magnify
    Pan
    ResetScale
    ResetWorkspace
    Center
    PresetScale
    ToggleHorizontalFlip
  End Enum

  ' A frame is owned by Shared until presentFrame reports success. The surface then
  ' owns it exclusively and must release it when the presentation is dismissed.
  Public Interface IWorkspaceFrame
    Sub releaseFrame()
  End Interface

  Public Class WorkspaceFailure
    Public Property Code As WorkspaceFailureCode
    Public Property Message As String

    Public Sub New(code As WorkspaceFailureCode, message text As String)
      Me.Code = code
      Me.Message = text
    End Sub

    Public Shared Function defaultMessageForCode(code As WorkspaceFailureCode) As String
      Select Case code
        Case WorkspaceFailureCode.PermissionDenied
          Return "需要屏幕录制权限"
        Case WorkspaceFailureCode.TargetDisplayUnavailable
          Return "无法找到当前显示器"
        Case WorkspaceFailureCode.CaptureCancelled
          Return "截屏已取消"
        Case WorkspaceFailureCode.PresentationFailed
          Return "无法显示工作区"
        Case WorkspaceFailureCode.PlatformActualFailed
          Return "平台工作区实现不可用"
        Case Else
          Return "无法截取当前显示器"
      End Select
    End Function

    Public Shared Function withDefaultMessageForCode(code As WorkspaceFailureCode) As WorkspaceFailure
      Return New WorkspaceFailure(code, message: defaultMessageForCode(code))
    End Function
  End Class

  Public Class WorkspaceDisplay
    Public Property DisplayId As String
    Public Property OriginX As Double
    Public Property OriginY As Double
    Public Property Width As Double
    Public Property Height As Double
    Public Property BackingScale As Double

    Public Sub New(displayId As String, originX x As Double, originY y As Double, width displayWidth As Double, height displayHeight As Double, backingScale scale As Double)
      Me.DisplayId = displayId
      Me.OriginX = x
      Me.OriginY = y
      Me.Width = displayWidth
      Me.Height = displayHeight
      Me.BackingScale = scale
    End Sub
  End Class

  Public Class WorkspaceTransform
    Public Property Scale As Double
    Public Property OffsetX As Double
    Public Property OffsetY As Double
    Public Property IsHorizontallyFlipped As Boolean

    Public Sub New(scale As Double, offsetX x As Double, offsetY y As Double, horizontallyFlipped flipped As Boolean)
      Me.Scale = scale
      Me.OffsetX = x
      Me.OffsetY = y
      Me.IsHorizontallyFlipped = flipped
    End Sub

    Public Shared Function identityTransform() As WorkspaceTransform
      Return New WorkspaceTransform(1.0, offsetX: 0.0, offsetY: 0.0, horizontallyFlipped: False)
    End Function
  End Class

  Public Class WorkspaceRenderState
    Public Property Transform As WorkspaceTransform
    Public Property ShowsHud As Boolean

    Public Sub New(transform As WorkspaceTransform, showHud hud As Boolean)
      Me.Transform = transform
      Me.ShowsHud = hud
    End Sub
  End Class

  Public Class WorkspaceCaptureResult
    Public Property RequestId As Int64
    Public Property Frame As IWorkspaceFrame
    Public Property Display As WorkspaceDisplay
    Public Property Failure As WorkspaceFailure

    Public Sub New(requestId As Int64, frame capturedFrame As IWorkspaceFrame, onDisplay display As WorkspaceDisplay, failure failureValue As WorkspaceFailure)
      Me.RequestId = requestId
      Me.Frame = capturedFrame
      Me.Display = display
      Me.Failure = failureValue
    End Sub

    Public Property IsSuccess As Boolean
      Get
        Return assigned(Me.Frame()) AndAlso assigned(Me.Display()) AndAlso Not assigned(Me.Failure())
      End Get
    End Property

    Public Shared Function succeededWithRequestId(requestId As Int64, frame capturedFrame As IWorkspaceFrame, onDisplay display As WorkspaceDisplay) As WorkspaceCaptureResult
      Return New WorkspaceCaptureResult(requestId, frame: capturedFrame, onDisplay: display, failure: Null)
    End Function

    Public Shared Function failedWithRequestId(requestId As Int64, failure failureValue As WorkspaceFailure) As WorkspaceCaptureResult
      Return New WorkspaceCaptureResult(requestId, frame: Null, onDisplay: Null, failure: failureValue)
    End Function
  End Class

  Public Class WorkspacePresentationResult
    Public Property IsSuccess As Boolean
    Public Property Failure As WorkspaceFailure

    Public Sub New(isSuccess As Boolean, failure failureValue As WorkspaceFailure)
      Me.IsSuccess = isSuccess
      Me.Failure = failureValue
    End Sub

    Public Shared Function succeeded() As WorkspacePresentationResult
      Return New WorkspacePresentationResult(True, failure: Null)
    End Function

    Public Shared Function failedWithFailure(failure failureValue As WorkspaceFailure) As WorkspacePresentationResult
      Return New WorkspacePresentationResult(False, failure: failureValue)
    End Function
  End Class

  Public Class WorkspaceCommand
    Public Property Kind As WorkspaceCommandKind
    Public Property FirstValue As Double
    Public Property SecondValue As Double
    Public Property ThirdValue As Double

    Private Sub New(kind As WorkspaceCommandKind, firstValue first As Double, secondValue second As Double, thirdValue third As Double)
      Me.Kind = kind
      Me.FirstValue = first
      Me.SecondValue = second
      Me.ThirdValue = third
    End Sub

    Public Shared Function dismiss() As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.Dismiss, firstValue: 0.0, secondValue: 0.0, thirdValue: 0.0)
    End Function

    Public Shared Function scrollZoomWithDelta(delta As Double, atX x As Double, atY y As Double) As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.ScrollZoom, firstValue: delta, secondValue: x, thirdValue: y)
    End Function

    Public Shared Function magnifyWithAmount(magnification As Double, atX x As Double, atY y As Double) As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.Magnify, firstValue: magnification, secondValue: x, thirdValue: y)
    End Function

    Public Shared Function panWithDeltaX(deltaX As Double, deltaY y As Double) As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.Pan, firstValue: deltaX, secondValue: y, thirdValue: 0.0)
    End Function

    Public Shared Function resetScale() As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.ResetScale, firstValue: 0.0, secondValue: 0.0, thirdValue: 0.0)
    End Function

    Public Shared Function resetWorkspace() As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.ResetWorkspace, firstValue: 0.0, secondValue: 0.0, thirdValue: 0.0)
    End Function

    Public Shared Function centerInViewport(width As Double, height viewportHeight As Double) As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.Center, firstValue: width, secondValue: viewportHeight, thirdValue: 0.0)
    End Function

    Public Shared Function presetScaleAtAnchor(scale As Double, atX x As Double, atY y As Double) As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.PresetScale, firstValue: scale, secondValue: x, thirdValue: y)
    End Function

    Public Shared Function toggleHorizontalFlip() As WorkspaceCommand
      Return New WorkspaceCommand(WorkspaceCommandKind.ToggleHorizontalFlip, firstValue: 0.0, secondValue: 0.0, thirdValue: 0.0)
    End Function
  End Class

  Public Class WorkspaceStateSnapshot
    Public Property State As WorkspaceState
    Public Property StatusText As String
    Public Property RequestId As Int64
    Public Property Transform As WorkspaceTransform

    Public Sub New(state As WorkspaceState, statusText text As String, requestId id As Int64, transform transform As WorkspaceTransform)
      Me.State = state
      Me.StatusText = text
      Me.RequestId = id
      Me.Transform = transform
    End Sub
  End Class

  Public Delegate Sub WorkspaceCaptureCompletion(result As WorkspaceCaptureResult)
  Public Delegate Sub WorkspaceStateChanged(snapshot As WorkspaceStateSnapshot)
  Public Delegate Sub WorkspaceCommandRequested(command As WorkspaceCommand)
  Public Delegate Sub WorkspaceSurfaceRequested()

  Public Interface IWorkspacePlatformActual
    Function screenRecordingPermission() As WorkspacePermissionState
    Sub requestScreenRecordingPermission()
    Sub captureDisplayWithRequestId(requestId As Int64, completion completion As WorkspaceCaptureCompletion)
    Function createWorkspaceSurface() As IWorkspaceSurfaceActual
  End Interface

  Public Interface IWorkspaceSurfaceActual
    Property CommandRequested As WorkspaceCommandRequested
    Property DismissRequested As WorkspaceSurfaceRequested
    Property TargetDisplayDisconnected As WorkspaceSurfaceRequested

    Function presentFrame(frame workspaceFrame As IWorkspaceFrame, onDisplay display As WorkspaceDisplay) As WorkspacePresentationResult
    Sub renderTransform(transform As WorkspaceTransform, showHud showHud As Boolean)
    Sub dismissPresentation()
  End Interface

  Public Shared Class WorkspaceActuals
    Private Shared _registeredPlatformActual As IWorkspacePlatformActual

    Public Shared Sub registerPlatformActual(actual As IWorkspacePlatformActual)
      If Not assigned(actual) Then
        Throw New Exception("平台工作区实现不能为空")
      End If

      If assigned(_registeredPlatformActual) Then
        Throw New Exception("平台工作区实现只能在启动时注册一次")
      End If

      _registeredPlatformActual = actual
    End Sub

    Public Shared Function createSessionUsingRegisteredPlatform() As WorkspaceSession
      If Not assigned(_registeredPlatformActual) Then
        Throw New Exception("必须先注册平台工作区实现")
      End If

      Return New WorkspaceSession(_registeredPlatformActual)
    End Function
  End Class

End Namespace
