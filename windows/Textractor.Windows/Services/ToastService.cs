using System;
using System.Drawing;
using System.Threading.Tasks;
using System.Windows.Forms;
using Textractor.Windows.Models;
using Textractor.Windows.UI;

namespace Textractor.Windows.Services;

public class ToastService : IDisposable
{
    private static ToastService? _instance;
    public static ToastService Shared => _instance ??= new ToastService();
    private Control? _dispatcher;
    private Form? _current;
    private ToastService() { }
    public void Initialize(Control? dispatcher = null) => _dispatcher = dispatcher;

    private void OnUi(Action action)
    {
        if (_dispatcher == null || _dispatcher.IsDisposed) return;
        if (_dispatcher.InvokeRequired) _dispatcher.BeginInvoke(action); else action();
    }

    public void ShowToast(ToastViewModel toast) => ShowToast(toast.Title, toast.Message, toast.Kind, toast.Sentiment, toast.DurationSeconds);
    public void ShowToast(string title, string message, ToastKind kind = ToastKind.Info,
        ToastSentiment sentiment = ToastSentiment.Neutral, int durationSeconds = 8)
    {
        Console.WriteLine($"[TOAST] {title}: {message}");
        OnUi(() =>
        {
            _current?.Close();
            var form = CreateToast(title, message);
            _current = form;
            var timer = new Timer { Interval = Math.Max(1, durationSeconds) * 1000 };
            timer.Tick += (_, _) => form.Close();
            form.FormClosed += (_, _) => timer.Dispose();
            form.Show(); timer.Start();
        });
    }

    private static Form CreateToast(string title, string message)
    {
        var form = new NotificationForm();
        AppTheme.Apply(form, title, new Size(340, 148));
        form.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        form.ShowInTaskbar = false; form.TopMost = true;
        form.StartPosition = FormStartPosition.Manual;
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        form.Location = new Point(area.Right - form.Width - 16, area.Bottom - form.Height - 16);
        form.Controls.Add(new Label { Text = message, ForeColor = AppTheme.Ink,
            Dock = DockStyle.Top, Height = 80, Padding = new Padding(16, 12, 16, 0), AutoEllipsis = true });
        return form;
    }

    public Task<StorageDecision> RequestStorageDecisionAsync(int seconds)
    {
        if (_dispatcher == null || _dispatcher.IsDisposed) return Task.FromResult(StorageDecision.Delete);
        var completion = new TaskCompletionSource<StorageDecision>(TaskCreationOptions.RunContinuationsAsynchronously);
        OnUi(() =>
        {
            int remaining = Math.Max(1, seconds);
            var form = CreateToast("Save Screenshot?", $"Save this capture, or delete it. Auto-delete in {remaining}s.");
            var caption = (Label)form.Controls[0];
            var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(12, 4, 0, 0) };
            var save = AppTheme.Row("Save", "\uE74E", () => { completion.TrySetResult(StorageDecision.SaveToFolder); form.Close(); });
            var delete = AppTheme.Row("Delete", "\uE74D", () => { completion.TrySetResult(StorageDecision.Delete); form.Close(); }, true);
            save.Width = 145; delete.Width = 145;
            buttons.Controls.Add(save); buttons.Controls.Add(delete); form.Controls.Add(buttons);
            var timer = new Timer { Interval = 1000 };
            timer.Tick += (_, _) =>
            {
                remaining--;
                caption.Text = $"Save this capture, or delete it. Auto-delete in {remaining}s.";
                if (remaining <= 0) form.Close();
            };
            form.FormClosed += (_, _) => { timer.Dispose(); completion.TrySetResult(StorageDecision.Delete); };
            form.Show(); timer.Start();
        });
        return completion.Task;
    }

    public void ShowSuccessToast(string title, string message, ToastSentiment sentiment = ToastSentiment.Positive, int durationSeconds = 8) =>
        ShowToast(title, message, ToastKind.Success, sentiment, durationSeconds);
    public void ShowErrorToast(string title, string message, int durationSeconds = 9) =>
        ShowToast(title, message, ToastKind.Error, ToastSentiment.Negative, durationSeconds);
    public void ShowStorageDecisionToast(CapturedImage capture, AppSettings settings, Action<StorageDecision> onDecision)
    {
        _ = DecideAsync();
        async Task DecideAsync() => onDecision(await RequestStorageDecisionAsync(settings.StorageDecisionTimeoutSeconds));
    }
    public void DismissCurrentToast() => OnUi(() => _current?.Close());
    public void Dispose() { DismissCurrentToast(); _instance = null; }
    private sealed class NotificationForm : Form
    {
        protected override bool ShowWithoutActivation => true;
    }
}
