using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows.UI;

// Geometry, artwork and section order follow MenuContentView/SettingsView.swift.
// Use Windows controls, fonts, focus cues and title bars for native interaction.
internal static class AppTheme
{
    internal static readonly Color Background = Color.FromArgb(13, 16, 11);
    internal static readonly Color Ink = Color.FromArgb(230, 234, 220);
    internal static readonly Color Muted = Color.FromArgb(160, 169, 151);
    internal static readonly Color Green = Color.FromArgb(107, 181, 52);

    internal static void Apply(Form form, string title, Size size)
    {
        form.Text = title;
        form.AutoScaleDimensions = new SizeF(96, 96);
        form.AutoScaleMode = AutoScaleMode.Dpi;
        form.ClientSize = size;
        form.BackColor = Background;
        form.ForeColor = Ink;
        form.Font = new Font("Segoe UI", 9.75f);
        form.StartPosition = FormStartPosition.CenterScreen;
        form.FormBorderStyle = FormBorderStyle.FixedSingle;
        form.MaximizeBox = false;
        form.KeyPreview = true;
        var icon = Path.Combine(AppContext.BaseDirectory, "app.ico");
        try { if (File.Exists(icon)) form.Icon = new Icon(icon); }
        catch (System.ComponentModel.Win32Exception) { form.Icon = SystemIcons.Application; }
        catch (ArgumentException) { form.Icon = SystemIcons.Application; }
        form.KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) { form.Close(); e.Handled = true; } };
    }

    internal static PictureBox Banner()
    {
        var banner = new PictureBox { Dock = DockStyle.Top, Height = 60, SizeMode = PictureBoxSizeMode.Zoom,
            BackColor = Background, AccessibleName = "Textractor wordmark", TabStop = false };
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", "textractor-type.png");
        if (File.Exists(path))
        {
            using var source = Image.FromFile(path);
            banner.Image = new Bitmap(source);
            banner.Disposed += (_, _) => banner.Image?.Dispose();
        }
        return banner;
    }

    internal static Label Section(string title, int width = 216) => new()
    {
        Text = title.ToUpperInvariant(), Width = width, Height = 23,
        Padding = new Padding(10, 7, 0, 0), ForeColor = Muted,
        Font = new Font("Segoe UI", 7.5f, FontStyle.Bold), Margin = Padding.Empty
    };

    internal static Button Row(string title, string symbol, Action action, bool destructive = false)
    {
        var button = new MenuButton(symbol) { Text = title, AccessibleName = title,
            Width = 216, Height = 31, Margin = new Padding(0, 1, 0, 0),
            ForeColor = destructive ? Color.Salmon : Ink, BackColor = Background,
            FlatStyle = FlatStyle.Flat, TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(34, 0, 4, 0), Cursor = Cursors.Hand, UseVisualStyleBackColor = false };
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.MouseOverBackColor = destructive ? Color.FromArgb(140, 42, 30) : Color.FromArgb(46, 92, 28);
        button.FlatAppearance.MouseDownBackColor = Color.FromArgb(64, 112, 36);
        button.Click += (_, _) => action();
        return button;
    }

    private sealed class MenuButton(string symbol) : Button
    {
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using var symbolFont = new Font("Segoe MDL2 Assets", 10);
            TextRenderer.DrawText(e.Graphics, symbol, symbolFont, new Rectangle(9, 0, 21, Height),
                ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter);
        }
    }

    internal static FlowLayoutPanel Stack(int width = 232) => new()
    {
        Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
        Padding = new Padding(8, 0, 8, 4), BackColor = Background, AutoScroll = false,
        Width = width
    };
}

internal class MenuForm : Form
{
    internal readonly List<Button> Actions = new();
    internal MenuForm(Action<CaptureMode> capture, Action pickFile, Action history, Action settings, Action quit)
    {
        AppTheme.Apply(this, "Textractor", new Size(232, 391));
        var stack = AppTheme.Stack();
        void Row(string title, string symbol, Action action, bool destructive = false)
        {
            var button = AppTheme.Row(title, symbol, action, destructive);
            Actions.Add(button);
            stack.Controls.Add(button);
        }
        stack.Controls.Add(AppTheme.Section("Capture"));
        Row("Region", "\uE7B4", () => capture(CaptureMode.Crosshair));
        Row("Window", "\uE737", () => capture(CaptureMode.Window));
        Row("Full Screen", "\uE740", () => capture(CaptureMode.FullScreen));
        stack.Controls.Add(AppTheme.Section("Library"));
        Row("Pick Image File…", "\uEB9F", pickFile);
        Row("History", "\uE81C", history);
        stack.Controls.Add(AppTheme.Section("App"));
        Row("Settings…", "\uE713", settings);
        stack.Controls.Add(new Panel { Width = 216, Height = 1, BackColor = Color.FromArgb(52, 62, 45), Margin = new Padding(0, 6, 0, 5) });
        Row("Quit Textractor", "\uE7E8", quit, true);
        stack.Controls.Add(new Label { Text = "v2.0.0 · Windows", ForeColor = AppTheme.Muted,
            Font = new Font("Consolas", 7), TextAlign = ContentAlignment.MiddleCenter,
            Width = 216, Height = 22, Margin = Padding.Empty });
        Controls.Add(stack);
        Controls.Add(AppTheme.Banner());
        var tip = new ToolTip();
        tip.SetToolTip(Actions[0], "Drag a region · Alt+Shift+2 · Esc cancels");
        tip.SetToolTip(Actions[1], "Click a window · Alt+Shift+3 · Esc cancels");
        Disposed += (_, _) => tip.Dispose();
    }
}

