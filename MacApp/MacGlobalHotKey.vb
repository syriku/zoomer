Imports Carbon.HIToolbox
Imports Foundation

Namespace Application

  Public Delegate Sub MacGlobalHotKeyTriggered()

  Public Function handleMacGlobalHotKeyEvent(nextHandler As EventHandlerCallRef, eventReference eventReference As EventRef, context context As Ptr(Of Void)) As OSStatus
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

    Public Property Triggered As MacGlobalHotKeyTriggered

    Public Function registerHotKey() As Boolean
      If assigned(_hotKey) Then
        Return True
      End If

      Dim eventType As EventTypeSpec
      eventType.eventClass = kEventClassKeyboard
      eventType.eventKind = kEventHotKeyPressed

      Dim installStatus As OSStatus = Carbon.HIToolbox.InstallEventHandler(GetApplicationEventTarget(),
        AddressOf Global.MacApp.Application.handleMacGlobalHotKeyEvent,
        1,
        AddressOf eventType,
        Null,
        AddressOf _eventHandler)
      If installStatus <> noErr Then
        Return False
      End If

      Dim identifier As EventHotKeyID
      identifier.signature = ZoomerSignature
      identifier.id = ZoomerHotKeyId
      Dim registerStatus As OSStatus = Carbon.HIToolbox.RegisterEventHotKey(ZKeyCode,
        optionKey Or cmdKey,
        identifier,
        GetApplicationEventTarget(),
        0,
        AddressOf _hotKey)
      If registerStatus <> noErr Then
        Carbon.HIToolbox.RemoveEventHandler(_eventHandler)
        _eventHandler = Nothing
        Return False
      End If

      _activeRegistration = Me
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

      If _activeRegistration Is Me Then
        _activeRegistration = Null
      End If
    End Sub

    Friend Shared Sub dispatchHotKeyEvent()
      Dim registration As MacGlobalHotKey = _activeRegistration
      If registration IsNot Null Then
        NSOperationQueue.mainQueue().addOperationWithBlock(Sub()
          registration.notifyTriggered()
        End Sub)
      End If
    End Sub

    Private Sub notifyTriggered()
      Dim listener As MacGlobalHotKeyTriggered = Triggered()
      If assigned(listener) Then
        listener()
      End If
    End Sub

  End Class

End Namespace
