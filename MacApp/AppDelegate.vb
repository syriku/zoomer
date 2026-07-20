Imports AppKit

<NSApplicationMain> <IBObject>
Class AppDelegate
  Inherits INSApplicationDelegate

  Public Property mainWindowController As MainWindowController

  Public Sub applicationDidFinishLaunching(notification As NSNotification)
    mainWindowController = New MainWindowController()
    mainWindowController.showWindow(Nothing)
  End Sub

End Class