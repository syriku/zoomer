namespace Zoomer.App;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
#if WINDOWS
        System.Windows.Forms.Application.SetHighDpiMode(
            System.Windows.Forms.HighDpiMode.PerMonitorV2);
        System.Windows.Forms.Application.EnableVisualStyles();
#endif
        using var host = new AppHost();
        return host.Run();
    }
}
