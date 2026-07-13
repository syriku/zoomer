#if WINDOWS
using System.Runtime.InteropServices;
using Zoomer.Core;
using Forms = System.Windows.Forms;

namespace Zoomer.App;

internal sealed class AppHost : IDisposable
{
    private readonly WorkspaceController _workspace;
    private readonly Forms.NotifyIcon _trayIcon;
    private readonly Forms.ContextMenuStrip _menu;
    private readonly Forms.ToolStripMenuItem _presentItem;
    private readonly Forms.ToolStripMenuItem _statusItem;
    private readonly HotKeyWindow _hotKeyWindow = new();
    private bool _hotKeyRegistered;
    private bool _disposed;

    public AppHost()
    {
        _workspace = new WorkspaceController(new WindowsPermissionService(),
            new WindowsScreenCaptureService(), new WindowsWorkspaceWindowFactory());
        _workspace.StateChanged += _ => RefreshMenu();

        _presentItem = new Forms.ToolStripMenuItem("进入工作模式");
        _presentItem.Click += (_, _) => _workspace.RequestPresentation();
        _statusItem = new Forms.ToolStripMenuItem("空闲") { Enabled = false };
        var quitItem = new Forms.ToolStripMenuItem("退出 Zoomer");
        quitItem.Click += (_, _) => Quit();

        _menu = new Forms.ContextMenuStrip();
        _menu.Items.Add(_presentItem);
        _menu.Items.Add(_statusItem);
        _menu.Items.Add(new Forms.ToolStripSeparator());
        _menu.Items.Add(quitItem);

        _trayIcon = new Forms.NotifyIcon
        {
            ContextMenuStrip = _menu,
            Icon = System.Drawing.SystemIcons.Application,
            Text = "Zoomer",
            Visible = true,
        };
        _trayIcon.DoubleClick += (_, _) => _workspace.RequestPresentation();
    }

    public int Run()
    {
        _hotKeyRegistered = _hotKeyWindow.Register(_workspace.RequestPresentation);
        RefreshMenu();
        var application = new System.Windows.Application
        {
            ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown,
        };
        return application.Run();
    }

    private void RefreshMenu()
    {
        _presentItem.Enabled = _workspace.State == WorkspaceState.Idle;
        _statusItem.Text = _hotKeyRegistered
            ? _workspace.StatusText
            : $"{_workspace.StatusText}；快捷键 Ctrl+Alt+Z 注册失败";
    }

    private void Quit()
    {
        Dispose();
        System.Windows.Application.Current?.Shutdown();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _workspace.Dispose();
        _hotKeyWindow.Dispose();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _menu.Dispose();
    }
}

internal sealed class HotKeyWindow : Forms.NativeWindow, IDisposable
{
    private const int HotKeyId = 1;
    private const int WmHotKey = 0x0312;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint VirtualKeyZ = 0x5A;
    private Action? _triggered;
    private bool _registered;

    internal bool Register(Action triggered)
    {
        _triggered = triggered;
        CreateHandle(new Forms.CreateParams { Caption = "Zoomer hotkey window" });
        _registered = RegisterHotKey(Handle, HotKeyId, ModControl | ModAlt, VirtualKeyZ);
        return _registered;
    }

    protected override void WndProc(ref Forms.Message message)
    {
        if (message.Msg == WmHotKey && message.WParam == HotKeyId)
            _triggered?.Invoke();
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (_registered)
        {
            UnregisterHotKey(Handle, HotKeyId);
            _registered = false;
        }
        if (Handle != 0)
            DestroyHandle();
        _triggered = null;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(nint window, int id);
}
#endif
