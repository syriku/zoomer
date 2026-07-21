namespace WPFApp;

interface

uses
  System,
  System.Windows,
  Core;

type
  App = public partial class(Application)
  private
    fPlatformActual: WindowsWorkspacePlatformActual;
    fWorkspaceSession: WorkspaceSession;
    fShellIntegration: WindowsShellIntegration;
    fIsShuttingDown: Boolean;

    method requestPresentation;
    method requestQuit;
    method workspaceStateDidChange(snapshot: WorkspaceStateSnapshot);
    method refreshShellState;
    method shutdownWorkspace;
  protected
    method OnStartup(e: StartupEventArgs); override;
    method OnExit(e: ExitEventArgs); override;
  end;

implementation

method App.OnStartup(e: StartupEventArgs);
begin
  WindowsNative.enablePerMonitorDpiAwareness;
  inherited OnStartup(e);

  fPlatformActual := new WindowsWorkspacePlatformActual(Dispatcher);
  WorkspaceActuals.registerPlatformActual(fPlatformActual);
  fWorkspaceSession := WorkspaceActuals.createSessionUsingRegisteredPlatform;
  fWorkspaceSession.StateChanged := @workspaceStateDidChange;

  fShellIntegration := new WindowsShellIntegration;
  fShellIntegration.PresentationRequested := @requestPresentation;
  fShellIntegration.QuitRequested := @requestQuit;
  fShellIntegration.startShell;
  refreshShellState;
end;

method App.OnExit(e: ExitEventArgs);
begin
  shutdownWorkspace;
  inherited OnExit(e);
end;

method App.requestPresentation;
begin
  if not assigned(fWorkspaceSession) then
    exit;

  if fWorkspaceSession.State = WorkspaceState.Idle then
    fWorkspaceSession.requestPresentation;
  refreshShellState;
end;

method App.requestQuit;
begin
  if fIsShuttingDown then
    exit;

  shutdownWorkspace;
  Shutdown;
end;

method App.workspaceStateDidChange(snapshot: WorkspaceStateSnapshot);
begin
  refreshShellState;
end;

method App.refreshShellState;
begin
  if (not assigned(fShellIntegration)) or (not assigned(fWorkspaceSession)) then
    exit;

  fShellIntegration.updateWorkspaceState(fWorkspaceSession.State) statusText(fWorkspaceSession.StatusText);
end;

method App.shutdownWorkspace;
begin
  if fIsShuttingDown then
    exit;

  fIsShuttingDown := true;
  if assigned(fShellIntegration) then begin
    fShellIntegration.PresentationRequested := nil;
    fShellIntegration.QuitRequested := nil;
    fShellIntegration.stopShell;
    fShellIntegration := nil;
  end;

  if assigned(fWorkspaceSession) then begin
    fWorkspaceSession.StateChanged := nil;
    fWorkspaceSession.disposeSession;
    fWorkspaceSession := nil;
  end;
  fPlatformActual := nil;
end;

end.