internal sealed class PreferencesForm : Form
{
    internal readonly CheckBox PlainText;
    internal readonly CheckBox Flatten;
    internal readonly ComboBox Storage;
    internal readonly ComboBox Language;
    private readonly AppSettings _settings;
    private readonly Action _save;

    internal PreferencesForm(AppSettings settings, Action save, Action showHistory)
    {
        _settings = settings;
        _save = save;
        AppTheme.Apply(this, "Textractor Settings", new Size(232, 620));
        var footer = new Label { Text = "Changes save automatically", Dock = DockStyle.Bottom,
            Height = 26, TextAlign = ContentAlignment.MiddleCenter, ForeColor = AppTheme.Muted,
            Font = new Font("Segoe UI", 8) };
        var scroll = AppTheme.Stack();
        scroll.AutoScroll = true;
        int rowWidth = 198;
        void Section(string title) => scroll.Controls.Add(AppTheme.Section(title, rowWidth));
        CheckBox Toggle(string title, bool value, Action<bool> update)
        {
            var checkbox = new CheckBox { Text = title, AccessibleName = title, Width = rowWidth,
                Height = 38, Checked = value, Margin = Padding.Empty, ForeColor = AppTheme.Ink,
                Padding = new Padding(7, 0, 0, 0) };
            checkbox.CheckedChanged += (_, _) => { update(checkbox.Checked); _save(); };
            scroll.Controls.Add(checkbox);
            return checkbox;
        }
        void Caption(string text, int height = 40) => scroll.Controls.Add(new Label { Text = text, Width = rowWidth,
            Height = height, Padding = new Padding(8, 2, 4, 0), ForeColor = AppTheme.Muted,
            Font = new Font("Segoe UI", 8), Margin = Padding.Empty });
        Section("AI & Extraction");
        var intensity = new Label { Text = $"Inference weirdness · {settings.Weirdness:P0}", Width = rowWidth,
            Height = 28, Padding = new Padding(8, 4, 0, 0), Margin = Padding.Empty };
        scroll.Controls.Add(intensity);
        var slider = new TrackBar { Minimum = 0, Maximum = 100, Value = (int)Math.Clamp(settings.Weirdness * 100, 0, 100),
            Width = rowWidth, Height = 32, TickStyle = TickStyle.None, AccessibleName = "Inference weirdness", Margin = Padding.Empty };
        slider.ValueChanged += (_, _) => { settings.Weirdness = slider.Value / 100.0; intensity.Text = $"Inference weirdness · {slider.Value}%"; _save(); };
        scroll.Controls.Add(slider);
        Caption("Adjusts local text cleanup and keyword extraction.");
        Caption("OCR language", 26);
        Language = new ComboBox { Width = rowWidth - 12, DropDownStyle = ComboBoxStyle.DropDownList,
            ForeColor = SystemColors.WindowText, BackColor = SystemColors.Window,
            Margin = new Padding(6, 0, 0, 6), AccessibleName = "OCR language" };
        var languages = AppSettings.OcrLanguageCatalog.Where(x => OCRService.DataDirectories.Any(path => File.Exists(Path.Combine(path, x.Code + ".traineddata")))).ToList();
        if (languages.Count == 0) languages.Add(("eng", "English", ""));
        Language.Items.AddRange(languages.Select(x => (object)x.Name).ToArray());
        Language.SelectedIndex = Math.Max(0, languages.FindIndex(x => x.Code == settings.OcrLanguage));
        if (settings.OcrLanguage != languages[Language.SelectedIndex].Code) { settings.OcrLanguage = languages[Language.SelectedIndex].Code; _save(); }
        Language.SelectedIndexChanged += (_, _) => { settings.OcrLanguage = languages[Language.SelectedIndex].Code; _save(); };
        scroll.Controls.Add(Language);
        Section("Sharing");
        PlainText = Toggle("Paste as plain text", settings.PasteAsPlainText, v => settings.PasteAsPlainText = v);
        Toggle("Auto-paste after capture", settings.AutoPasteEnabled, v => settings.AutoPasteEnabled = v);
        Section("Window Captures");
        Toggle("Convert to markdown tables", settings.WindowCaptureAsTable, v => settings.WindowCaptureAsTable = v);
        Section("History");
        var history = AppTheme.Row("Open History", "\uE81C", showHistory); history.Width = rowWidth;
        scroll.Controls.Add(history);
        Section("Behaviour");
        Flatten = Toggle("Flatten text (no line breaks)", settings.FlattenText, v => settings.FlattenText = v);
        Toggle("Sound effects", settings.SoundEffectsEnabled, v => settings.SoundEffectsEnabled = v);
        Toggle("Local telemetry log", settings.LocalTelemetryEnabled, v => settings.LocalTelemetryEnabled = v);
        Section("Screenshots");
        Storage = new ComboBox { Width = rowWidth - 12, DropDownStyle = ComboBoxStyle.DropDownList,
            ForeColor = SystemColors.WindowText, BackColor = SystemColors.Window,
            AccessibleName = "Screenshot storage", Margin = new Padding(6, 4, 0, 4) };
        Storage.Items.AddRange(new object[] { "Ask each time", "Auto-delete", "Save to folder" });
        Storage.SelectedIndex = (int)settings.StorageDecision;
        Storage.SelectedIndexChanged += (_, _) => { settings.StorageDecision = (StorageDecision)Storage.SelectedIndex; _save(); };
        scroll.Controls.Add(Storage);
        Caption("Ask defaults to delete when the countdown ends.");
        var choose = AppTheme.Row("Choose folder…", "\uE8B7", () =>
        {
            using var picker = new FolderBrowserDialog { Description = "Screenshot folder", UseDescriptionForTitle = true };
            if (picker.ShowDialog(this) == DialogResult.OK)
            {
                settings.CustomScreenshotsFolder = picker.SelectedPath;
                Storage.SelectedIndex = (int)StorageDecision.SaveToFolder;
                _save();
            }
        });
        choose.Width = rowWidth; scroll.Controls.Add(choose);
        Section("About");
        Caption("Textractor · on-device OCR\nMade by Lucky Clover · v2.0.0");
        Controls.Add(scroll); Controls.Add(footer); Controls.Add(AppTheme.Banner());
        Height = Math.Min(Height, Screen.FromControl(this).WorkingArea.Height - 40);
    }

}

