Imports AppKit
Imports CoreGraphics
Imports Foundation
Imports Core

Public Class MacWorkspaceImageView
  Inherits NSView

  Public Property CommandRequested As WorkspaceCommandRequested
  Public Property DismissRequested As WorkspaceSurfaceRequested

  Private _previousDragPoint As NSPoint
  Private _hasPreviousDragPoint As Boolean
  Private _image As NSImage
  Private _transform As WorkspaceTransform = WorkspaceTransform.identityTransform()

  Public Property Image As NSImage
    Get
      Return _image
    End Get
    Set(value As NSImage)
      _image = value
      needsDisplay = True
    End Set
  End Property

  Public Overrides Function acceptsFirstResponder() As Boolean
    Return True
  End Function

  Public Sub renderTransform(transform As WorkspaceTransform)
    If transform Is Null Then
      Exit Sub
    End If

    _transform = transform
    needsDisplay = True
  End Sub

  Public Overrides Sub drawRect(dirtyRect As NSRect)
    NSColor.blackColor().setFill()
    NSRectFill(bounds)
    If _image Is Null Then
      Exit Sub
    End If

    Dim destination As NSRect = NSMakeRect(_transform.OffsetX(),
    _transform.OffsetY(),
    bounds.size.width * _transform.Scale(),
    bounds.size.height * _transform.Scale())
    Dim graphicsContext As NSGraphicsContext = NSGraphicsContext.currentContext()
    If graphicsContext IsNot Null Then
      CGContextSetInterpolationQuality(graphicsContext.CGContext, CGInterpolationQuality.High)
    End If

    If _transform.IsHorizontallyFlipped() AndAlso graphicsContext IsNot Null Then
      CGContextSaveGState(graphicsContext.CGContext)
      CGContextTranslateCTM(graphicsContext.CGContext, NSMinX(destination) + NSMaxX(destination), 0.0)
      CGContextScaleCTM(graphicsContext.CGContext, -1.0, 1.0)
    End If

    _image.drawInRect(destination,
    fromRect: NSZeroRect,
    operation: NSCompositingOperation.Copy,
    fraction: 1.0,
    respectFlipped: False,
    hints: Null)

    If _transform.IsHorizontallyFlipped() AndAlso graphicsContext IsNot Null Then
      CGContextRestoreGState(graphicsContext.CGContext)
    End If
  End Sub

  Public Overrides Sub mouseDown(nativeEvent As NSEvent)
    _previousDragPoint = pointForEvent(nativeEvent)
    _hasPreviousDragPoint = True
    NSCursor.closedHandCursor().set()
  End Sub

  Public Overrides Sub mouseDragged(nativeEvent As NSEvent)
    Dim point As NSPoint = pointForEvent(nativeEvent)
    If Not _hasPreviousDragPoint Then
      _previousDragPoint = point
      _hasPreviousDragPoint = True
      Exit Sub
    End If

    Dim deltaX As Double = point.x - _previousDragPoint.x
    Dim deltaY As Double = point.y - _previousDragPoint.y
    _previousDragPoint = point
    If deltaX <> 0.0 OrElse deltaY <> 0.0 Then
      requestCommand(WorkspaceCommand.panWithDeltaX(deltaX, deltaY: deltaY))
    End If
  End Sub

  Public Overrides Sub mouseUp(nativeEvent As NSEvent)
    _hasPreviousDragPoint = False
    NSCursor.openHandCursor().set()
  End Sub

  Public Overrides Function resignFirstResponder() As Boolean
    _hasPreviousDragPoint = False
    NSCursor.arrowCursor().set()
    Return MyBase.resignFirstResponder()
  End Function

  Public Overrides Sub scrollWheel(nativeEvent As NSEvent)
    If nativeEvent.hasPreciseScrollingDeltas Then
      requestCommand(WorkspaceCommand.panWithDeltaX(nativeEvent.scrollingDeltaX,
      deltaY: -nativeEvent.scrollingDeltaY))
      Exit Sub
    End If

    Dim anchor As NSPoint = pointForEvent(nativeEvent)
    requestCommand(WorkspaceCommand.scrollZoomWithDelta(nativeEvent.scrollingDeltaY,
    atX: anchor.x,
    atY: anchor.y))
  End Sub

  Public Overrides Sub magnifyWithEvent(nativeEvent As NSEvent)
    Dim anchor As NSPoint = pointForEvent(nativeEvent)
    requestCommand(WorkspaceCommand.magnifyWithAmount(nativeEvent.magnification,
    atX: anchor.x,
    atY: anchor.y))
  End Sub

  Public Overrides Sub keyDown(nativeEvent As NSEvent)
    Dim modifiers As NSEventModifierFlags = nativeEvent.modifierFlags And
    (NSEventModifierFlags.NSCommandKeyMask Or NSEventModifierFlags.NSAlternateKeyMask Or
    NSEventModifierFlags.NSControlKeyMask Or NSEventModifierFlags.NSShiftKeyMask)
    Dim hasShortcutModifier As Boolean = modifiers <> 0
    Dim anchor As NSPoint = pointForEvent(nativeEvent)
    Select Case nativeEvent.keyCode
      Case 53
        requestDismissal()
        Exit Sub

      Case 29, 82
        If Not nativeEvent.isARepeat AndAlso
        (modifiers = 0 OrElse modifiers = NSEventModifierFlags.NSCommandKeyMask) Then
          requestCommand(WorkspaceCommand.resetScale())
          Exit Sub
        End If

      Case 15
        If Not nativeEvent.isARepeat AndAlso Not hasShortcutModifier Then
          requestCommand(WorkspaceCommand.resetWorkspace())
          Exit Sub
        End If

      Case 8
        If Not nativeEvent.isARepeat AndAlso Not hasShortcutModifier Then
          requestCommand(WorkspaceCommand.centerInViewport(bounds.size.width,
          height: bounds.size.height))
          Exit Sub
        End If

      Case 18, 83
        If Not nativeEvent.isARepeat AndAlso Not hasShortcutModifier Then
          sendPresetScale(1.5, atPoint: anchor)
          Exit Sub
        End If

      Case 19, 84
        If Not nativeEvent.isARepeat AndAlso Not hasShortcutModifier Then
          sendPresetScale(2.0, atPoint: anchor)
          Exit Sub
        End If

      Case 25, 92
        If Not nativeEvent.isARepeat AndAlso Not hasShortcutModifier Then
          sendPresetScale(0.7, atPoint: anchor)
          Exit Sub
        End If

      Case 46
        If Not nativeEvent.isARepeat Then
          requestCommand(WorkspaceCommand.toggleHorizontalFlip())
        End If
        Exit Sub
    End Select

    MyBase.keyDown(nativeEvent)
  End Sub

  Private Function pointForEvent(nativeEvent As NSEvent) As NSPoint
    Return convertPoint(nativeEvent.locationInWindow, fromView: Null)
  End Function

  Private Sub sendPresetScale(scale As Double, atPoint anchor As NSPoint)
    requestCommand(WorkspaceCommand.presetScaleAtAnchor(scale,
    atX: anchor.x,
    atY: anchor.y))
  End Sub

  Private Sub requestCommand(command As WorkspaceCommand)
    Dim commandListener As WorkspaceCommandRequested = CommandRequested()
    If assigned(commandListener) Then
      commandListener(command)
    End If
  End Sub

  Private Sub requestDismissal()
    Dim dismissListener As WorkspaceSurfaceRequested = DismissRequested()
    If assigned(dismissListener) Then
      dismissListener()
    End If
  End Sub

End Class