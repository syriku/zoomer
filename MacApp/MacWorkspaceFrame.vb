Imports AppKit
Imports RemObjects.Elements.RTL
Imports Core

  ' NSImage keeps the captured CGImage alive after ScreenCaptureKit returns.
  ' Shared owns this wrapper until presentFrame succeeds; the surface releases it.
Public Class MacWorkspaceFrame
  Implements IWorkspaceFrame

  Private _image As NSImage

  Public Sub New(image As NSImage)
    If image Is Null Then
      Throw New ArgumentNullException("image")
    End If

    _image = image
  End Sub

  Public ReadOnly Property IsReleased() As Boolean
    Get
      Return _image Is Null
    End Get
  End Property

  Public Function imageForPresentation() As NSImage
    Return _image
  End Function

  Public Sub releaseFrame()
    _image = Null
  End Sub

End Class