internal sealed class LibraryForm : Form
{
    internal readonly TextBox Search;
    internal readonly ListBox Entries;
    internal readonly TextBox Preview;
    internal readonly Button Copy;
    private readonly List<HistoryRecord> _records;
    internal LibraryForm(IEnumerable<HistoryRecord> records)
    {
        _records = records.ToList();
        AppTheme.Apply(this, "Textractor History", new Size(660, 460));
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimumSize = new Size(470, 350);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(12), ColumnCount = 2, RowCount = 3 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        Search = new TextBox { Dock = DockStyle.Fill, PlaceholderText = "Search extracted text…", AccessibleName = "Search history" };
        Entries = new ListBox { Dock = DockStyle.Fill, BackColor = AppTheme.Background, ForeColor = AppTheme.Ink,
            BorderStyle = BorderStyle.FixedSingle, AccessibleName = "Capture history", HorizontalScrollbar = true, IntegralHeight = false };
        Preview = new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both,
            BackColor = AppTheme.Background, ForeColor = AppTheme.Ink, BorderStyle = BorderStyle.FixedSingle, AccessibleName = "Extracted text" };
        Copy = AppTheme.Row("Copy text", "\uE8C8", () =>
        {
            Copy!.Text = ClipboardService.Copy(Preview.Text) ? "Copied to clipboard" : "Copy failed — try again";
        });
        Copy.Enabled = false; Copy.Dock = DockStyle.Fill;
        layout.Controls.Add(Search, 0, 0); layout.SetColumnSpan(Search, 2);
        layout.Controls.Add(Entries, 0, 1); layout.Controls.Add(Preview, 1, 1);
        layout.Controls.Add(Copy, 1, 2);
        layout.Controls.Add(new Label { Text = _records.Count == 0 ? "No captures yet" : $"{_records.Count} captures", Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft, ForeColor = AppTheme.Muted }, 0, 2);
        Search.TextChanged += (_, _) => RefreshEntries();
        Entries.SelectedIndexChanged += (_, _) =>
        {
            Preview.Text = (Entries.SelectedItem as HistoryItem)?.Record.Text ?? "";
            Copy.Enabled = Preview.Text.Length > 0;
            Copy.Text = "Copy text";
        };
        Controls.Add(layout);
        RefreshEntries();
    }
    private void RefreshEntries()
    {
        Entries.Items.Clear();
        foreach (var record in _records.Where(r => r.Text.Contains(Search.Text, StringComparison.OrdinalIgnoreCase)))
            Entries.Items.Add(new HistoryItem(record));
        if (Entries.Items.Count > 0) Entries.SelectedIndex = 0;
        else { Preview.Text = _records.Count == 0 ? "Your extracted text will appear here after a capture." : "No matching captures."; Copy.Enabled = false; }
    }
    private sealed record HistoryItem(HistoryRecord Record)
    {
        public override string ToString() => $"{Record.Timestamp.LocalDateTime:g} · {Record.Text.Replace('\n', ' ').Replace('\r', ' ')}";
    }
}

