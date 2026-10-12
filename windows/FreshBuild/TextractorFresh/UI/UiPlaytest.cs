using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows;

partial class Program
{
    // Runs the actual forms and OCR pipeline on a Windows message loop.
    // Settings, history, captures and logs are isolated in the requested output folder.
    static int RunUiPlaytest(string output)
    {
        output = Path.GetFullPath(output);
        Directory.CreateDirectory(output);
        Environment.SetEnvironmentVariable("TEXTRACTOR_DATA_DIR", Path.Combine(output, "data", Guid.NewGuid().ToString("N")));
        InitializeServices();
        _settings!.AutoPasteEnabled = false;
        _settings.SoundEffectsEnabled = false;
        _settings.StorageDecision = StorageDecision.Delete;
        var checks = new List<string>();
        Exception? failure = null;
        using var main = new MainForm();
        _mainForm = main;
        _toastService!.Initialize(main);
        var originalClipboard = new DataObject();
        try
        {
            var original = Clipboard.GetDataObject();
            if (original != null)
                foreach (var format in original.GetFormats(false))
                {
                    try { var data = original.GetData(format, false); if (data != null) originalClipboard.SetData(format, data); } catch { }
                }
        }
        catch { }

        void Check(bool passed, string name)
        {
            if (!passed) throw new InvalidOperationException(name);
            checks.Add(name);
            Console.WriteLine($"PASS: {name}");
        }
        async Task Snapshot(Form form, string filename)
        {
            bool wasTopMost = form.TopMost;
            try
            {
                // A hidden process launch can suppress a window's first native ShowWindow.
                form.Hide(); form.Show();
                form.TopMost = true; form.BringToFront(); form.Activate(); form.Refresh();
                await Task.Delay(200);
                using var bitmap = new Bitmap(form.Width, form.Height);
                using (var graphics = Graphics.FromImage(bitmap))
                    graphics.CopyFromScreen(form.Location, Point.Empty, form.Size);
                bitmap.Save(Path.Combine(output, filename), ImageFormat.Png);
            }
            finally { form.TopMost = wasTopMost; }
        }
        async Task WaitCapture()
        {
            for (int i = 0; i < 200 && _captureBusy; i++) await Task.Delay(50);
            Check(!_captureBusy, "Capture completes without hanging");
        }
        void SelectOnNextOverlay(Action<UI.CaptureSelectionForm> action)
        {
            var timer = new System.Windows.Forms.Timer { Interval = 100 };
            int ticks = 0;
            timer.Tick += (_, _) =>
            {
                var selector = Application.OpenForms.OfType<UI.CaptureSelectionForm>().FirstOrDefault();
                if (selector == null && ++ticks < 50) return;
                timer.Stop(); timer.Dispose();
                if (selector != null) action(selector);
            };
            timer.Start();
        }
        main.Shown += async (_, _) =>
        {
            try
            {
                await Task.Delay(200);
                var titles = main.Actions.Select(b => b.Text).ToArray();
                Check(titles.SequenceEqual(new[] { "Region", "Window", "Full Screen", "Pick Image File…", "History", "Settings…", "Quit Textractor" }), "Menu matches macOS action order");
                Check(main.Controls.OfType<PictureBox>().Single().Image != null, "Original macOS wordmark is bundled");
                Check(main.Actions.All(b => b.Visible && b.Parent!.ClientRectangle.Contains(b.Bounds)), "Every menu action fits without scrolling");
                Check(Math.Abs(main.ClientSize.Width - 232 * main.DeviceDpi / 96f) <= 2, "Menu retains macOS 232-point logical width at current DPI");
                main.Actions[0].Focus();
                Check(main.Actions[0].Focused && main.SelectNextControl(main.Actions[0], true, true, true, false) && main.Actions[1].Focused, "Keyboard tab order reaches capture actions");
                await Snapshot(main, "menu.png");

                main.Actions[5].PerformClick();
                await Task.Delay(100);
                Check(_preferences != null && _preferences.Visible, "Settings button opens a real window");
                await Snapshot(_preferences!, "settings.png");
                var plain = _settings.PasteAsPlainText;
                _preferences!.PlainText.Checked = !plain;
                _preferences.Flatten.Checked = true;
                _settingsStore!.Load();
                Check(_settingsStore.Settings.PasteAsPlainText == !plain && _settingsStore.Settings.FlattenText, "Settings changes persist to disk");
                _preferences.Close();
                _settings = _settingsStore.Settings;
                _settings.PasteAsPlainText = true;
                _settings.FlattenText = false;
                _settings.AutoPasteEnabled = false;

                main.Actions[4].PerformClick();
                Check(_library != null && _library.Visible && _library.Entries.Items.Count == 0 && !_library.Copy.Enabled, "Empty history has useful guidance and disables Copy");
                await Snapshot(_library!, "history-empty.png");
                _library!.Close();

                Check(_ocrService!.IsReady, "Tesseract initializes with installed language data");
                using var fixture = new Bitmap(840, 180);
                using (var graphics = Graphics.FromImage(fixture))
                using (var font = new Font("Arial", 30))
                {
                    graphics.Clear(Color.White);
                    graphics.DrawString("Textractor ready for duty", font, Brushes.Black, 25, 55);
                }
                var fixturePath = Path.Combine(output, "ocr-fixture.png");
                fixture.Save(fixturePath, ImageFormat.Png);
                var fileCapture = await _screenshotService!.CaptureFromFileAsync(fixturePath);
                await ProcessCapture(fileCapture, CaptureMode.File);
                Check(ClipboardService.GetText()?.Contains("ready for duty", StringComparison.OrdinalIgnoreCase) == true, "Image import performs real OCR and copies recognized text");
                Check(!File.Exists(fileCapture.FilePath) && File.Exists(fixturePath), "Auto-delete removes the temporary import and preserves the original file");

                ShowHistory();
                Check(_library!.Entries.Items.Count == 1, "Successful extraction appears in History");
                _library.Search.Text = "duty";
                Check(_library.Entries.Items.Count == 1 && _library.Preview.Text.Contains("duty"), "History search finds extracted text and shows the preview");
                _library.Copy.PerformClick();
                Check(ClipboardService.GetText() == _library.Preview.Text, "History Copy writes selected text to the clipboard");
                await Snapshot(_library, "history.png");
                _library.Search.Text = "no-match-98765";
                Check(_library.Entries.Items.Count == 0 && !_library.Copy.Enabled, "No-match history search disables Copy");
                _library.Close();
                _toastService.DismissCurrentToast();

                main.Show(); main.Activate();
                var count = _historyStore!.GetRecent(20).Count;
                SelectOnNextOverlay(selector => SendUiMessage(selector.Handle, 0x0100, (IntPtr)Keys.Escape, IntPtr.Zero));
                main.Actions[0].PerformClick();
                await WaitCapture();
                Check(_historyStore.GetRecent(20).Count == count, "Escape cancels region capture without creating history");

                using var target = new Form { Text = "Textractor playtest target", ClientSize = fixture.Size, StartPosition = FormStartPosition.CenterScreen, TopMost = true };
                target.Controls.Add(new PictureBox { Dock = DockStyle.Fill, Image = fixture, SizeMode = PictureBoxSizeMode.Normal });
                target.Show(); target.BringToFront(); target.Activate(); await Task.Delay(200);
                var targetOrigin = target.PointToScreen(Point.Empty);
                var targetRegion = new Rectangle(targetOrigin, target.ClientSize);
                SelectOnNextOverlay(selector =>
                {
                    var start = selector.PointToClient(targetRegion.Location);
                    var end = new Point(start.X + targetRegion.Width, start.Y + targetRegion.Height);
                    SendUiMessage(selector.Handle, 0x0201, (IntPtr)1, MousePosition(start));
                    SendUiMessage(selector.Handle, 0x0200, (IntPtr)1, MousePosition(end));
                    SendUiMessage(selector.Handle, 0x0202, IntPtr.Zero, MousePosition(end));
                });
                TriggerCapture(CaptureMode.Crosshair);
                await WaitCapture();
                var regionRecord = _historyStore.GetRecent(1).Single();
                Check(_historyStore.GetRecent(20).Count == count + 1 && regionRecord.Text.Contains("duty", StringComparison.OrdinalIgnoreCase), "Drag-selected screen region performs OCR");
                Check(regionRecord.CaptureInfo.Rect.Width == targetRegion.Width && regionRecord.CaptureInfo.Rect.Height == targetRegion.Height, "Region capture uses the selected rectangle rather than the full display");
                _toastService.DismissCurrentToast();
                target.Activate();
                SelectOnNextOverlay(selector =>
                {
                    var click = selector.PointToClient(new Point(targetOrigin.X + 60, targetOrigin.Y + 70));
                    SendUiMessage(selector.Handle, 0x0201, (IntPtr)1, MousePosition(click));
                });
                TrayHotkeyManager.Initialize(main.Handle, TriggerCapture);
                TrayHotkeyManager.ProcessHotkey(2);
                await WaitCapture();
                Check(_historyStore.GetRecent(20).Count == count + 2 && _historyStore.GetRecent(1)[0].Mode == CaptureMode.Window, "Window hotkey dispatches window selection and extraction");
                _toastService.DismissCurrentToast();
                target.Close();

                var ask = _toastService.RequestStorageDecisionAsync(1);
                await Task.Delay(100);
                await Snapshot(Application.OpenForms.Cast<Form>().Single(f => f.Text == "Save Screenshot?"), "storage.png");
                Check(await ask == StorageDecision.Delete, "Unanswered screenshot prompt defaults to delete");
                var saveDecision = _toastService.RequestStorageDecisionAsync(5);
                var prompt = Application.OpenForms.Cast<Form>().Single(f => f.Text == "Save Screenshot?");
                prompt.Controls.OfType<FlowLayoutPanel>().Single().Controls.OfType<Button>().Single(b => b.Text == "Save").PerformClick();
                Check(await saveDecision == StorageDecision.SaveToFolder, "Screenshot Save button resolves the storage choice");
                main.Show(); main.Activate();
                main.WindowState = FormWindowState.Minimized;
                main.Close();
                Check(!main.IsDisposed && !main.Visible, "Closing the main window preserves the tray application");
                RestoreMainWindow();
                Check(main.Visible && main.WindowState == FormWindowState.Normal, "Tray restore returns the main window");
            }
            catch (Exception ex) { failure = ex; Console.Error.WriteLine(ex); }
            finally
            {
                try { Clipboard.SetDataObject(originalClipboard, true); } catch { }
                File.WriteAllText(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new
                {
                    Passed = failure == null, Dpi = main.DeviceDpi, Checks = checks,
                    Error = failure?.ToString(), Limitations = new[] { "macOS runtime unavailable", "Only attached display configuration tested", "Global shortcut registration and external auto-paste require manual verification" }
                }, new JsonSerializerOptions { WriteIndented = true }));
                _isShuttingDown = true;
                foreach (var form in Application.OpenForms.Cast<Form>().Where(f => f != main).ToArray()) form.Close();
                main.Close();
            }
        };
        Application.Run(main);
        _ocrService?.Dispose(); _soundManager?.Dispose(); _toastService?.Dispose();
        return failure == null ? 0 : 1;
    }

    private static IntPtr MousePosition(Point point) => (IntPtr)((point.Y << 16) | (point.X & 0xffff));
    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern IntPtr SendUiMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
