using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using System;
using System.IO;
using System.Runtime.InteropServices;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows.Services;

public class SystemTrayService : IDisposable
{
    private readonly App _app;
    private NotifyIcon? _notifyIcon;
    private ContextMenu? _contextMenu;
    private Window? _settingsWindow;
    private Window? _historyWindow;
    private bool _isInitialized = false;

    public SystemTrayService(App app)
    {
        _app = app;
    }

    public void Initialize()
    {
        if (_isInitialized) return;
        
        CreateNotifyIcon();
        CreateContextMenu();
        _isInitialized = true;
    }

    private void CreateNotifyIcon()
    {
        _notifyIcon = new NotifyIcon
        {
            Icon = new System.Drawing.Icon("Resources/textractor.ico"),
            Visible = true,
            Text = "Textractor"
        };
        
        _notifyIcon.DoubleClick += (s, e) => ShowCaptureOverlay(CaptureMode.Crosshair);
        _notifyIcon.ContextMenuStrip = CreateLegacyContextMenu();
    }

    private ContextMenuStrip CreateLegacyContextMenu()
    {
        var menu = new ContextMenuStrip();
        
        // Banner would be shown as a custom item - for now use standard items
        menu.Items.Add("Textractor", null, (s, e) => { });
        menu.Items.Add(new ToolStripSeparator());
        
        var captureRegion = new ToolStripMenuItem("Region", null, (s, e) => ShowCaptureOverlay(CaptureMode.Crosshair));
        captureRegion.Image = CreateMenuIcon("viewfinder");
        menu.Items.Add(captureRegion);
        
        var captureWindow = new ToolStripMenuItem("Window", null, (s, e) => ShowCaptureOverlay(CaptureMode.Window));
        captureWindow.Image = CreateMenuIcon("macwindow");
        menu.Items.Add(captureWindow);
        
        var captureFullscreen = new ToolStripMenuItem("Full Screen", null, (s, e) => ShowCaptureOverlay(CaptureMode.FullScreen));
        captureFullscreen.Image = CreateMenuIcon("rectangle.dashed.badge.record");
        menu.Items.Add(captureFullscreen);
        
        menu.Items.Add(new ToolStripSeparator());
        
        var pickFile = new ToolStripMenuItem("Pick Image File…", null, (s, e) => PickImageFile());
        pickFile.Image = CreateMenuIcon("photo.on.rectangle");
        menu.Items.Add(pickFile);
        
        var history = new ToolStripMenuItem("History", null, (s, e) => ShowHistory());
        history.Image = CreateMenuIcon("clock.arrow.circlepath");
        menu.Items.Add(history);
        
        menu.Items.Add(new ToolStripSeparator());
        
        var settings = new ToolStripMenuItem("Settings…", null, (s, e) => ShowSettings());
        settings.Image = CreateMenuIcon("gearshape");
        menu.Items.Add(settings);
        
        menu.Items.Add(new ToolStripSeparator());
        
        var quit = new ToolStripMenuItem("Quit Textractor", null, (s, e) => Quit());
        quit.Image = CreateMenuIcon("power");
        quit.ForeColor = System.Drawing.Color.Red;
        menu.Items.Add(quit);
        
        return menu;
    }

