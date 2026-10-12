using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Windowing;
using System;
using System.Threading.Tasks;
using Windows.Graphics;
using Windows.UI;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows.Views;

public sealed partial class ToastNotificationWindow : Window
{
    private readonly DispatcherTimer _dismissTimer = new();
    private ToastState? _currentToast;
    private bool _isAnimating = false;

    public ToastNotificationWindow()
    {
        this.InitializeComponent();
        
        this.ExtendsContentIntoTitleBar = true;
        this.AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        
        // Position at top-right of primary screen
        PositionAtTopRight();
        
        _dismissTimer.Interval = TimeSpan.FromSeconds(6.5);
        _dismissTimer.Tick += DismissTimer_Tick;
    }

    public async Task ShowToastAsync(ToastState toast)
    {
        _currentToast = toast;
        UpdateToastUI(toast);
        
        this.Activate();
        
        // Animate in
        await AnimateInAsync();
        
        // Start dismiss timer
        var delay = toast.Kind == "failure" ? TimeSpan.FromSeconds(9) : TimeSpan.FromSeconds(6.5);
        _dismissTimer.Interval = delay;
        _dismissTimer.Start();
    }

    private void UpdateToastUI(ToastState toast)
    {
        // Set border color based on kind
        var borderColor = toast.Kind switch
        {
            "success" => BreakingDadToxicGreenBrush,
            "failure" => BreakingDadRustBrush,
            "info" => BreakingDadMethBlueBrush,
            _ => BreakingDadToxicGreenBrush
        };
        
        ToastBorder.BorderBrush = borderColor;
        
        // Status icon
        if (toast.Kind == "success")
        {
            StatusIconBackground.Color = Colors.Green;
            StatusIcon.Glyph = "\uE73E"; // Checkmark
            StatusIcon.Foreground = new SolidColorBrush(Colors.White);
        }
        else if (toast.Kind == "failure")
        {
            StatusIconBackground.Color = Colors.Red;
            StatusIcon.Glyph = "\uE7BA"; // Exclamation triangle
            StatusIcon.Foreground = new SolidColorBrush(Colors.White);
        }
        else
        {
            StatusIconBackground.Color = Colors.Blue;
            StatusIcon.Glyph = "\uE8C8"; // Clipboard
            StatusIcon.Foreground = new SolidColorBrush(Colors.White);
        }
        
        // Headline & timestamp
        HeadlineText.Text = toast.Headline;
        if (toast.Capture != null)
        {
            TimestampText.Text = $"Captured at {toast.Capture.CapturedAt:t}";
            TimestampText.Visibility = Visibility.Visible;
        }
        else
        {
            TimestampText.Visibility = Visibility.Collapsed;
        }
        
        // Body
        if (!string.IsNullOrEmpty(toast.Body))
        {
            BodyText.Text = toast.Body;
            BodyText.Visibility = Visibility.Visible;
        }
        else
        {
            BodyText.Visibility = Visibility.Collapsed;
        }
        
        // Analysis chips
        if (toast.Analysis != null)
        {
            UpdateAnalysisChips(toast.Analysis);
            AnalysisPanel.Visibility = Visibility.Visible;
        }
        else
        {
            AnalysisPanel.Visibility = Visibility.Collapsed;
        }
        
        // Action panels based on kind and state
        StorageActionsPanel.Visibility = Visibility.Collapsed;
        ActionRowPanel.Visibility = Visibility.Collapsed;
        FailureActionsPanel.Visibility = Visibility.Collapsed;
        PermissionActionsPanel.Visibility = Visibility.Collapsed;
        
        if (toast.Kind == "success" && toast.StorageQuestion != StorageDecision.None)
        {
            // Ask mode - show storage actions
            StorageActionsPanel.Visibility = Visibility.Visible;
            AlwaysSaveButton.Visibility = 
                SettingsStore.Shared.Settings.DockPresence == DockPresence.MenuBarOnly ? 
                Visibility.Visible : Visibility.Collapsed;
        }
        else if (toast.Kind == "success")
        {
            // Normal success - show copy + share
            ActionRowPanel.Visibility = Visibility.Visible;
        }
        else if (toast.Kind == "failure")
        {
            FailureActionsPanel.Visibility = Visibility.Visible;
            RevealRecoveryButton.Visibility = !string.IsNullOrEmpty(toast.RecoveryImagePath) 
                ? Visibility.Visible : Visibility.Collapsed;
        }
        else if (toast.ScreenRecordingDenied)
        {
            PermissionActionsPanel.Visibility = Visibility.Visible;
        }
    }

