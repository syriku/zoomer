Imports AppKit
Imports CoreGraphics
Imports Foundation
Imports RemObjects.Elements.RTL
Imports ScreenCaptureKit
Imports [Shared].Core

Namespace Application

  Public Class MacWorkspacePlatformActual
    Implements IWorkspacePlatformActual

    Public Function screenRecordingPermission() As WorkspacePermissionState
      If CGPreflightScreenCaptureAccess() Then
        Return WorkspacePermissionState.Granted
      End If

      ' CGPreflightScreenCaptureAccess does not distinguish a first request from a
      ' prior denial. Treating it as NotDetermined keeps the shared layer able to
      ' request permission, while the status-menu action provides Settings access.
      Return WorkspacePermissionState.NotDetermined
    End Function

    Public Sub requestScreenRecordingPermission()
      If Not NSThread.isMainThread Then
        NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
          requestScreenRecordingPermission()
        End Sub)
        Exit Sub
      End If

      If CGRequestScreenCaptureAccess() Then
        Exit Sub
      End If
    End Sub

    Public Sub openScreenRecordingSettings()
      If Not NSThread.isMainThread Then
        NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
          openScreenRecordingSettings()
        End Sub)
        Exit Sub
      End If

      Dim settingsUrl As NSURL = NSURL.URLWithString("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
      If settingsUrl IsNot Null Then
        NSWorkspace.sharedWorkspace().openURL(settingsUrl)
      End If
    End Sub

    Public Sub captureDisplayWithRequestId(requestId As Int64, completion completion As WorkspaceCaptureCompletion)
      If completion Is Null Then
        Exit Sub
      End If

      If Not NSThread.isMainThread Then
        NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
          captureDisplayWithRequestId(requestId, completion: completion)
        End Sub)
        Exit Sub
      End If

      If screenRecordingPermission() <> WorkspacePermissionState.Granted Then
        completeFailureWithRequestId(requestId,
          code: WorkspaceFailureCode.PermissionDenied,
          message: "需要屏幕录制权限",
          completion: completion)
        Exit Sub
      End If

      Dim screen As NSScreen = screenContainingPointer()
      If screen Is Null Then
        completeFailureWithRequestId(requestId,
          code: WorkspaceFailureCode.TargetDisplayUnavailable,
          message: "无法找到鼠标所在的显示器",
          completion: completion)
        Exit Sub
      End If

      Dim display As WorkspaceDisplay = workspaceDisplayForScreen(screen)
      If display Is Null Then
        completeFailureWithRequestId(requestId,
          code: WorkspaceFailureCode.TargetDisplayUnavailable,
          message: "无法读取当前显示器的信息",
          completion: completion)
        Exit Sub
      End If

      Dim pointerLocation As NSPoint = NSEvent.mouseLocation
      SCShareableContent.getShareableContentWithCompletionHandler(Sub(content, contentError)
        If content Is Null OrElse contentError IsNot Null Then
          completeFailureWithRequestId(requestId,
            code: WorkspaceFailureCode.TargetDisplayUnavailable,
            message: "无法读取可截取的显示器",
            completion: completion)
          Exit Sub
        End If

        Dim shareableDisplay As SCDisplay = shareableDisplayInContent(content, atPoint: pointerLocation)
        If shareableDisplay Is Null Then
          completeFailureWithRequestId(requestId,
            code: WorkspaceFailureCode.TargetDisplayUnavailable,
            message: "当前显示器不可用于截屏",
            completion: completion)
          Exit Sub
        End If

        Dim filter As SCContentFilter = New SCContentFilter(Display: shareableDisplay, excludingWindows: New NSArray())
        Dim configuration As SCStreamConfiguration = New SCStreamConfiguration()
        ' ScreenCaptureKit defaults to a logical-size image. Request native backing
        ' pixels explicitly so a Retina display is not captured at half resolution.
        configuration.width = CType(Math.Round(display.Width() * display.BackingScale()), UInt64)
        configuration.height = CType(Math.Round(display.Height() * display.BackingScale()), UInt64)
        configuration.showsCursor = False
        configuration.backgroundColor = NSColor.blackColor().CGColor

        SCScreenshotManager.captureImageWithFilter(filter,
          configuration: configuration,
          completionHandler: Sub(image, captureError)
            If image = Null OrElse captureError IsNot Null Then
              completeFailureWithRequestId(requestId,
                code: WorkspaceFailureCode.CaptureFailed,
                message: "无法截取当前显示器",
                completion: completion)
              Exit Sub
            End If

            Dim retainedImage As CGImageRef = CGImageRetain(image)
            NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
              Try
                Dim nativeImage As NSImage = New NSImage(CGImage: retainedImage, size: NSMakeSize(0.0, 0.0))
                If nativeImage Is Null Then
                  completeFailureWithRequestId(requestId,
                    code: WorkspaceFailureCode.CaptureFailed,
                    message: "无法创建截图图像",
                    completion: completion)
                  Exit Sub
                End If

                Dim frame As MacWorkspaceFrame = New MacWorkspaceFrame(nativeImage)
                completeCaptureWithCompletion(completion,
                  result: WorkspaceCaptureResult.succeededWithRequestId(requestId, frame: frame, onDisplay: display))
              Finally
                CGImageRelease(retainedImage)
              End Try
            End Sub)
          End Sub)
      End Sub)
    End Sub

    Public Function createWorkspaceSurface() As IWorkspaceSurfaceActual
      Return New MacWorkspaceSurfaceActual()
    End Function

    Private Function screenContainingPointer() As NSScreen
      Dim pointerLocation As NSPoint = NSEvent.mouseLocation
      For Each screen As NSScreen In NSScreen.screens
        If NSPointInRect(pointerLocation, screen.frame) Then
          Return screen
        End If
      Next

      Return Null
    End Function

    Private Function workspaceDisplayForScreen(screen As NSScreen) As WorkspaceDisplay
      Dim identifier As String = identifierForScreen(screen)
      If identifier Is Null Then
        Return Null
      End If

      Dim nativeFrame As NSRect = screen.frame
      Return New WorkspaceDisplay(identifier,
        originX: nativeFrame.origin.x,
        originY: nativeFrame.origin.y,
        width: nativeFrame.size.width,
        height: nativeFrame.size.height,
        backingScale: screen.backingScaleFactor)
    End Function

    Private Function identifierForScreen(screen As NSScreen) As String
      Dim displayNumber As NSNumber = TryCast(screen.deviceDescription.objectForKey("NSScreenNumber"), NSNumber)
      If displayNumber Is Null Then
        Return Null
      End If

      Return displayNumber.stringValue
    End Function

    Private Function shareableDisplayInContent(content As SCShareableContent, atPoint pointerLocation As NSPoint) As SCDisplay
      For Each candidate As SCDisplay In content.displays
        If CGRectContainsPoint(candidate.frame, pointerLocation) Then
          Return candidate
        End If
      Next

      Return Null
    End Function

    Private Sub completeFailureWithRequestId(requestId As Int64, code failureCode As WorkspaceFailureCode, message failureMessage As String, completion completion As WorkspaceCaptureCompletion)
      Dim failure As WorkspaceFailure = New WorkspaceFailure(failureCode, message: failureMessage)
      completeCaptureWithCompletion(completion,
        result: WorkspaceCaptureResult.failedWithRequestId(requestId, failure: failure))
    End Sub

    Private Sub completeCaptureWithCompletion(completion As WorkspaceCaptureCompletion, result captureResult As WorkspaceCaptureResult)
      If NSThread.isMainThread Then
        completion(captureResult)
        Exit Sub
      End If

      NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
        completion(captureResult)
      End Sub)
    End Sub

  End Class

End Namespace
