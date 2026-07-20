Imports AppKit
Imports Foundation

Namespace Application

  Public Class MacWorkspaceWindow
    Inherits NSWindow

    Public Sub New(contentRect As NSRect, styleMask windowStyle As NSWindowStyleMask, backing backingStore As NSBackingStoreType, defer shouldDefer As Boolean, screen targetScreen As NSScreen)
      MyBase.New(ContentRect: contentRect,
        styleMask: windowStyle,
        backing: backingStore,
        defer: shouldDefer,
        screen: targetScreen)
    End Sub

    Public Overrides Function canBecomeKeyWindow() As Boolean
      Return True
    End Function

    Public Overrides Function canBecomeMainWindow() As Boolean
      Return True
    End Function

  End Class

End Namespace
