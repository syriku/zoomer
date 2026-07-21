namespace MacApp;

interface

uses
  AppKit,
  Foundation;

type
  MacWorkspaceWindow = public class(NSWindow)
  public
    constructor withContentRect(contentRect: NSRect) styleMask(windowStyle: NSWindowStyleMask) backing(backingStore: NSBackingStoreType) defer(shouldDefer: Boolean) screen(targetScreen: NSScreen);
    method canBecomeKeyWindow: Boolean; override;
    method canBecomeMainWindow: Boolean; override;
  end;

implementation

constructor MacWorkspaceWindow withContentRect(contentRect: NSRect) styleMask(windowStyle: NSWindowStyleMask) backing(backingStore: NSBackingStoreType) defer(shouldDefer: Boolean) screen(targetScreen: NSScreen);
begin
  inherited constructor withContentRect(contentRect) styleMask(windowStyle) backing(backingStore) defer(shouldDefer) screen(targetScreen);
end;

method MacWorkspaceWindow.canBecomeKeyWindow: Boolean;
begin
  result := true;
end;

method MacWorkspaceWindow.canBecomeMainWindow: Boolean;
begin
  result := true;
end;

end.
