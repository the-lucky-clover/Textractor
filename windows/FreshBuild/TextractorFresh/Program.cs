using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Tesseract;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows;

/// <summary>
/// Textractor - On-device, privacy-first OCR for Windows
/// System tray application with global hotkey support
/// </summary>
partial class Program
{
    private static NotifyIcon? _notifyIcon;
    private static ContextMenuStrip? _contextMenu;
    private static bool _isShuttingDown = false;
    private static readonly ManualResetEvent _exitEvent = new(false);
    
    // Services
    private static SettingsStore? _settingsStore;
    private static AppSettings? _settings;
    private static OCRService? _ocrService;
    private static AIInferenceService? _aiService;
    private static ScreenshotService? _screenshotService;
    private static HistoryStore? _historyStore;
    private static SoundManager? _soundManager;
    private static ToastService? _toastService;
    private static IntPtr _windowHandle = IntPtr.Zero;
    private static WndProc? _wndProcDelegate; // Keep delegate alive to prevent GC
    
    [STAThread]
    static void Main(string[] args)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        if (args.FirstOrDefault() == "--ui-smoke-test")
        {
            Environment.ExitCode = RunUiPlaytest(args.Skip(1).FirstOrDefault() ?? "playtest");
            return;
        }
        // Handle command line arguments
        if (args.Length > 0)
        {
            if (args[0] == "--console" || args[0] == "-c")
            {
                RunConsoleMode(args.Skip(1).ToArray()).GetAwaiter().GetResult();
                return;
            }
            else if (args[0] == "--help" || args[0] == "-h")
            {
                ShowHelp();
                return;
            }
            else if (File.Exists(args[0]))
            {
                // Process image file and exit
                ProcessImageFileAndExit(args[0]).GetAwaiter().GetResult();
                return;
            }
        }
        
