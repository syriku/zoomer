namespace MacApp;

uses
  AppKit,
  Foundation;

type
  MacWorkspaceWindow = public class(NSWindow)
  public
    constructor withContentRect(contentRect: NSRect) styleMask(windowStyle: NSWindowStyleMask) backing(backingStore: NSBackingStoreType) defer(shouldDefer: Boolean) screen(targetScreen: NSScreen);
    begin
      inherited constructor withContentRect(contentRect) styleMask(windowStyle) backing(backingStore) defer(shouldDefer) screen(targetScreen);
    end;
    method canBecomeKeyWindow: Boolean; override;
    begin
      result := true;
    end;
    method canBecomeMainWindow: Boolean; override;
    begin
      result := true;
    end;
  end;

end.
