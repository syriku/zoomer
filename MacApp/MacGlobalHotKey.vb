Imports Carbon.HIToolbox
Imports Foundation
Imports RemObjects.Elements.System

Public Delegate Sub MacGlobalHotKeyTriggered()

Public Function handleMacGlobalHotKeyEvent(nextHandler As EventHandlerCallRef, eventReference As EventRef, context As Ptr(Of Void)) As OSStatus
  NSLog("Zoomer: Carbon received ⌥⌘Z")
  MacGlobalHotKey.dispatchHotKeyEvent()
  Return noErr
End Function

Public Class MacGlobalHotKey
  Private Const ZoomerSignature As UInt32 = &H5A4D524B
  Private Const ZoomerHotKeyId As UInt32 = 1
  Private Const ZKeyCode As UInt32 = 6

  Private Shared _activeRegistration As MacGlobalHotKey

  Private _hotKey As EventHotKeyRef
  Private _eventHandler As EventHandlerRef
  Private _eventHandlerCallback As EventHandlerUPP
  Private _registrationStatus As OSStatus = noErr

  Public Property Triggered As MacGlobalHotKeyTriggered

  Public ReadOnly Property RegistrationStatus As OSStatus
    Get
      Return _registrationStatus
    End Get
  End Property

  Public Function registerHotKey() As Boolean
    If assigned(_hotKey) Then
      Return True
    End If

    Dim eventType As EventTypeSpec
    eventType.eventClass = kEventClassKeyboard
    eventType.eventKind = kEventHotKeyPressed
    ' NSApplication owns and drives the application event target. The dispatcher
    ' target is intended for applications that dispatch Carbon events themselves.
    Dim eventTarget As EventTargetRef = GetApplicationEventTarget()
    If Not assigned(eventTarget) Then
      _registrationStatus = -1
      Return False
    End If

    _eventHandlerCallback = AddressOf Global.MacApp.handleMacGlobalHotKeyEvent
    If Not assigned(_eventHandlerCallback) Then
      _registrationStatus = -1
      Return False
    End If

    ' InstallApplicationEventHandler is a C macro and is not exported by the
    ' Elements SDK; this is its exact expansion.
    Dim installStatus As OSStatus = Carbon.HIToolbox.InstallEventHandler(eventTarget,
    _eventHandlerCallback,
    1,
    AddressOf eventType,
    Null,
    AddressOf _eventHandler)
    NSLog("Zoomer: InstallEventHandler status %d", installStatus)
    If installStatus <> noErr Then
      _registrationStatus = installStatus
      releaseEventHandlerCallback()
      Return False
    End If

    Dim identifier As EventHotKeyID
    identifier.signature = ZoomerSignature
    identifier.id = ZoomerHotKeyId
    Dim registerStatus As OSStatus = Carbon.HIToolbox.RegisterEventHotKey(ZKeyCode,
    optionKey Or cmdKey,
    identifier,
    eventTarget,
    0,
    AddressOf _hotKey)
    NSLog("Zoomer: RegisterEventHotKey ⌥⌘Z status %d", registerStatus)
    If registerStatus <> noErr Then
      _registrationStatus = registerStatus
      Carbon.HIToolbox.RemoveEventHandler(_eventHandler)
      _eventHandler = Nothing
      releaseEventHandlerCallback()
      Return False
    End If

    _activeRegistration = Me
    _registrationStatus = noErr
    Return True
  End Function

  Public Sub unregisterHotKey()
    If assigned(_hotKey) Then
      Carbon.HIToolbox.UnregisterEventHotKey(_hotKey)
      _hotKey = Nothing
    End If

    If assigned(_eventHandler) Then
      Carbon.HIToolbox.RemoveEventHandler(_eventHandler)
      _eventHandler = Nothing
    End If
    releaseEventHandlerCallback()

    If _activeRegistration Is Me Then
      _activeRegistration = Null
    End If
  End Sub

  Friend Shared Sub dispatchHotKeyEvent()
    Dim registration As MacGlobalHotKey = _activeRegistration
    If registration IsNot Null Then
      NSLog("Zoomer: dispatching ⌥⌘Z")
      NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
        registration.notifyTriggered()
      End Sub)
    Else
      NSLog("Zoomer: ⌥⌘Z arrived without an active registration")
    End If
  End Sub

  Private Sub notifyTriggered()
    Dim listener As MacGlobalHotKeyTriggered = Triggered()
    If assigned(listener) Then
      NSLog("Zoomer: invoking ⌥⌘Z listener")
      listener()
    Else
      NSLog("Zoomer: ⌥⌘Z listener is missing")
    End If
  End Sub

  Private Sub releaseEventHandlerCallback()
    If assigned(_eventHandlerCallback) Then
      _eventHandlerCallback = Nothing
    End If
  End Sub

End Class