        // Run as system tray application
        RunSystemTrayApp();
    }
    
    static void RunSystemTrayApp()
    {
        // Show splash screen first
        ShowSplashScreen();
        
        InitializeServices();
        
        // Create and show notify icon immediately for fast startup
        CreateNotifyIcon();
        
        
        // Register global hotkey
        RegisterGlobalHotkey();
        
        // Create and run main form (shows in taskbar)
        var mainForm = new MainForm();
        _mainForm = mainForm;
        _toastService!.Initialize(mainForm);
        mainForm.Load += (s, e) => 
        {
            // Check for first run onboarding
            CheckFirstRunOnboarding();
        };
        
        Application.Run(mainForm);
    }
    
    static void ShowSplashScreen()
    {
        using var splash = new SplashScreenForm();
        splash.ShowDialog();
    }

    static Form? _mainForm;
    
    class MainForm : Textractor.Windows.UI.MenuForm
    {
        public MainForm() : base(TriggerCapture, PickImageFile, ShowHistory, ShowSettings, ExitApplication)
        {
            ShowInTaskbar = _settings?.DockPresence != DockPresence.MenuBarOnly;
            FormClosing += (_, e) =>
            {
                if (!_isShuttingDown) { e.Cancel = true; Hide(); }
            };
        }
        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            _mainForm = this;
        }
    }
    class SplashScreenForm : Form
    {
        private readonly System.Windows.Forms.Timer _fadeTimer;
        private readonly System.Windows.Forms.Timer _displayTimer;
        private Image? _splashImage;
        private float _opacity = 0f;
        private int _phase = 0; // 0 = fade in, 1 = display, 2 = fade out
        private const float FADE_STEP = 0.12f;
        
        public SplashScreenForm()
        {
            // Form settings
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.BackColor = UI.AppTheme.Background;
            this.Opacity = 0;
            
            // Load splash image
            try
            {
                var imagePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "textractor-splash.png");
                if (File.Exists(imagePath))
                {
                    _splashImage = Image.FromFile(imagePath);
                    
                    // Match the macOS 460-point splash rather than the image's export size.
                    var area = Screen.FromPoint(Cursor.Position).WorkingArea;
                    var side = Math.Min(460, Math.Min(area.Width, area.Height) - 80);
                    this.ClientSize = new Size(side, side);
                }
                else
                {
                    this.ClientSize = new Size(500, 350);
                }
            }
            catch
            {
                this.ClientSize = new Size(500, 350);
            }
            
            // Fade in timer (fast - ~33fps)
            _fadeTimer = new System.Windows.Forms.Timer { Interval = 30 };
            _fadeTimer.Tick += FadeTimer_Tick;
            
            // Display timer (hold at full opacity)
            _displayTimer = new System.Windows.Forms.Timer { Interval = 3000 };
            _displayTimer.Tick += DisplayTimer_Tick;
            
            // Start fade in
            if (SettingsStore.Shared.Settings.ReduceMotion)
            {
                _opacity = 1; Opacity = 1; _displayTimer.Start();
            }
            else _fadeTimer.Start();
        }
        
        private void FadeTimer_Tick(object? sender, EventArgs e)
        {
            if (_phase == 0) // Fade in
            {
                _opacity = Math.Min(1f, _opacity + FADE_STEP);
                this.Opacity = _opacity;
                
                if (_opacity >= 1f)
                {
                    _opacity = 1f;
                    this.Opacity = 1f;
                    _phase = 1;
                    _fadeTimer.Stop();
                    _displayTimer.Start();
                }
            }
            else if (_phase == 2) // Fade out
            {
                _opacity = Math.Max(0f, _opacity - FADE_STEP);
                this.Opacity = _opacity;
                
                if (_opacity <= 0f)
                {
                    _opacity = 0f;
                    this.Opacity = 0f;
                    _fadeTimer.Stop();
                    this.Close();
                }
            }
        }
        
        private void DisplayTimer_Tick(object? sender, EventArgs e)
        {
            _displayTimer.Stop();
            _phase = 2;
            _fadeTimer.Start();
        }
        
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            
            if (_splashImage != null)
            {
                // Draw image centered with padding
                e.Graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                e.Graphics.DrawImage(_splashImage, new Rectangle(20, 20, ClientSize.Width - 40, ClientSize.Height - 40));
            }
            else
            {
                // Fallback text
                using var font = new Font("Segoe UI", 24, FontStyle.Bold);
                using var brush = new SolidBrush(UI.AppTheme.Green);
                var text = "Textractor";
                var size = e.Graphics.MeasureString(text, font);
                var x = (this.ClientSize.Width - size.Width) / 2;
                var y = (this.ClientSize.Height - size.Height) / 2;
                e.Graphics.DrawString(text, font, brush, x, y);
            }
        }
        
        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            _fadeTimer?.Dispose();
            _displayTimer?.Dispose();
            _splashImage?.Dispose();
            base.OnFormClosed(e);
        }
    }
    
    static void InitializeServices()
    {
        _settingsStore = SettingsStore.Shared;
        _settings = _settingsStore.Settings;
        
        _ocrService = new OCRService();
        _aiService = AIInferenceService.Shared;
        _screenshotService = new ScreenshotService();
        _historyStore = HistoryStore.Shared;
        _soundManager = new SoundManager();
        _toastService = ToastService.Shared;
        
        _toastService.Initialize();
        TelemetryService.Shared.IsEnabled = _settings.LocalTelemetryEnabled;
        
        // Check tessdata
        if (!Directory.Exists(_ocrService.GetTessdataPath()))
        {
            LogWarning($"Tesseract tessdata not found at: {_ocrService.GetTessdataPath()}");
        }
        
        LogInfo("Textractor services initialized");
    }
    
    static void CreateNotifyIcon()
    {
        _contextMenu = new ContextMenuStrip();
        _contextMenu.BackColor = UI.AppTheme.Background;
        _contextMenu.ForeColor = Color.White;
        _contextMenu.Renderer = new ToolStripProfessionalRenderer(new DarkColorTable());
        
        // App header
        var headerItem = new ToolStripMenuItem("Textractor")
        {
            Enabled = false,
            Font = new Font("Segoe UI", 10, FontStyle.Bold),
            ForeColor = UI.AppTheme.Green,
            Padding = new Padding(10, 8, 10, 8)
        };
        _contextMenu.Items.Add(headerItem);
        _contextMenu.Items.Add(new ToolStripSeparator());
        
        // Show Window
        var showWindowItem = CreateMenuItem("Show Window", 
            (s, e) => RestoreMainWindow());
        _contextMenu.Items.Add(showWindowItem);
        
        _contextMenu.Items.Add(new ToolStripSeparator());
        
        // Capture Region
        var captureRegionItem = CreateMenuItem("Capture Region (Alt+Shift+2)", 
            (s, e) => TriggerCapture(CaptureMode.Crosshair));
        captureRegionItem.ShortcutKeys = Keys.Alt | Keys.Shift | Keys.D2;
        captureRegionItem.ShowShortcutKeys = true;
        _contextMenu.Items.Add(captureRegionItem);
        
        // Capture Window
        var captureWindowItem = CreateMenuItem("Capture Window (Alt+Shift+3)", 
            (s, e) => TriggerCapture(CaptureMode.Window));
        captureWindowItem.ShortcutKeys = Keys.Alt | Keys.Shift | Keys.D3;
        captureWindowItem.ShowShortcutKeys = true;
        _contextMenu.Items.Add(captureWindowItem);
        
        // Capture Full Screen
        var captureFullItem = CreateMenuItem("Capture Full Screen", 
            (s, e) => TriggerCapture(CaptureMode.FullScreen));
        _contextMenu.Items.Add(captureFullItem);
        
        _contextMenu.Items.Add(new ToolStripSeparator());
        
        // History
        var historyItem = CreateMenuItem("History", 
            (s, e) => ShowHistory());
        _contextMenu.Items.Add(historyItem);
        
        // Settings
        var settingsItem = CreateMenuItem("Settings", 
            (s, e) => ShowSettings());
        _contextMenu.Items.Add(settingsItem);
        
        _contextMenu.Items.Add(new ToolStripSeparator());
        
        // Exit
        var exitItem = CreateMenuItem("Exit", 
            (s, e) => ExitApplication());
        _contextMenu.Items.Add(exitItem);
        
        // Load icon
        Icon appIcon;
        try
        {
            var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
            if (File.Exists(iconPath))
            {
                appIcon = new Icon(iconPath);
            }
            else
            {
                appIcon = SystemIcons.Application;
            }
        }
        catch
        {
            appIcon = SystemIcons.Application;
        }
        
        _notifyIcon = new NotifyIcon
        {
            Icon = appIcon,
            Text = "Textractor - On-device OCR",
            Visible = true,
            ContextMenuStrip = _contextMenu
        };
        
        // Handle double-click - restore window
        _notifyIcon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) RestoreMainWindow(); };
        
        // Show startup notification
        _notifyIcon.ShowBalloonTip(3000, "Textractor", "Running in background. Alt+Shift+2 to capture.", ToolTipIcon.Info);
    }
    
    static void RestoreMainWindow()
    {
        if (_mainForm != null)
        {
            _mainForm.Show();
            _mainForm.WindowState = FormWindowState.Normal;
            _mainForm.BringToFront();
            _mainForm.Activate();
        }
    }
    
    static ToolStripMenuItem CreateMenuItem(string text, EventHandler onClick)
    {
        var item = new ToolStripMenuItem(text, null, onClick)
        {
            ForeColor = Color.White,
            BackColor = Color.Transparent,
            Padding = new Padding(10, 6, 10, 6),
            Font = new Font("Segoe UI", 9)
        };
        item.MouseEnter += (s, e) => item.BackColor = UI.AppTheme.Green;
        item.MouseLeave += (s, e) => item.BackColor = Color.Transparent;
        return item;
    }
    
    static void RegisterGlobalHotkey()
    {
        // Create a hidden window for hotkey messages
        _windowHandle = CreateMessageWindow();
        
        // Register hotkeys: Alt+Shift+2 (region), Alt+Shift+3 (window)
        TrayHotkeyManager.Initialize(_windowHandle, TriggerCapture);
        
        var success = TrayHotkeyManager.RegisterHotkeys(_settings!);
        if (!success)
        {
            LogWarning("Failed to register global hotkeys. Another app may be using them.");
        }
        else
        {
            LogInfo($"Global hotkeys registered: Alt+Shift+2 (Region), Alt+Shift+3 (Window)");
        }
    }
    
    static IntPtr CreateMessageWindow()
    {
        _wndProcDelegate = MessageWindowProc; // Store delegate to prevent GC
        var wc = new WNDCLASS
        {
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProcDelegate),
            hInstance = NativeMethods.GetModuleHandle(null),
            lpszClassName = "TextractorMessageWindow"
        };
        
        NativeMethods.RegisterClass(ref wc);
        
        return NativeMethods.CreateWindowEx(
            0,
            "TextractorMessageWindow",
            "TextractorMessageWindow",
            0,
            0, 0, 0, 0,
            IntPtr.Zero,
            IntPtr.Zero,
            NativeMethods.GetModuleHandle(null),
            IntPtr.Zero
        );
    }

    private delegate IntPtr WndProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);
    
    private static IntPtr MessageWindowProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam)
    {
        const int WM_HOTKEY = 0x0312;
        const uint WM_USER = 0x0400;
        const uint WM_TRIGGER_CAPTURE = WM_USER + 1;
        
        if (uMsg == WM_HOTKEY)
        {
            int hotkeyId = wParam.ToInt32();
            TrayHotkeyManager.ProcessHotkey(hotkeyId);
            return IntPtr.Zero;
        }
        
        if (uMsg == WM_TRIGGER_CAPTURE)
        {
            // This is a fallback - hotkeys are handled directly via ProcessHotkey
            return IntPtr.Zero;
        }
        
        return NativeMethods.DefWindowProc(hWnd, uMsg, wParam, lParam);
    }
    
    static bool _captureBusy;
    static async void TriggerCapture(CaptureMode mode)
    {
        if (_isShuttingDown || _captureBusy) return;
        _captureBusy = true;
        try
        {
            _mainForm?.Hide();
            if (mode == CaptureMode.FullScreen) { await Task.Delay(150); await PerformCapture(mode); return; }
            using var selector = new UI.CaptureSelectionForm(mode, _screenshotService!.EnumerateWindows());
            if (selector.ShowDialog() != DialogResult.OK) return;
            await Task.Delay(150);
            if (selector.SelectedMode == CaptureMode.Window)
            {
                var result = await _screenshotService.CaptureWindowAsync(selector.SelectedWindow);
                await ProcessCapture(result.Item1, CaptureMode.Window);
            }
            else
            {
                var capture = await _screenshotService.CaptureRegionAsync(selector.SelectedRegion);
                await ProcessCapture(capture, CaptureMode.Crosshair);
            }
        }
        catch (Exception ex) { LogError("Capture failed", ex); ShowToast("Capture Failed", ex.Message, ToastKind.Error); }
        finally { _captureBusy = false; }
    }
    
    static async Task PerformCapture(CaptureMode mode)
    {
        if (_screenshotService == null || _ocrService == null || _aiService == null || 
            _historyStore == null || _soundManager == null || _settings == null)
        {
            ShowToast("Not Ready", "Services still initializing...", ToastKind.Warning);
            return;
        }
        
        _soundManager.PlayCaptureSound(_settings);
        
        CapturedImage? capture = null;
        
        try
        {
            switch (mode)
            {
                case CaptureMode.Crosshair:
                    // Capture primary display as region (simplified - full screen capture)
                    var displays = _screenshotService.GetDisplays();
                    if (displays.Count > 0)
                    {
                        var primaryDisplay = displays[0];
                        capture = await _screenshotService.CaptureRegionAsync(primaryDisplay.Frame);
                    }
                    break;
                case CaptureMode.Window:
                    // Capture foreground window
                    var foregroundWindow = NativeMethods.GetForegroundWindow();
                    if (foregroundWindow != IntPtr.Zero)
                    {
                        var result = await _screenshotService.CaptureWindowAsync(foregroundWindow);
                        capture = result.Item1;
                    }
                    break;
                case CaptureMode.FullScreen:
                    var captures = await _screenshotService.CaptureFullScreenAsync();
                    if (captures.Count > 0)
                    {
                        foreach (var c in captures)
                        {
                            await ProcessCapture(c, mode);
                        }
                        return;
                    }
                    break;
            }
            
            if (capture != null)
            {
                await ProcessCapture(capture, mode);
            }
            else
            {
                ShowToast("Capture Failed", "No image was captured.", ToastKind.Error);
            }
        }
        catch (Exception ex)
        {
            LogError("Capture failed", ex);
            ShowToast("Capture Failed", ex.Message, ToastKind.Error);
        }
    }
    
    static async Task ProcessCapture(CapturedImage capture, CaptureMode mode)
    {
        try
        {
            _ocrService!.SetLanguage(_settings!.OcrLanguage);
            if (!_ocrService.IsReady)
                throw new InvalidOperationException("OCR language data is unavailable. Install the language data and restart Textractor.");
            OCRResult ocrResult;
            using (var bitmap = new Bitmap(capture.FilePath))
                ocrResult = await _ocrService!.RecognizeText(bitmap, _settings!.Weirdness, _settings.CustomVocabulary);

            if (ocrResult.IsEmpty)
            {
                ShowToast("No Text Found", "No text was detected in the capture.", ToastKind.Warning);
                await StorageService.GovernStorageAsync(capture, _settings!);
                return;
            }

            // Run AI analysis
            var analysis = await _aiService!.Analyze(ocrResult.JoinedText, _settings.Weirdness);

            // Format text
            string finalText = ocrResult.JoinedText;
            if (_settings.WindowCaptureAsTable && mode == CaptureMode.Window)
            {
                var table = TableFormatter.ToMarkdownTable(ocrResult.RawObservations);
                if (!string.IsNullOrEmpty(table))
                {
                    finalText = table;
                }
            }

            finalText = PasteFormatter.Format(finalText, _settings.WordWrapCaptured, _settings.FlattenText);
            var rtfText = TextFormatter.ToRtf(finalText, analysis, _settings.Weirdness);

            // Copy to clipboard
            if (!ClipboardService.Copy(finalText, _settings.PasteAsPlainText ? null : rtfText))
                throw new InvalidOperationException("Clipboard is busy. Please retry the capture.");

            // Auto-paste
            if (_settings.AutoPasteEnabled && capture.Origin != CaptureOrigin.File)
            {
                await Task.Delay(150);
                ClipboardService.AutoPasteIntoFrontmostApp();
            }

            // Record history
            _historyStore!.Record(capture, finalText, mode, _settings.HistoryEntryLimit);

            // Storage
            await StorageService.GovernStorageAsync(capture, _settings);

            // Success toast
            _soundManager!.PlaySuccessSound(_settings);
            
            var sentiment = analysis.Sentiment switch
            {
                AIInferenceService.Sentiment.Positive => ToastSentiment.Positive,
                AIInferenceService.Sentiment.Negative => ToastSentiment.Negative,
                AIInferenceService.Sentiment.Mixed => ToastSentiment.Mixed,
                _ => ToastSentiment.Neutral
            };

            ShowToast(
                "Text Extracted",
                $"{analysis.Tokens} words • {analysis.Language?.ToUpper() ?? "EN"} • {ocrResult.RawObservations.Count} regions",
                ToastKind.Success,
                sentiment);
        }
        catch (Exception ex)
        {
            LogError("Process capture failed", ex);
            ShowToast("Processing Failed", ex.Message, ToastKind.Error);
        }
    }
    
    static void ShowSettings()
    {
        if (_preferences != null && !_preferences.IsDisposed) { _preferences.Show(); _preferences.Activate(); return; }
        _preferences = new UI.PreferencesForm(_settings!, () =>
        {
            _settingsStore!.Save();
            TelemetryService.Shared.IsEnabled = _settings!.LocalTelemetryEnabled;
        }, ShowHistory);
        _preferences.Show();
    }
    
    static void ShowHistory()
    {
        _library?.Close();
        _library = new UI.LibraryForm(_historyStore!.GetRecent(_settings!.HistoryEntryLimit));
        _library.Show();
    }

    static UI.PreferencesForm? _preferences;
    static UI.LibraryForm? _library;

    static async void PickImageFile()
    {
        if (_captureBusy) return;
        using var picker = new OpenFileDialog { Title = "Pick Image File", Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff|All files|*.*" };
        if (picker.ShowDialog(_mainForm) != DialogResult.OK) return;
        _captureBusy = true;
        try
        {
            var capture = await _screenshotService!.CaptureFromFileAsync(picker.FileName);
            // File import keeps the app focused; only screen captures should auto-paste.
            await ProcessCapture(capture, CaptureMode.Crosshair);
        }
        catch (Exception ex) { ShowToast("Image import failed", ex.Message, ToastKind.Error); }
        finally { _captureBusy = false; }
    }
    
    static void ShowToast(string title, string message, ToastKind kind, ToastSentiment sentiment = ToastSentiment.Neutral)
    {
        _toastService?.ShowToast(new ToastViewModel
        {
            Title = title,
            Message = message,
            Kind = kind,
            Sentiment = sentiment,
            DurationSeconds = kind == ToastKind.Error ? 9 : 8
        });
    }
    
    static void ExitApplication()
    {
        _isShuttingDown = true;
        
        // Unregister hotkey
        TrayHotkeyManager.Stop();
        
        // Cleanup services
        _ocrService?.Dispose();
        _soundManager?.Dispose();
        _toastService?.Dispose();
        
        // Hide and dispose notify icon
        if (_notifyIcon != null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
        }
        
        // Close main form
        if (_mainForm != null)
        {
            _mainForm.Close();
            _mainForm.Dispose();
        }
        
        // Exit message loop
        Application.Exit();
        _exitEvent.Set();
    }
    
    static void CheckFirstRunOnboarding()
    {
        try
        {
            var settingsPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Textractor",
                "settings.json");
            
            if (!File.Exists(settingsPath))
            {
                // First run - show onboarding
                ShowOnboardingDialog();
            }
        }
        catch
        {
            // Ignore errors, just skip onboarding
        }
    }
    
    static void ShowOnboardingDialog()
    {
        if (_mainForm == null) return;
        
        var dialog = new Form
        {
            Text = "Welcome to Textractor",
            Width = 500,
            Height = 450,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false,
            ShowInTaskbar = false,
            BackColor = UI.AppTheme.Background
        };
        
        try
        {
            var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
            if (File.Exists(iconPath))
                dialog.Icon = new Icon(iconPath);
        }
        catch { }
        
        var panel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(30) };
        
        var titleLabel = new Label
        {
            Text = "Welcome to Textractor",
            Font = new Font("Segoe UI", 18, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = true,
            Location = new Point(20, 20)
        };
        
        var descLabel = new Label
        {
            Text = "On-device, privacy-first OCR for Windows.\n\nCapture text from anywhere on your screen with global hotkeys:",
            Font = new Font("Segoe UI", 9),
            ForeColor = UI.AppTheme.Ink,
            AutoSize = true,
            MaximumSize = new Size(440, 0),
            Location = new Point(20, 60)
        };
        
        var hotkeysLabel = new Label
        {
            Text = "  Alt+Shift+2  →  Capture Region (click & drag)\n  Alt+Shift+3  →  Capture Window (click window)\n\nText is automatically extracted and copied to clipboard.\nScreenshots can be saved or auto-deleted per your settings.",
            Font = new Font("Consolas", 9),
            ForeColor = UI.AppTheme.Green,
            AutoSize = true,
            MaximumSize = new Size(440, 0),
            Location = new Point(20, 110)
        };
        
        var skipCheck = new CheckBox
        {
            Text = "Don't show this again",
            Font = new Font("Segoe UI", 9),
            ForeColor = UI.AppTheme.Muted,
            AutoSize = true,
            Location = new Point(20, 240)
        };
        
        var okButton = new Button
        {
            Text = "Get Started",
            Font = new Font("Segoe UI", 10, FontStyle.Bold),
            ForeColor = UI.AppTheme.Background,
            BackColor = UI.AppTheme.Green,
            FlatStyle = FlatStyle.Flat,
            Size = new Size(120, 40),
            Location = new Point(20, 300),
            DialogResult = DialogResult.OK
        };
        okButton.FlatAppearance.BorderSize = 0;
        
        okButton.Click += (s, e) =>
        {
            if (skipCheck.Checked)
            {
                // Mark onboarding as complete by creating empty settings file
                try
                {
                    var settingsDir = Path.GetDirectoryName(
                        Path.Combine(
                            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                            "Textractor",
                            "settings.json"));
                    Directory.CreateDirectory(settingsDir!);
                    var defaultSettings = "{\"Weirdness\":0.45,\"OcrLanguage\":\"eng\",\"AutoPasteEnabled\":true}";
                    File.WriteAllText(
                        Path.Combine(settingsDir!, "settings.json"),
                        defaultSettings);
                }
                catch { }
            }
            dialog.Close();
        };
        
        panel.Controls.AddRange(new Control[] { titleLabel, descLabel, hotkeysLabel, skipCheck, okButton });
        dialog.Controls.Add(panel);
        
        _mainForm.BeginInvoke(new Action(() => dialog.ShowDialog(_mainForm)));
    }
    
    static async Task RunConsoleMode(string[] args)
    {
        // Ensure we have a console
        if (!Console.IsOutputRedirected && !Console.IsInputRedirected)
        {
            NativeMethods.AttachConsole(-1);
        }
        
        Console.WriteLine("╔═══════════════════════════════════════════════════════════╗");
        Console.WriteLine("║  Textractor - On-device OCR for Windows                   ║");
        Console.WriteLine("║  Privacy-first • Local processing • Cyberpunk aesthetic   ║");
        Console.WriteLine("╚═══════════════════════════════════════════════════════════╝");
        Console.WriteLine();

        InitializeServices();
        
        Console.WriteLine("Services initialized.");
        Console.WriteLine($"OCR Language: {_settings!.OcrLanguage}");
        Console.WriteLine($"Weirdness: {_settings.Weirdness:P0}");
        Console.WriteLine($"Auto-paste: {_settings.AutoPasteEnabled}");
        Console.WriteLine();

        if (!Directory.Exists(_ocrService!.GetTessdataPath()))
        {
            Console.WriteLine("⚠ Tesseract tessdata not found!");
            Console.WriteLine($"  Expected at: {_ocrService.GetTessdataPath()}");
            Console.WriteLine();
        }

        Console.WriteLine("Available windows for capture:");
        var windows = _screenshotService!.EnumerateWindows()
            .Where(w => w.IsCaptureEligible)
            .Take(10)
            .ToList();
        
        foreach (var w in windows)
        {
            Console.WriteLine($"  [{w.Id}] {w.DisplayName} ({w.Bounds.Width}x{w.Bounds.Height})");
        }
        Console.WriteLine();

        Console.WriteLine("Available displays:");
        var displays = _screenshotService.GetDisplays();
        foreach (var (index, frame) in displays)
        {
            Console.WriteLine($"  Display {index}: {frame.Width}x{frame.Height} at ({frame.X},{frame.Y})");
        }
        Console.WriteLine();

        if (args.Length > 0 && File.Exists(args[0]))
        {
            Console.WriteLine($"Processing image: {args[0]}");
            await ProcessImageFile(args[0]);
        }
        else
        {
            Console.WriteLine("Usage: Textractor.exe [--console] <image-file>");
            Console.WriteLine("   or: Textractor.exe (runs in system tray)");
        }

        _ocrService!.Dispose();
        _soundManager!.Dispose();
        _toastService!.Dispose();
        
        Console.WriteLine();
        Console.WriteLine("Press any key to exit...");
        try { Console.ReadKey(); } catch { Thread.Sleep(2000); }
    }
    
    static async Task ProcessImageFileAndExit(string filePath)
    {
        InitializeServices();
        await ProcessImageFile(filePath);
        _ocrService!.Dispose();
        _soundManager!.Dispose();
        _toastService!.Dispose();
    }
    
    static async Task ProcessImageFile(string filePath)
    {
        try
        {
            using var bitmap = new Bitmap(filePath);
            Console.WriteLine($"Image loaded: {bitmap.Width}x{bitmap.Height}");

            Console.WriteLine("Running OCR...");
            var ocrResult = await _ocrService!.RecognizeText(
                bitmap,
                _settings!.Weirdness,
                _settings.CustomVocabulary);

            if (ocrResult.IsEmpty)
            {
                Console.WriteLine("No text detected.");
                return;
            }

            Console.WriteLine($"OCR completed in {ocrResult.RecognizedAtSeconds:F2}s");
            Console.WriteLine($"Found {ocrResult.RawObservations.Count} text regions");
            Console.WriteLine($"Average confidence: {ocrResult.AverageConfidence:P1}");
            Console.WriteLine();

            Console.WriteLine("Running AI analysis...");
            var analysis = await _aiService!.Analyze(ocrResult.JoinedText, _settings.Weirdness);

            string finalText = ocrResult.JoinedText;
            if (_settings.WindowCaptureAsTable)
            {
                var table = TableFormatter.ToMarkdownTable(ocrResult.RawObservations);
                if (!string.IsNullOrEmpty(table))
                {
                    finalText = table;
                }
            }

            finalText = PasteFormatter.Format(finalText, _settings.WordWrapCaptured, _settings.FlattenText);

            Console.WriteLine();
            Console.WriteLine("═══ EXTRACTED TEXT ═══");
            Console.WriteLine(finalText);
            Console.WriteLine("══════════════════════");
            Console.WriteLine();

            Console.WriteLine($"Language: {analysis.Language?.ToUpper() ?? "EN"}");
            Console.WriteLine($"Sentiment: {analysis.Sentiment} ({GetSentimentColor(analysis.Sentiment)})");
            Console.WriteLine($"Keywords: {string.Join(", ", analysis.Keywords.Take(5))}");
            Console.WriteLine($"Tokens: {analysis.Tokens}");
            Console.WriteLine();

            var capture = new CapturedImage
            {
                Mode = CaptureMode.File,
                Origin = CaptureOrigin.File,
                Rect = new RectangleF(0, 0, bitmap.Width, bitmap.Height),
                FilePath = filePath,
                CapturedAt = DateTimeOffset.Now
            };
            
            _historyStore!.Record(capture, finalText, CaptureMode.File, _settings!.HistoryEntryLimit);
            Console.WriteLine("Saved to history.");
            Console.WriteLine("Text ready for clipboard.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
        }
    }
    
    static string GetSentimentColor(AIInferenceService.Sentiment sentiment)
    {
        return sentiment switch
        {
            AIInferenceService.Sentiment.Positive => "Lime",
            AIInferenceService.Sentiment.Negative => "Red",
            AIInferenceService.Sentiment.Mixed => "Violet",
            _ => "Cyan"
        };
    }
    
    static void ShowHelp()
    {
        Console.WriteLine("Textractor - On-device OCR for Windows");
        Console.WriteLine();
        Console.WriteLine("Usage:");
        Console.WriteLine("  Textractor.exe                 Run in system tray (default)");
        Console.WriteLine("  Textractor.exe --console       Run in console mode");
        Console.WriteLine("  Textractor.exe <image-file>    Process image and exit");
        Console.WriteLine("  Textractor.exe --help          Show this help");
        Console.WriteLine();
        Console.WriteLine("System Tray:");
        Console.WriteLine("  Alt+Shift+2    Capture region (click and drag)");
        Console.WriteLine("  Alt+Shift+3    Capture window (click window)");
        Console.WriteLine("  Right-click     Show menu");
        Console.WriteLine("  Double-click    Capture region");
    }
    
    static void LogInfo(string message) => Console.WriteLine($"[INFO] {message}");
    static void LogWarning(string message) => Console.WriteLine($"[WARN] {message}");
    static void LogError(string message, Exception? ex = null)
    {
        Console.WriteLine($"[ERROR] {message}");
        if (ex != null) Console.WriteLine(ex.ToString());
    }
}

