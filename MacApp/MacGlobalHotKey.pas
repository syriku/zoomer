namespace MacApp;

interface

uses
  Carbon.HIToolbox,
  Foundation;

{$GLOBALS ON}

method handleMacGlobalHotKeyEvent(nextHandler: EventHandlerCallRef)
  eventReference(eventReference: EventRef)
  context(context: ^Void): OSStatus;

type
  MacGlobalHotKeyTriggered = public block;

  MacGlobalHotKey = public class
  private
    const
      ZoomerSignature: UInt32 = $5A4D524B;
      ZoomerHotKeyId: UInt32 = 1;
      ZKeyCode: UInt32 = kVK_ANSI_Z;
      // Older SDK imports reverse kEventClassKeyboard. Keep the native 'keyb'
      // FourCC until all supported Elements SDK metadata contains the fix.
      KeyboardEventClass: UInt32 = $6B657962;

    class var fActiveRegistration: MacGlobalHotKey;
    var fHotKey: EventHotKeyRef;
    var fEventHandler: EventHandlerRef;
    var fEventHandlerCallback: EventHandlerUPP;
    var fRegistrationVersion: Int64;
    var fRegistrationStatus: OSStatus := noErr;
    var fTriggered: MacGlobalHotKeyTriggered;

    class method installCarbonEventHandlerOnTarget(eventTarget: EventTargetRef)
      callback(eventHandlerCallback: EventHandlerUPP)
      eventType(eventType: ^EventTypeSpec)
      userData(userData: ^Void)
      eventHandlerReference(var eventHandler: EventHandlerRef): OSStatus;
    class method registerCarbonHotKeyWithCode(keyCode: UInt32)
      modifiers(modifiers: UInt32)
      identifier(identifier: EventHotKeyID)
      onTarget(eventTarget: EventTargetRef)
      options(options: UInt32)
      hotKeyReference(var hotKey: EventHotKeyRef): OSStatus;
    method removeInstalledEventHandler: OSStatus;
    method notifyTriggered;
  public
    property Triggered: MacGlobalHotKeyTriggered read fTriggered write fTriggered;
    property RegistrationStatus: OSStatus read fRegistrationStatus;

    method registerHotKey: Boolean;
    method unregisterHotKey;
  assembly
    class method dispatchHotKeyEvent;
  end;

implementation

method handleMacGlobalHotKeyEvent(nextHandler: EventHandlerCallRef)
  eventReference(eventReference: EventRef)
  context(context: ^Void): OSStatus;
begin
  MacGlobalHotKey.dispatchHotKeyEvent;
  result := noErr;
end;

method MacGlobalHotKey.registerHotKey: Boolean;
begin
  if assigned(fHotKey) then
    exit true;

  if assigned(fEventHandler) then begin
    unregisterHotKey;
    if assigned(fEventHandler) then
      exit false;
  end;

  var eventTarget := Carbon.HIToolbox.GetApplicationEventTarget;
  if not assigned(eventTarget) then begin
    fRegistrationStatus := -1;
    exit false;
  end;

  var eventType: EventTypeSpec;
  eventType.eventClass := KeyboardEventClass;
  eventType.eventKind := kEventHotKeyPressed;

  fEventHandlerCallback := @handleMacGlobalHotKeyEvent;
  if not assigned(fEventHandlerCallback) then begin
    fRegistrationStatus := -1;
    exit false;
  end;

  var installStatus := installCarbonEventHandlerOnTarget(eventTarget)
    callback(fEventHandlerCallback)
    eventType(@eventType)
    userData(nil)
    eventHandlerReference(var fEventHandler);
  if installStatus <> noErr then begin
    fRegistrationStatus := installStatus;
    fEventHandlerCallback := nil;
    exit false;
  end;

  var identifier: EventHotKeyID;
  identifier.signature := ZoomerSignature;
  identifier.id := ZoomerHotKeyId;

  var registerStatus := registerCarbonHotKeyWithCode(ZKeyCode)
    modifiers(optionKey or cmdKey)
    identifier(identifier)
    onTarget(eventTarget)
    options(0)
    hotKeyReference(var fHotKey);
  if registerStatus <> noErr then begin
    fRegistrationStatus := registerStatus;
    var cleanupStatus := removeInstalledEventHandler;
    if cleanupStatus <> noErr then
      NSLog('Zoomer: RemoveEventHandler after a hot-key registration failure returned %d', cleanupStatus);
    exit false;
  end;

  fRegistrationVersion := fRegistrationVersion + 1;
  fActiveRegistration := self;
  fRegistrationStatus := noErr;
  result := true;
end;

method MacGlobalHotKey.unregisterHotKey;
begin
  if assigned(fHotKey) then begin
    var unregisterStatus := Carbon.HIToolbox.UnregisterEventHotKey(fHotKey);
    if unregisterStatus <> noErr then begin
      fRegistrationStatus := unregisterStatus;
      NSLog('Zoomer: UnregisterEventHotKey returned %d', unregisterStatus);
      exit;
    end;
    fHotKey := nil;
  end;

  if fActiveRegistration = self then
    fActiveRegistration := nil;

  var removeStatus := removeInstalledEventHandler;
  if removeStatus <> noErr then begin
    fRegistrationStatus := removeStatus;
    NSLog('Zoomer: RemoveEventHandler returned %d', removeStatus);
  end;
end;

class method MacGlobalHotKey.installCarbonEventHandlerOnTarget(eventTarget: EventTargetRef)
  callback(eventHandlerCallback: EventHandlerUPP)
  eventType(eventType: ^EventTypeSpec)
  userData(userData: ^Void)
  eventHandlerReference(var eventHandler: EventHandlerRef): OSStatus;
begin
  // Carbon's generated C imports have positional parameters. Keep that ABI-only
  // call at this boundary; the rest of MacApp uses selector-shaped APIs.
  result := Carbon.HIToolbox.InstallEventHandler(eventTarget, eventHandlerCallback, 1, eventType, userData, @eventHandler);
end;

class method MacGlobalHotKey.registerCarbonHotKeyWithCode(keyCode: UInt32)
  modifiers(modifiers: UInt32)
  identifier(identifier: EventHotKeyID)
  onTarget(eventTarget: EventTargetRef)
  options(options: UInt32)
  hotKeyReference(var hotKey: EventHotKeyRef): OSStatus;
begin
  result := Carbon.HIToolbox.RegisterEventHotKey(keyCode, modifiers, identifier, eventTarget, options, @hotKey);
end;

method MacGlobalHotKey.removeInstalledEventHandler: OSStatus;
begin
  if not assigned(fEventHandler) then begin
    fEventHandlerCallback := nil;
    exit noErr;
  end;

  result := Carbon.HIToolbox.RemoveEventHandler(fEventHandler);
  if result = noErr then begin
    fEventHandler := nil;
    fEventHandlerCallback := nil;
  end;
end;

class method MacGlobalHotKey.dispatchHotKeyEvent;
begin
  var registration := fActiveRegistration;
  if registration = nil then
    exit;

  var registrationVersion := registration.fRegistrationVersion;

  NSOperationQueue.mainQueue.addOperationWithBlock(method
    begin
      if (fActiveRegistration <> registration) or (registration.fRegistrationVersion <> registrationVersion) then
        exit;
      registration.notifyTriggered;
    end);
end;

method MacGlobalHotKey.notifyTriggered;
begin
  var listener := fTriggered;
  if assigned(listener) then
    listener();
end;

end.