    private void UpdateAnalysisChips(AIInferenceService.Analysis analysis)
    {
        // Sentiment
        var sentimentColor = analysis.Sentiment switch
        {
            AIInferenceService.Sentiment.Positive => Colors.Green,
            AIInferenceService.Sentiment.Negative => Colors.Red,
            AIInferenceService.Sentiment.Neutral => Colors.Blue,
            AIInferenceService.Sentiment.Mixed => Colors.Purple,
            _ => Colors.Blue
        };
        
        SentimentIcon.Foreground = new SolidColorBrush(sentimentColor);
        SentimentIcon.Glyph = "\uE946"; // Waveform
        SentimentText.Text = analysis.Sentiment.ToString().ToUpper();
        SentimentText.Foreground = new SolidColorBrush(sentimentColor);
        SentimentChip.BorderBrush = new SolidColorBrush(sentimentColor);
        SentimentChip.Background = new SolidColorBrush(Color.FromArgb(0x1A, sentimentColor.R, sentimentColor.G, sentimentColor.B));
        
        // Language
        if (!string.IsNullOrEmpty(analysis.Language))
        {
            LanguageText.Text = analysis.Language.ToUpper();
            LanguageChip.Visibility = Visibility.Visible;
        }
        else
        {
            LanguageChip.Visibility = Visibility.Collapsed;
        }
        
        // Tokens
        TokensText.Text = $"{analysis.Tokens} TOKENS";
    }

    private async Task AnimateInAsync()
    {
        _isAnimating = true;
        
        var storyboard = new Storyboard();
        
        var opacityAnim = new DoubleAnimation { From = 0, To = 1, Duration = TimeSpan.FromSeconds(0.3) };
        var scaleXAnim = new DoubleAnimation { From = 0.9, To = 1.0, Duration = TimeSpan.FromSeconds(0.4), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        var scaleYAnim = new DoubleAnimation { From = 0.9, To = 1.0, Duration = TimeSpan.FromSeconds(0.4), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        var translateYAnim = new DoubleAnimation { From = -20, To = 0, Duration = TimeSpan.FromSeconds(0.4), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };

        Storyboard.SetTarget(opacityAnim, ToastBorder);
        Storyboard.SetTargetProperty(opacityAnim, "Opacity");
        
        Storyboard.SetTarget(scaleXAnim, ToastTransform);
        Storyboard.SetTargetProperty(scaleXAnim, "ScaleX");
        
        Storyboard.SetTarget(scaleYAnim, ToastTransform);
        Storyboard.SetTargetProperty(scaleYAnim, "ScaleY");

        storyboard.Children.Add(opacityAnim);
        storyboard.Children.Add(scaleXAnim);
        storyboard.Children.Add(scaleYAnim);
        
        await storyboard.BeginAsync();
        
        _isAnimating = false;
    }

    private async Task AnimateOutAsync()
    {
        _isAnimating = true;
        _dismissTimer.Stop();
        
        var storyboard = new Storyboard();
        
        var opacityAnim = new DoubleAnimation { From = 1, To = 0, Duration = TimeSpan.FromSeconds(0.4) };
        var scaleXAnim = new DoubleAnimation { From = 1.0, To = 0.9, Duration = TimeSpan.FromSeconds(0.4), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn } };
        var scaleYAnim = new DoubleAnimation { From = 1.0, To = 0.9, Duration = TimeSpan.FromSeconds(0.4), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn } };
        var translateYAnim = new DoubleAnimation { From = 0, To = -20, Duration = TimeSpan.FromSeconds(0.4), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn } };

        Storyboard.SetTarget(opacityAnim, ToastBorder);
        Storyboard.SetTargetProperty(opacityAnim, "Opacity");
        
        Storyboard.SetTarget(scaleXAnim, ToastTransform);
        Storyboard.SetTargetProperty(scaleXAnim, "ScaleX");
        
        Storyboard.SetTarget(scaleYAnim, ToastTransform);
        Storyboard.SetTargetProperty(scaleYAnim, "ScaleY");

        storyboard.Children.Add(opacityAnim);
        storyboard.Children.Add(scaleXAnim);
        storyboard.Children.Add(scaleYAnim);
        
        await storyboard.BeginAsync();
        
        this.Close();
        _isAnimating = false;
    }

    private void DismissTimer_Tick(object? sender, object e)
    {
        if (!_isAnimating)
        {
            _ = AnimateOutAsync();
        }
    }

    private void PositionAtTopRight()
    {
        var displayArea = DisplayArea.Primary;
        if (displayArea != null)
        {
            var workArea = displayArea.WorkArea;
            var x = workArea.Right - 420; // 400 width + 20 margin
            var y = workArea.Top + 50;
            this.AppWindow.Move(new PointInt32(x, y));
        }
    }

    // Event handlers
    private void StorageButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string action && _currentToast != null)
        {
            _currentToast.ResolveStorage?.Invoke(Enum.Parse<StorageDecision>(action, true));
            _ = AnimateOutAsync();
        }
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        _currentToast?.Copy?.Invoke();
    }

    private void ShareButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string provider && _currentToast != null)
        {
            _currentToast.Share?.Invoke();
        }
    }

    private void RetryButton_Click(object sender, RoutedEventArgs e)
    {
        _currentToast?.TryAgain?.Invoke();
        _ = AnimateOutAsync();
    }

    private void CancelToastButton_Click(object sender, RoutedEventArgs e)
    {
        _currentToast?.Cancel?.Invoke();
        _ = AnimateOutAsync();
    }

    private void RevealRecoveryButton_Click(object sender, RoutedEventArgs e)
    {
        _currentToast?.RevealRecovery?.Invoke();
    }

    private void OpenSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        _currentToast?.OpenSettings?.Invoke();
        _ = AnimateOutAsync();
    }
}