/// <summary>
/// Dark color table for context menu
/// </summary>
class DarkColorTable : ProfessionalColorTable
{
    public override Color MenuBorder => Color.FromArgb(0x2A, 0x2D, 0x44);
    public override Color MenuItemBorder => UI.AppTheme.Green;
    public override Color MenuItemSelected => UI.AppTheme.Background;
    public override Color MenuItemSelectedGradientBegin => Color.FromArgb(0x20, 0x37, 0xF2, 0xFF);
    public override Color MenuItemSelectedGradientEnd => UI.AppTheme.Background;
    public override Color ToolStripDropDownBackground => Color.FromArgb(0x12, 0x13, 0x24);
    public override Color SeparatorDark => Color.FromArgb(0x2A, 0x2D, 0x44);
    public override Color SeparatorLight => Color.FromArgb(0x2A, 0x2D, 0x44);
}

/// <summary>
/// Toast view model for system tray
/// </summary>
public class ToastViewModel
{
    public string Title { get; set; } = "";
    public string Message { get; set; } = "";
    public ToastKind Kind { get; set; }
    public ToastSentiment Sentiment { get; set; }
    public int DurationSeconds { get; set; } = 8;
}

/// <summary>
/// Windows API for message window
/// </summary>
static class NativeMethods
{
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern ushort RegisterClass(ref WNDCLASS lpWndClass);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr CreateWindowEx(
        uint dwExStyle,
        string lpClassName,
        string lpWindowName,
        uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        IntPtr hWndParent,
        IntPtr hMenu,
        IntPtr hInstance,
        IntPtr lpParam);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr DefWindowProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);
    
    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr GetModuleHandle(string? lpModuleName);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    
    [DllImport("kernel32.dll")]
    public static extern bool AttachConsole(int dwProcessId);
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
struct WNDCLASS
{
    public uint style;
    public IntPtr lpfnWndProc;
    public int cbClsExtra;
    public int cbWndExtra;
    public IntPtr hInstance;
    public IntPtr hIcon;
    public IntPtr hCursor;
    public IntPtr hbrBackground;
    public string? lpszMenuName;
    public string lpszClassName;
}