internal sealed class CaptureSelectionForm : Form
{
    private Point _anchor;
    private Rectangle _selection;
    private bool _dragging;
    private CaptureMode _mode;
    private readonly List<WindowDescriptor> _windows;
    internal Rectangle SelectedRegion { get; private set; }
    internal IntPtr SelectedWindow { get; private set; }
    internal CaptureMode SelectedMode => _mode;

    internal CaptureSelectionForm(CaptureMode mode, IEnumerable<WindowDescriptor> windows)
    {
        _mode = mode; _windows = windows.ToList();
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        Bounds = SystemInformation.VirtualScreen;
        ShowInTaskbar = false; TopMost = true; DoubleBuffered = true;
        BackColor = Color.Black; Opacity = 0.32; Cursor = Cursors.Cross; KeyPreview = true;
        AccessibleName = "Capture selector";
        KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape) { DialogResult = DialogResult.Cancel; Close(); }
            if (e.KeyCode == Keys.Space) { _mode = _mode == CaptureMode.Window ? CaptureMode.Crosshair : CaptureMode.Window; _selection = Rectangle.Empty; Invalidate(); }
        };
        MouseDown += (_, e) =>
        {
            if (e.Button != MouseButtons.Left) return;
            if (_mode == CaptureMode.Window)
            {
                var window = FindWindow(PointToScreen(e.Location));
                if (window != null) { SelectedWindow = window.Id; DialogResult = DialogResult.OK; Close(); }
            }
            else { _anchor = e.Location; _dragging = true; Capture = true; }
        };
        MouseMove += (_, e) =>
        {
            if (_mode == CaptureMode.Window)
            {
                var window = FindWindow(PointToScreen(e.Location));
                _selection = window == null ? Rectangle.Empty : Rectangle.Round(window.Bounds);
                _selection.Offset(-Left, -Top);
            }
            else if (_dragging) _selection = Rectangle.FromLTRB(Math.Min(_anchor.X, e.X), Math.Min(_anchor.Y, e.Y), Math.Max(_anchor.X, e.X), Math.Max(_anchor.Y, e.Y));
            Invalidate();
        };
        MouseUp += (_, e) =>
        {
            if (!_dragging || e.Button != MouseButtons.Left) return;
            _dragging = false; Capture = false;
            if (_selection.Width < 4 || _selection.Height < 4) return;
            SelectedRegion = _selection; SelectedRegion = new Rectangle(PointToScreen(SelectedRegion.Location), SelectedRegion.Size);
            DialogResult = DialogResult.OK; Close();
        };
    }
    private WindowDescriptor? FindWindow(Point point) => _windows.FirstOrDefault(w => w.IsCaptureEligible && w.Bounds.Contains(point));
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var pen = new Pen(Color.Lime, 3);
        if (!_selection.IsEmpty) e.Graphics.DrawRectangle(pen, _selection);
        var mouse = PointToClient(Cursor.Position);
        var label = $"{(_mode == CaptureMode.Window ? "Click a window" : "Drag to select a region")}   ·   Space: switch mode   ·   Esc: cancel";
        using var font = new Font("Segoe UI", 12, FontStyle.Bold);
        var monitor = Screen.FromPoint(Cursor.Position).Bounds;
        TextRenderer.DrawText(e.Graphics, label, font, new Point(monitor.Left - Left + 24, monitor.Top - Top + 24), Color.White);
        if (_mode == CaptureMode.Crosshair)
        {
            e.Graphics.DrawLine(pen, mouse.X - 12, mouse.Y, mouse.X + 12, mouse.Y);
            e.Graphics.DrawLine(pen, mouse.X, mouse.Y - 12, mouse.X, mouse.Y + 12);
        }
    }
}
