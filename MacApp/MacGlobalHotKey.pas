namespace MacApp;

interface

uses
  Carbon.HIToolbox,
  CoreGraphics,
  Foundation;

type
  MacGlobalHotKeyTriggered = public block;

  MacGlobalHotKey = public class
  private
    const
      PollingIntervalSeconds: Double = 0.05;
      ZKeyCode: UInt32 = kVK_ANSI_Z;

    var fTimer: NSTimer;
    var fIsHotKeyDown: Boolean;
    var fRegistrationStatus: OSStatus := noErr;
    var fTriggered: MacGlobalHotKeyTriggered;

    method pollHotKeyState;
    method dispatchHotKeyEvent;
    method notifyTriggered;
  public
    property Triggered: MacGlobalHotKeyTriggered read fTriggered write fTriggered;
    property RegistrationStatus: OSStatus read fRegistrationStatus;

    method registerHotKey: Boolean;
    method unregisterHotKey;
  end;

implementation

method MacGlobalHotKey.registerHotKey: Boolean;
begin
  if assigned(fTimer) then
    exit true;

  fTimer := NSTimer.scheduledTimerWithTimeInterval(PollingIntervalSeconds) repeats(true) &block(method(aTimer: NSTimer)
    begin
      pollHotKeyState;
    end);

  if not assigned(fTimer) then begin
    fRegistrationStatus := -1;
    exit false;
  end;

  fRegistrationStatus := noErr;
  result := true;
end;

method MacGlobalHotKey.unregisterHotKey;
begin
  if assigned(fTimer) then begin
    fTimer.invalidate;
    fTimer := nil;
  end;
  fIsHotKeyDown := false;
end;

method MacGlobalHotKey.pollHotKeyState;
begin
  var zDown: Boolean := CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, ZKeyCode);
  var commandDown: Boolean := CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_Command) or
    CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_RightCommand);
  var optionDown: Boolean := CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_Option) or
    CGEventSourceKeyState(CGEventSourceStateID.HIDSystemState, kVK_RightOption);
  var hotKeyDown: Boolean := zDown and commandDown and optionDown;

  if hotKeyDown and not fIsHotKeyDown then
    dispatchHotKeyEvent;
  fIsHotKeyDown := hotKeyDown;
end;

method MacGlobalHotKey.dispatchHotKeyEvent;
begin
  NSOperationQueue.mainQueue.addOperationWithBlock(method
    begin
      notifyTriggered;
    end);
end;

method MacGlobalHotKey.notifyTriggered;
begin
  var listener := fTriggered;
  if assigned(listener) then
    listener();
end;

end.
