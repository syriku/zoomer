Imports AppKit
Imports CoreGraphics
Imports Foundation
Imports QuartzCore
Imports RemObjects.Elements.RTL
Imports [Shared].Core

Namespace Application

  Public Class MacWorkspaceSurfaceActual
    Implements IWorkspaceSurfaceActual

    Public Property CommandRequested As WorkspaceCommandRequested
    Public Property DismissRequested As WorkspaceSurfaceRequested
    Public Property TargetDisplayDisconnected As WorkspaceSurfaceRequested

    Private _window As MacWorkspaceWindow
    Private _imageView As MacWorkspaceImageView
    Private _hudLabel As NSTextField
    Private _ownedFrame As MacWorkspaceFrame
    Private _targetDisplayId As String
    Private _screenObserver As NSObject
    Private _windowCloseObserver As NSObject
    Private _hudFadeTimer As NSTimer
    Private _isDismissing As Boolean
    Private _didRequestDisplayDismissal As Boolean

    Public Function presentFrame(frame workspaceFrame As IWorkspaceFrame, onDisplay display As WorkspaceDisplay) As WorkspacePresentationResult
      If Not NSThread.isMainThread Then
        Return failedPresentationWithMessage("工作区界面必须在主线程显示")
      End If

      If _window IsNot Null Then
        Return failedPresentationWithMessage("工作区已经显示")
      End If

      Dim nativeFrame As MacWorkspaceFrame = TryCast(workspaceFrame, MacWorkspaceFrame)
      If nativeFrame Is Null OrElse nativeFrame.IsReleased() Then
        Return failedPresentationWithMessage("无法显示工作区：截图无效")
      End If

      If display Is Null Then
        Return failedPresentationWithMessage("无法显示工作区：显示器信息无效")
      End If

      Dim targetScreen As NSScreen = screenWithIdentifier(display.DisplayId())
      If targetScreen Is Null Then
        Return failedPresentationWithMessage("无法显示工作区：目标显示器不可用")
      End If

      Dim image As NSImage = nativeFrame.imageForPresentation()
      If image Is Null Then
        Return failedPresentationWithMessage("无法显示工作区：截图已经释放")
      End If

      Dim newWindow As MacWorkspaceWindow = Null
      Try
        Dim screenFrame As NSRect = targetScreen.frame
        newWindow = New MacWorkspaceWindow(contentRect: screenFrame,
          styleMask: NSWindowStyleMask.Borderless,
          backing: NSBackingStoreType.Buffered,
          defer: False,
          screen: targetScreen)
        newWindow.backgroundColor = NSColor.blackColor
        newWindow.opaque = True
        newWindow.acceptsMouseMovedEvents = True

        Dim contentFrame As NSRect = NSMakeRect(0.0, 0.0, screenFrame.size.width, screenFrame.size.height)
        Dim contentView As NSView = New NSView(Frame: contentFrame)
        Dim imageView As MacWorkspaceImageView = New MacWorkspaceImageView(Frame: contentFrame)
        imageView.Image = image
        imageView.wantsLayer = True
        contentView.addSubview(imageView)

        Dim hudLabel As NSTextField = NSTextField.labelWithString("100%")
        hudLabel.frame = NSMakeRect(16.0, 16.0, 88.0, 36.0)
        hudLabel.font = NSFont.monospacedDigitSystemFontOfSize(18.0, weight: NSFontWeightSemibold)
        hudLabel.textColor = NSColor.whiteColor
        hudLabel.alignment = NSTextAlignment.Center
        hudLabel.wantsLayer = True
        hudLabel.layer.backgroundColor = NSColor.colorWithWhite(0.0, alpha: 0.72).CGColor
        hudLabel.layer.cornerRadius = 7.0
        hudLabel.hidden = True
        contentView.addSubview(hudLabel)

        newWindow.contentView = contentView
        imageView.CommandRequested = AddressOf workspaceCommandRequested
        imageView.DismissRequested = AddressOf workspaceDismissRequested

        _window = newWindow
        _imageView = imageView
        _hudLabel = hudLabel
        _ownedFrame = nativeFrame
        _targetDisplayId = display.DisplayId()
        _didRequestDisplayDismissal = False
        beginObservingDisplayForWindow(newWindow, displayId: _targetDisplayId)

        NSApplication.sharedApplication().activateIgnoringOtherApps(True)
        newWindow.makeKeyAndOrderFront(Null)
        newWindow.makeFirstResponder(imageView)
        Return WorkspacePresentationResult.succeeded()
      Catch caughtError As Exception
        _isDismissing = True
        stopObservingDisplayChanges()
        If newWindow IsNot Null Then
          newWindow.close()
        End If

        clearPresentationWithoutReleasingFrame()
        _isDismissing = False
        Return failedPresentationWithMessage("无法显示工作区")
      End Try
    End Function

    Public Sub renderTransform(transform As WorkspaceTransform, showHud showHud As Boolean)
      If Not NSThread.isMainThread Then
        NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
          renderTransform(transform, showHud: showHud)
        End Sub)
        Exit Sub
      End If

      If _window Is Null OrElse _imageView Is Null OrElse transform Is Null Then
        Exit Sub
      End If

      _imageView.renderTransform(transform)

      If _hudLabel IsNot Null Then
        _hudLabel.stringValue = NSString.stringWithFormat("%.0f%%", transform.Scale() * 100.0)
        If showHud Then
          showHudTemporarily()
        End If
      End If
    End Sub

    Public Sub dismissPresentation()
      If Not NSThread.isMainThread Then
        NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
          dismissPresentation()
        End Sub)
        Exit Sub
      End If

      _isDismissing = True
      stopObservingDisplayChanges()
      stopHudFadeTimer()

      If _imageView IsNot Null Then
        _imageView.CommandRequested = Null
        _imageView.DismissRequested = Null
      End If

      If _window IsNot Null Then
        _window.orderOut(Null)
        _window.close()
      End If

      releaseOwnedFrame()
      clearPresentationWithoutReleasingFrame()
      _isDismissing = False
    End Sub

    Private Sub workspaceCommandRequested(command As WorkspaceCommand)
      Dim commandListener As WorkspaceCommandRequested = CommandRequested()
      If assigned(commandListener) Then
        commandListener(command)
      End If
    End Sub

    Private Sub showHudTemporarily()
      stopHudFadeTimer()
      _hudLabel.hidden = False
      _hudLabel.alphaValue = 1.0
      _hudFadeTimer = NSTimer.scheduledTimerWithTimeInterval(0.8,
        repeats: False,
        block: Sub(timer)
          _hudFadeTimer = Null
          If _hudLabel IsNot Null Then
            NSAnimationContext.runAnimationGroup(Sub(animation)
              animation.duration = 0.2
              _hudLabel.animator().alphaValue = 0.0
            End Sub,
            completionHandler: Null)
          End If
        End Sub)
    End Sub

    Private Sub stopHudFadeTimer()
      If _hudFadeTimer IsNot Null Then
        _hudFadeTimer.invalidate()
        _hudFadeTimer = Null
      End If
    End Sub

    Private Sub workspaceDismissRequested()
      requestDismissal()
    End Sub

    Private Sub beginObservingDisplayForWindow(window As NSWindow, displayId targetDisplayId As String)
      Dim center As NSNotificationCenter = NSNotificationCenter.defaultCenter()
      _screenObserver = center.addObserverForName(NSApplicationDidChangeScreenParametersNotification,
        [object]: Null,
        queue: NSOperationQueue.mainQueue(),
        usingBlock: Sub(notification)
          checkTargetDisplayAvailability()
        End Sub)
      _windowCloseObserver = center.addObserverForName(NSWindowWillCloseNotification,
        [object]: window,
        queue: NSOperationQueue.mainQueue(),
        usingBlock: Sub(notification)
          If Not _isDismissing Then
            requestDismissal()
          End If
        End Sub)
    End Sub

    Private Sub stopObservingDisplayChanges()
      Dim center As NSNotificationCenter = NSNotificationCenter.defaultCenter()
      If _screenObserver IsNot Null Then
        center.removeObserver(_screenObserver)
        _screenObserver = Null
      End If

      If _windowCloseObserver IsNot Null Then
        center.removeObserver(_windowCloseObserver)
        _windowCloseObserver = Null
      End If
    End Sub

    Private Sub checkTargetDisplayAvailability()
      If _targetDisplayId Is Null OrElse _didRequestDisplayDismissal Then
        Exit Sub
      End If

      If screenWithIdentifier(_targetDisplayId) IsNot Null Then
        Exit Sub
      End If

      _didRequestDisplayDismissal = True
      Dim disconnectListener As WorkspaceSurfaceRequested = TargetDisplayDisconnected()
      If assigned(disconnectListener) Then
        disconnectListener()
      End If
    End Sub

    Private Function screenWithIdentifier(displayId As String) As NSScreen
      If displayId Is Null Then
        Return Null
      End If

      For Each screen As NSScreen In NSScreen.screens
        If identifierForScreen(screen) = displayId Then
          Return screen
        End If
      Next

      Return Null
    End Function

    Private Function identifierForScreen(screen As NSScreen) As String
      Dim displayNumber As NSNumber = TryCast(screen.deviceDescription.objectForKey("NSScreenNumber"), NSNumber)
      If displayNumber Is Null Then
        Return Null
      End If

      Return displayNumber.stringValue
    End Function

    Private Function failedPresentationWithMessage(message As String) As WorkspacePresentationResult
      Return WorkspacePresentationResult.failedWithFailure(New WorkspaceFailure(WorkspaceFailureCode.PresentationFailed,
        message: message))
    End Function

    Private Sub releaseOwnedFrame()
      If _ownedFrame IsNot Null Then
        _ownedFrame.releaseFrame()
        _ownedFrame = Null
      End If
    End Sub

    Private Sub clearPresentationWithoutReleasingFrame()
      _window = Null
      _imageView = Null
      _hudLabel = Null
      _ownedFrame = Null
      _targetDisplayId = Null
      _didRequestDisplayDismissal = False
    End Sub

    Private Sub requestDismissal()
      Dim dismissListener As WorkspaceSurfaceRequested = DismissRequested()
      If assigned(dismissListener) Then
        dismissListener()
      End If
    End Sub

  End Class

End Namespace
