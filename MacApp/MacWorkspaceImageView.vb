Imports AppKit
Imports Foundation
Imports [Shared].Core

Namespace Application

  Public Class MacWorkspaceImageView
    Inherits NSImageView

    Public Property CommandRequested As WorkspaceCommandRequested
    Public Property DismissRequested As WorkspaceSurfaceRequested

    Private _previousDragPoint As NSPoint
    Private _hasPreviousDragPoint As Boolean

    Public Overrides Function acceptsFirstResponder() As Boolean
      Return True
    End Function

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
      If nativeEvent.isARepeat Then
        MyBase.keyDown(nativeEvent)
        Exit Sub
      End If

      Dim anchor As NSPoint = pointForEvent(nativeEvent)
      Select Case nativeEvent.keyCode
        Case 53
          requestDismissal()
          Exit Sub

        Case 29, 82
          requestCommand(WorkspaceCommand.resetScale())
          Exit Sub

        Case 15
          requestCommand(WorkspaceCommand.resetWorkspace())
          Exit Sub

        Case 8
          requestCommand(WorkspaceCommand.centerInViewport(bounds.size.width,
            height: bounds.size.height))
          Exit Sub

        Case 18, 83
          sendPresetScale(1.5, atPoint: anchor)
          Exit Sub

        Case 19, 84
          sendPresetScale(2.0, atPoint: anchor)
          Exit Sub

        Case 25, 92
          sendPresetScale(0.7, atPoint: anchor)
          Exit Sub

        Case 46
          requestCommand(WorkspaceCommand.toggleHorizontalFlip())
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

End Namespace