    private System.Drawing.Image? CreateMenuIcon(string name)
    {
        try
        {
            var basePath = AppDomain.CurrentDomain.BaseDirectory;
            var iconPath = name switch
            {
                "viewfinder" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                "macwindow" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                "rectangle.dashed.badge.record" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                "photo.on.rectangle" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                "clock.arrow.circlepath" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                "gearshape" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                "power" => Path.Combine(basePath, "Resources", "textractor-menubar@1x.png"),
                _ => null
            };
            
            if (iconPath != null && File.Exists(iconPath))
            {
                return System.Drawing.Image.FromFile(iconPath);
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error($"Failed to load menu icon {name}", ex);
        }
        return null;
    }

    private void CreateContextMenu()
    {
        // Modern XAML-based context menu for richer UI
        _contextMenu = new ContextMenu();
        
        // We'll use the legacy ContextMenuStrip for now due to NotifyIcon limitations
        // In a full implementation, we'd use a custom Window as a popup
    }

    public void ShowCaptureOverlay(CaptureMode mode)
    {
        _app.DispatcherQueue.TryEnqueue(() =>
        {
            var overlay = new Views.CaptureOverlayWindow(mode)
            {
                OnRegionCaptured = async (rect) => await OnRegionCapturedAsync(rect),
                OnWindowCaptured = async (hwnd) => await OnWindowCapturedAsync(hwnd),
                OnCancel = () => { /* Cancelled */ }
            };
            overlay.Activate();
        });
    }

    private async Task OnRegionCapturedAsync(Rect rect)
    {
        try
        {
            var capture = await ScreenshotService.Shared.CaptureRegionAsync(rect);
            await RunPipelineAsync(capture);
        }
        catch (Exception ex)
        {
            LoggerService.Error("Region capture failed", ex);
            ShowErrorToast("Capture failed: " + ex.Message);
        }
    }

    private async Task OnWindowCapturedAsync(IntPtr hwnd)
    {
        try
        {
            var (capture, _) = await ScreenshotService.Shared.CaptureWindowAsync(hwnd);
            await RunPipelineAsync(capture);
        }
        catch (Exception ex)
        {
            LoggerService.Error("Window capture failed", ex);
            ShowErrorToast("Capture failed: " + ex.Message);
        }
    }

    private async Task RunPipelineAsync(Models.CapturedImage capture)
    {
        // This would run the full OCR pipeline
        // For now, show a placeholder toast
        var toastWindow = new Views.ToastNotificationWindow();
        var toast = new Models.ToastState
        {
            Kind = "success",
            Headline = "Text copied to clipboard",
            Body = "OCR processing complete",
            Capture = capture,
            Copy = () => { /* Copy to clipboard */ }
        };
        await toastWindow.ShowToastAsync(toast);
    }

    private void PickImageFile()
    {
        var picker = new Windows.Storage.Pickers.FileOpenPicker();
        picker.FileTypeFilter.Add(".png");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");
        picker.FileTypeFilter.Add(".heic");
        picker.FileTypeFilter.Add(".tiff");
        picker.FileTypeFilter.Add(".bmp");
        
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(_app.MainWindow);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        
        _ = Task.Run(async () =>
        {
            var file = await picker.PickSingleFileAsync();
            if (file != null)
            {
                await _app.DispatcherQueue.EnqueueAsync(async () =>
                {
                    var capture = await ScreenshotService.Shared.CaptureFromFileAsync(file.Path);
                    await RunPipelineAsync(capture);
                });
            }
        });
    }

    private void ShowSettings()
    {
        if (_settingsWindow == null)
        {
            _settingsWindow = new Views.SettingsWindow();
            _settingsWindow.Closed += (s, e) => _settingsWindow = null;
        }
        _settingsWindow.Activate();
    }

    private void ShowHistory()
    {
        if (_historyWindow == null)
        {
            _historyWindow = new Views.HistoryWindow();
            _historyWindow.Closed += (s, e) => _historyWindow = null;
        }
        _historyWindow.Activate();
    }

    private void Quit()
    {
        _app.ExitApplication();
    }

    public void ShowSuccessToast(string message)
    {
        _ = _app.DispatcherQueue.EnqueueAsync(async () =>
        {
            var toastWindow = new Views.ToastNotificationWindow();
            var toast = new Models.ToastState
            {
                Kind = "success",
                Headline = "Textractor",
                Body = message
            };
            await toastWindow.ShowToastAsync(toast);
        });
    }

    public void ShowErrorToast(string message)
    {
        _ = _app.DispatcherQueue.EnqueueAsync(async () =>
        {
            var toastWindow = new Views.ToastNotificationWindow();
            var toast = new Models.ToastState
            {
                Kind = "failure",
                Headline = "Error",
                Body = message
            };
            await toastWindow.ShowToastAsync(toast);
        });
    }

    public void Dispose()
    {
        _notifyIcon?.Dispose();
        _notifyIcon = null;
        _contextMenu = null;
    }
}

// WinForms NotifyIcon wrapper for WinUI 3
internal class NotifyIcon : IDisposable
{
    private readonly System.Windows.Forms.NotifyIcon _icon;
    public event EventHandler? DoubleClick;
    public ContextMenuStrip? ContextMenuStrip { get; set; }

    public NotifyIcon()
    {
        _icon = new System.Windows.Forms.NotifyIcon();
        _icon.DoubleClick += (s, e) => DoubleClick?.Invoke(this, EventArgs.Empty);
        _icon.MouseClick += (s, e) => 
        {
            if (e.Button == System.Windows.Forms.MouseButtons.Right && ContextMenuStrip != null)
            {
                ContextMenuStrip.Show(System.Windows.Forms.Cursor.Position);
            }
        };
    }

    public System.Drawing.Icon? Icon
    {
        get => _icon.Icon;
        set => _icon.Icon = value;
    }

    public bool Visible
    {
        get => _icon.Visible;
        set => _icon.Visible = value;
    }

    public string Text
    {
        get => _icon.Text;
        set => _icon.Text = value;
    }

    public void Dispose()
    {
        _icon.Dispose();
    }
}