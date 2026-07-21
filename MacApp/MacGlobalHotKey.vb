Imports Carbon.HIToolbox
Imports CoreGraphics
Imports Foundation

Public Delegate Sub MacGlobalHotKeyTriggered()

Public Class MacGlobalHotKey
  Private Const PollingIntervalSeconds As Double = 0.05
  Private Const ZKeyCode As UInt32 = kVK_ANSI_Z

  Private _timer As NSTimer
  Private _isHotKeyDown As Boolean
  Private _registrationStatus As OSStatus = noErr

  Public Property Triggered As MacGlobalHotKeyTriggered

  Public ReadOnly Property RegistrationStatus As OSStatus
    Get
      Return _registrationStatus
    End Get
  End Property

  Public Function registerHotKey() As Boolean
    If assigned(_timer) Then
      Return True
    End If

    _timer = NSTimer.scheduledTimerWithTimeInterval(PollingIntervalSeconds,
    repeats: True,
    block: Sub(timer)
      pollHotKeyState()
    End Sub)

    If Not assigned(_timer) Then
      _registrationStatus = -1
      Return False
    End If

    _registrationStatus = noErr
    Return True
  End Function

  Public Sub unregisterHotKey()
    If assigned(_timer) Then
      _timer.invalidate()
      _timer = Nothing
    End If
    _isHotKeyDown = False
  End Sub

  Private Sub pollHotKeyState()
    Dim zDown As Boolean = CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, ZKeyCode)
    Dim commandDown As Boolean = CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_Command) OrElse
    CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_RightCommand)
    Dim optionDown As Boolean = CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_Option) OrElse
    CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_RightOption)
    Dim hotKeyDown As Boolean = zDown AndAlso commandDown AndAlso optionDown

    If hotKeyDown AndAlso Not _isHotKeyDown Then
      dispatchHotKeyEvent()
    End If
    _isHotKeyDown = hotKeyDown
  End Sub

  Private Sub dispatchHotKeyEvent()
    NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
      notifyTriggered()
    End Sub)
  End Sub

  Private Sub notifyTriggered()
    Dim listener As MacGlobalHotKeyTriggered = Triggered()
    If assigned(listener) Then
      listener()
    End If
  End Sub

End Class
