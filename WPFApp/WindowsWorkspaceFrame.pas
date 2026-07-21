namespace WPFApp;

interface

uses
  System,
  System.Windows.Media.Imaging,
  Core;

type
  // Shared owns this wrapper until presentFrame succeeds. The WPF surface then
  // owns it and clears the BitmapSource when the presentation is dismissed.
  WindowsWorkspaceFrame = public class(IWorkspaceFrame)
  private
    fSource: BitmapSource;
    method get_IsReleased: Boolean;
  public
    constructor(source: BitmapSource);
    property IsReleased: Boolean read get_IsReleased;
    method sourceForPresentation: BitmapSource;
    method releaseFrame;
  end;

implementation

constructor WindowsWorkspaceFrame(source: BitmapSource);
begin
  if not assigned(source) then
    raise new ArgumentNullException('source');
  fSource := source;
end;

method WindowsWorkspaceFrame.get_IsReleased: Boolean;
begin
  result := not assigned(fSource);
end;

method WindowsWorkspaceFrame.sourceForPresentation: BitmapSource;
begin
  result := fSource;
end;

method WindowsWorkspaceFrame.releaseFrame;
begin
  fSource := nil;
end;

end.
