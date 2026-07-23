namespace WPFApp;

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
    begin
      if not assigned(fWorkspaceSession) then
        exit;

      if fWorkspaceSession.State = WorkspaceState.Idle then
        fWorkspaceSession.requestPresentation;
      refreshShellState;
    end;
    method requestQuit;
    begin
      if fIsShuttingDown then
        exit;

      shutdownWorkspace;
      Shutdown;
    end;
    method workspaceStateDidChange(snapshot: WorkspaceStateSnapshot);
    begin
      refreshShellState;
    end;
    method refreshShellState;
    begin
      if (not assigned(fShellIntegration)) or (not assigned(fWorkspaceSession)) then
        exit;

      fShellIntegration.updateWorkspaceState(fWorkspaceSession.State) statusText(fWorkspaceSession.StatusText);
    end;
    method shutdownWorkspace;
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
  protected
    method OnStartup(e: StartupEventArgs); override;
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
    method OnExit(e: ExitEventArgs); override;
    begin
      shutdownWorkspace;
      inherited OnExit(e);
    end;
  end;

end.
