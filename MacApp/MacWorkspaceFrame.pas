namespace MacApp;

interface

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
  public
    constructor(image: NSImage);
    property IsReleased: Boolean read getIsReleased;
    method imageForPresentation: NSImage;
    method releaseFrame;
  end;

implementation

constructor MacWorkspaceFrame(image: NSImage);
begin
  if image = nil then
    raise new ArgumentNullException('image');

  fImage := image;
end;

method MacWorkspaceFrame.getIsReleased: Boolean;
begin
  result := fImage = nil;
end;

method MacWorkspaceFrame.imageForPresentation: NSImage;
begin
  result := fImage;
end;

method MacWorkspaceFrame.releaseFrame;
begin
  fImage := nil;
end;

end.
