Imports AppKit

<IBObject>
Public Class MainWindowController
  Inherits NSWindowController

  Public Sub New()
    MyBase.New(WindowNibName: "MainWindowController")
    '  Custom initialization
  End Sub

  Public Overrides Sub windowDidLoad()
    MyBase.windowDidLoad()
    '  Implement this method to handle any initialization after your window controller's
    '  window has been loaded from its nib file.
  End Sub

End Class