static class TrayHotkeyManager
{
    private static IntPtr _windowHandle = IntPtr.Zero;
    private static Action<CaptureMode>? _callback;
    private const int WM_HOTKEY = 0x0312;
    private const int REGION_HOTKEY_ID = 1;
    private const int WINDOW_HOTKEY_ID = 2;
    
    public static void Initialize(IntPtr windowHandle, Action<CaptureMode> callback)
    {
        _windowHandle = windowHandle;
        _callback = callback;
    }
    
    public static bool RegisterHotkeys(AppSettings settings)
    {
        if (_windowHandle == IntPtr.Zero) return false;
        
        // Unregister existing hotkeys
        NativeMethods.UnregisterHotKey(_windowHandle, REGION_HOTKEY_ID);
        NativeMethods.UnregisterHotKey(_windowHandle, WINDOW_HOTKEY_ID);
        
        bool success = true;
        
        // Register region capture hotkey (Alt+Shift+2)
        var regionModifiers = settings.RegionCaptureModifiers;
        var regionKeyCode = settings.RegionCaptureKeyCode;
        
        if (regionModifiers == 0 && regionKeyCode == 0)
        {
            regionModifiers = 0x0005; // MOD_ALT | MOD_SHIFT
            regionKeyCode = 0x32; // '2'
        }
        
        success &= NativeMethods.RegisterHotKey(_windowHandle, REGION_HOTKEY_ID, regionModifiers, regionKeyCode);
        
        // Register window capture hotkey (Alt+Shift+3)
        var windowModifiers = settings.WindowCaptureModifiers;
        var windowKeyCode = settings.WindowCaptureKeyCode;
        
        if (windowModifiers == 0 && windowKeyCode == 0)
        {
            windowModifiers = 0x0005; // MOD_ALT | MOD_SHIFT
            windowKeyCode = 0x33; // '3'
        }
        
        success &= NativeMethods.RegisterHotKey(_windowHandle, WINDOW_HOTKEY_ID, windowModifiers, windowKeyCode);
        
        return success;
    }
    
    public static void Stop()
    {
        if (_windowHandle != IntPtr.Zero)
        {
            NativeMethods.UnregisterHotKey(_windowHandle, REGION_HOTKEY_ID);
            NativeMethods.UnregisterHotKey(_windowHandle, WINDOW_HOTKEY_ID);
        }
    }
    
    public static void ProcessHotkey(int hotkeyId)
    {
        if (hotkeyId == REGION_HOTKEY_ID)
        {
            _callback?.Invoke(CaptureMode.Crosshair);
        }
        else if (hotkeyId == WINDOW_HOTKEY_ID)
        {
            _callback?.Invoke(CaptureMode.Window);
        }
    }
}

