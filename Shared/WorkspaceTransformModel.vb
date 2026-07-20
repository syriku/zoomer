Imports RemObjects.Elements.RTL

Namespace Core

  Public Class WorkspaceTransformModel
    Public Const MinimumScale As Double = 0.1
    Public Const MaximumScale As Double = 16.0

    Private _transform As WorkspaceTransform = WorkspaceTransform.identityTransform()

    Public Property Transform As WorkspaceTransform
      Get
        Return _transform
      End Get
    End Property

    Public Function zoomByScrollDelta(delta As Double, atX anchorX As Double, atY anchorY As Double) As Boolean
      If Not isFinite(delta) Then
        Return False
      End If

      Return zoomByFactor(Math.Exp(delta * 0.025), atX: anchorX, atY: anchorY)
    End Function

    Public Function zoomByMagnification(magnification As Double, atX anchorX As Double, atY anchorY As Double) As Boolean
      If Not isFinite(magnification) Then
        Return False
      End If

      Return zoomToScale(_transform.Scale() + magnification, atX: anchorX, atY: anchorY)
    End Function

    Public Function zoomByFactor(factor As Double, atX anchorX As Double, atY anchorY As Double) As Boolean
      If Not isFinite(factor) OrElse factor <= 0.0 Then
        Return False
      End If

      Return zoomToScale(_transform.Scale() * factor, atX: anchorX, atY: anchorY)
    End Function

    Public Function setPresetScale(scale As Double, atX anchorX As Double, atY anchorY As Double) As Boolean
      Return zoomToScale(scale, atX: anchorX, atY: anchorY)
    End Function

    Public Function translateBy(deltaX As Double, deltaY y As Double) As Boolean
      If Not isFinite(deltaX) OrElse Not isFinite(y) OrElse (deltaX = 0.0 AndAlso y = 0.0) Then
        Return False
      End If

      Dim current = _transform
      _transform = New WorkspaceTransform(current.Scale(),
        offsetX: current.OffsetX() + deltaX,
        offsetY: current.OffsetY() + y,
        horizontallyFlipped: current.IsHorizontallyFlipped())
      Return True
    End Function

    Public Function resetScale() As Boolean
      Dim current = _transform
      If current.Scale() = 1.0 Then
        Return False
      End If

      _transform = New WorkspaceTransform(1.0,
        offsetX: current.OffsetX(),
        offsetY: current.OffsetY(),
        horizontallyFlipped: current.IsHorizontallyFlipped())
      Return True
    End Function

    Public Function resetTransform() As Boolean
      Dim current = _transform
      If current.Scale() = 1.0 AndAlso current.OffsetX() = 0.0 AndAlso current.OffsetY() = 0.0 AndAlso Not current.IsHorizontallyFlipped() Then
        Return False
      End If

      _transform = WorkspaceTransform.identityTransform()
      Return True
    End Function

    Public Function centerInViewport(width As Double, height viewportHeight As Double) As Boolean
      If Not isFinite(width) OrElse Not isFinite(viewportHeight) OrElse width < 0.0 OrElse viewportHeight < 0.0 Then
        Return False
      End If

      Dim current = _transform
      Dim offsetX = (width - (width * current.Scale())) / 2.0
      Dim offsetY = (viewportHeight - (viewportHeight * current.Scale())) / 2.0
      If offsetX = current.OffsetX() AndAlso offsetY = current.OffsetY() Then
        Return False
      End If

      _transform = New WorkspaceTransform(current.Scale(),
        offsetX: offsetX,
        offsetY: offsetY,
        horizontallyFlipped: current.IsHorizontallyFlipped())
      Return True
    End Function

    Public Sub toggleHorizontalFlip()
      Dim current = _transform
      _transform = New WorkspaceTransform(current.Scale(),
        offsetX: current.OffsetX(),
        offsetY: current.OffsetY(),
        horizontallyFlipped: Not current.IsHorizontallyFlipped())
    End Sub

    Private Function zoomToScale(requestedScale As Double, atX anchorX As Double, atY anchorY As Double) As Boolean
      If Not isFinite(requestedScale) OrElse Not isFinite(anchorX) OrElse Not isFinite(anchorY) Then
        Return False
      End If

      Dim current = _transform
      Dim nextScale = clampScale(requestedScale)
      If nextScale = current.Scale() Then
        Return False
      End If

      Dim ratio = nextScale / current.Scale()
      _transform = New WorkspaceTransform(nextScale,
        offsetX: anchorX - ((anchorX - current.OffsetX()) * ratio),
        offsetY: anchorY - ((anchorY - current.OffsetY()) * ratio),
        horizontallyFlipped: current.IsHorizontallyFlipped())
      Return True
    End Function

    Private Function clampScale(value As Double) As Double
      If value < MinimumScale Then
        Return MinimumScale
      End If

      If value > MaximumScale Then
        Return MaximumScale
      End If

      Return value
    End Function

    Private Function isFinite(value As Double) As Boolean
      Return value = value AndAlso value > -1.7976931348623157E+308 AndAlso value < 1.7976931348623157E+308
    End Function
  End Class

End Namespace
