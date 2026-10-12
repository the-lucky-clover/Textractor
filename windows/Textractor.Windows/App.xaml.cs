using System;
using System.Threading.Tasks;
using System.Windows;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows;

public partial class App : Application
{
    private Window? _mainWindow;
    private SystemTrayService? _systemTray;
    private ToastNotificationWindow? _toastWindow;
    private SplashScreenWindow? _splashWindow;

    public App()
    {
        this.InitializeComponent();
    }

    protected override async void OnStartup(StartupEventArgs args)
    {
        base.OnStartup(args);

        // Create main window (hidden, used for message pump)
        _mainWindow = new Window
        {
            Width = 1,
            Height = 1,
            Visibility = Visibility.Collapsed,
            WindowStyle = WindowStyle.None,
            ShowInTaskbar = false
        };
        _mainWindow.Show();

        // Show splash screen
        await ShowSplashScreenAsync();

        // Initialize services
        InitializeServices();

        // Initialize system tray
        _systemTray = new SystemTrayService(this);
        _systemTray.Initialize();

        // Register global hotkey
        HotkeyManager.Start();

        LoggerService.Log("Textractor Windows started");
    }

    private async Task ShowSplashScreenAsync()
    {
        _splashWindow = new SplashScreenWindow();
        await _splashWindow.ShowAsync();
        _splashWindow = null;
    }

    private void InitializeServices()
    {
        // Load settings
        var settings = SettingsStore.Shared.Settings;

        // Initialize telemetry
        TelemetryService.Shared.IsEnabled = settings.LocalTelemetryEnabled;

        // Initialize OCR
        // OCRService.Shared.Initialize(); // Would initialize Tesseract

        // Record session start
        TelemetryService.Shared.Record(new Models.TelemetryEvent
        {
            Kind = "session_start",
            Success = true
        });
    }

    public void ExitApplication()
    {
        // Record session end
        TelemetryService.Shared.Record(new Models.TelemetryEvent
        {
            Kind = "session_end",
            Success = true
        });

        HotkeyManager.Stop();
        _systemTray?.Dispose();
        _toastWindow?.Close();
        _mainWindow?.Close();

        // Exit the application
        Current.Shutdown();
    }

    public void ShowCaptureOverlay(CaptureMode mode)
    {
        _systemTray?.ShowCaptureOverlay(mode);
    }

    public void ShowSettings()
    {
        _systemTray?.ShowSettings();
    }

    public void ShowHistory()
    {
        _systemTray?.ShowHistory();
    }
}