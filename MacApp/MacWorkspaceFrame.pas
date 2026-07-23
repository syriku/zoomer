namespace MacApp;

uses
  AppKit,
  RemObjects.Elements.RTL,
  Core;

type
  // NSImage keeps the captured CGImage alive after ScreenCaptureKit returns.
  // Shared owns this wrapper until presentFrame succeeds; the surface releases it.
  MacWorkspaceFrame = public class(IWorkspaceFrame)
  private
    fImage: NSImage;
    method getIsReleased: Boolean;
    begin
      result := fImage = nil;
    end;
  public
    constructor(image: NSImage);
    begin
      if image = nil then
        raise new ArgumentNullException('image');

      fImage := image;
    end;
    property IsReleased: Boolean read getIsReleased;
    method imageForPresentation: NSImage;
    begin
      result := fImage;
    end;
    method releaseFrame;
    begin
      fImage := nil;
    end;
  end;

end.
