namespace WPFApp;

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
    begin
      result := not assigned(fSource);
    end;
  public
    constructor(source: BitmapSource);
    begin
      if not assigned(source) then
        raise new ArgumentNullException('source');
      fSource := source;
    end;
    property IsReleased: Boolean read get_IsReleased;
    method sourceForPresentation: BitmapSource;
    begin
      result := fSource;
    end;
    method releaseFrame;
    begin
      fSource := nil;
    end;
  end;

end.
