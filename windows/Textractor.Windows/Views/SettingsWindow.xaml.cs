using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;
using System;
using System.Linq;
using System.Threading.Tasks;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows.Views;

public sealed partial class SettingsWindow : Window
{
    private readonly AppSettings _settings;
    private bool _firstLoad = true;
    private bool _animationsEnabled => !_settings.ReduceMotion;

    public SettingsWindow()
    {
        _settings = SettingsStore.Shared.Settings;
        this.InitializeComponent();
        
        this.ExtendsContentIntoTitleBar = true;
        this.AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        
        // Position near system tray
        PositionNearTray();
        
        LoadSettings();
        
        if (_animationsEnabled)
        {
            _ = AnimateEntranceAsync();
        }
        else
        {
            SetAllVisible();
        }
    }

    private void PositionNearTray()
    {
        var displayArea = DisplayArea.Primary;
        if (displayArea != null)
        {
            var workArea = displayArea.WorkArea;
            var x = workArea.Right - 252; // 232 width + 20 margin
            var y = workArea.Top + 60;
            this.AppWindow.Move(new PointInt32(x, y));
        }
    }

    private void LoadSettings()
    {
        // Load banner
        try
        {
            BannerImage.Source = new BitmapImage(new Uri("ms-appx:///Resources/textractor-type.png"));
        }
        catch { }

        // Weirdness
        WeirdnessSlider.Value = _settings.Weirdness;
        WeirdnessValueText.Text = $"{(int)(_settings.Weirdness * 100)}%";

        // Vocab
        VocabTextBox.Text = string.Join(", ", _settings.CustomVocabulary);

        // Toggles
        PastePlainToggle.IsOn = _settings.PasteAsPlainText;
        ShareMailToggle.IsOn = _settings.QuickShareTargets?.Contains(QuickShareTarget.Mail) ?? true;
        ShareMessageToggle.IsOn = _settings.QuickShareTargets?.Contains(QuickShareTarget.Message) ?? true;
        ShareAirDropToggle.IsOn = _settings.QuickShareTargets?.Contains(QuickShareTarget.AirDrop) ?? true;
        WindowTableToggle.IsOn = _settings.WindowCaptureAsTable;
        FlattenToggle.IsOn = _settings.FlattenText;
        ReduceMotionToggle.IsOn = _settings.ReduceMotion;
        TelemetryToggle.IsOn = _settings.LocalTelemetryEnabled;

        // Version
        VersionText.Text = $"Version {UpdateService.GetVersionDescription()}";
        LastCheckedText.Text = UpdateService.GetRelativeLastChecked(_settings.LastUpdateCheckAt);
    }

    private async Task AnimateEntranceAsync()
    {
        var elements = new[]
        {
            (BannerBorder, BannerTransform, 0),
            (Section1Label, Section1Transform, 1),
            (WeirdnessCard, WeirdnessTransform, 2),
            (VocabCard, VocabTransform, 3),
            (ResetDefaultsButton, ResetTransform, 4),
            (Section2Label, Section2Transform, 5),
            (PastePlainTextButton, PastePlainTransform, 6),
            (QuickShareLabel, QuickShareLabelTransform, 7),
            (ShareMailButton, ShareMailTransform, 8),
            (ShareMessageButton, ShareMessageTransform, 9),
            (ShareAirDropButton, ShareAirDropTransform, 10),
            (Section3Label, Section3Transform, 11),
            (WindowTableButton, WindowTableTransform, 12),
            (Section4Label, Section4Transform, 13),
            (UpdatesCard, UpdatesTransform, 14),
            (Section5Label, Section5Transform, 15),
            (OpenHistoryButton, OpenHistoryTransform, 16),
            (Section6Label, Section6Transform, 17),
            (FlattenButton, FlattenTransform, 18),
            (ReduceMotionButton, ReduceMotionTransform, 19),
            (TelemetryButton, TelemetryTransform, 20),
            (Section7Label, Section7Transform, 21),
            (AboutCard, AboutTransform, 22),
        };

        foreach (var (element, transform, index) in elements)
        {
            var delay = TimeSpan.FromMilliseconds(index * 35);
            await Task.Delay(delay);
            
            var storyboard = new Storyboard();
            
            var opacityAnim = new DoubleAnimation { From = 0, To = 1, Duration = TimeSpan.FromSeconds(0.44) };
            var scaleXAnim = new DoubleAnimation { From = 0.94, To = 1.0, Duration = TimeSpan.FromSeconds(0.44), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            var scaleYAnim = new DoubleAnimation { From = 0.94, To = 1.0, Duration = TimeSpan.FromSeconds(0.44), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            var translateYAnim = new DoubleAnimation { From = 10, To = 0, Duration = TimeSpan.FromSeconds(0.44), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };

            Storyboard.SetTarget(opacityAnim, element);
            Storyboard.SetTargetProperty(opacityAnim, "Opacity");
            
            Storyboard.SetTarget(scaleXAnim, transform);
            Storyboard.SetTargetProperty(scaleXAnim, "ScaleX");
            
            Storyboard.SetTarget(scaleYAnim, transform);
            Storyboard.SetTargetProperty(scaleYAnim, "ScaleY");
            
            Storyboard.SetTarget(translateYAnim, transform);
            Storyboard.SetTargetProperty(translateYAnim, "TranslateY");

            storyboard.Children.Add(opacityAnim);
            storyboard.Children.Add(scaleXAnim);
            storyboard.Children.Add(scaleYAnim);
            storyboard.Children.Add(translateYAnim);
            
            storyboard.Begin();
        }
    }

    private void SetAllVisible()
    {
        BannerBorder.Opacity = 1;
        Section1Label.Opacity = 1;
        WeirdnessCard.Opacity = 1;
        VocabCard.Opacity = 1;
        ResetDefaultsButton.Opacity = 1;
        Section2Label.Opacity = 1;
        PastePlainTextButton.Opacity = 1;
        QuickShareLabel.Opacity = 1;
        ShareMailButton.Opacity = 1;
        ShareMessageButton.Opacity = 1;
        ShareAirDropButton.Opacity = 1;
        Section3Label.Opacity = 1;
        WindowTableButton.Opacity = 1;
        Section4Label.Opacity = 1;
        UpdatesCard.Opacity = 1;
        Section5Label.Opacity = 1;
        OpenHistoryButton.Opacity = 1;
        Section6Label.Opacity = 1;
        FlattenButton.Opacity = 1;
        ReduceMotionButton.Opacity = 1;
        TelemetryButton.Opacity = 1;
        Section7Label.Opacity = 1;
        AboutCard.Opacity = 1;
    }

    // Event handlers
    private void WeirdnessSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        var value = e.NewValue;
        _settings.Weirdness = value;
        WeirdnessValueText.Text = $"{(int)(value * 100)}%";
        SettingsStore.Shared.Save();
    }

    private void SaveVocab_Click(object sender, RoutedEventArgs e)
    {
        var tokens = VocabTextBox.Text
            .Split(',')
            .Select(t => t.Trim())
            .Where(t => !string.IsNullOrEmpty(t))
            .ToList();
        
        _settings.CustomVocabulary = tokens;
        SettingsStore.Shared.Save();
    }

    private void PastePlainToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            _settings.PasteAsPlainText = toggle.IsOn;
            SettingsStore.Shared.Save();
        }
    }

    private void ShareMailToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            UpdateQuickShareTarget(QuickShareTarget.Mail, toggle.IsOn);
        }
    }

    private void ShareMessageToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            UpdateQuickShareTarget(QuickShareTarget.Message, toggle.IsOn);
        }
    }

    private void ShareAirDropToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            UpdateQuickShareTarget(QuickShareTarget.AirDrop, toggle.IsOn);
        }
    }

    private void UpdateQuickShareTarget(QuickShareTarget target, bool isOn)
    {
        if (_settings.QuickShareTargets == null)
            _settings.QuickShareTargets = new();
            
        if (isOn)
            _settings.QuickShareTargets.Add(target);
        else
            _settings.QuickShareTargets.Remove(target);
            
        SettingsStore.Shared.Save();
    }

    private void WindowTableToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            _settings.WindowCaptureAsTable = toggle.IsOn;
            SettingsStore.Shared.Save();
        }
    }

    private void FlattenToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            _settings.FlattenText = toggle.IsOn;
            SettingsStore.Shared.Save();
        }
    }

    private void ReduceMotionToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            _settings.ReduceMotion = toggle.IsOn;
            SettingsStore.Shared.Save();
        }
    }

    private void TelemetryToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch toggle)
        {
            _settings.LocalTelemetryEnabled = toggle.IsOn;
            TelemetryService.Shared.IsEnabled = toggle.IsOn;
            SettingsStore.Shared.Save();
        }
    }

    private void MenuRow_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string action)
        {
            switch (action)
            {
                case "reset":
                    ResetDefaults();
                    break;
                case "history":
                    // Show history window
                    break;
            }
        }
    }

    private void ResetDefaults()
    {
        _settings.Weirdness = 0.45;
        _settings.CustomVocabulary.Clear();
        _settings.PasteAsPlainText = true;
        _settings.FlattenText = false;
        _settings.ReduceMotion = false;
        _settings.LocalTelemetryEnabled = true;
        _settings.WindowCaptureAsTable = true;
        _settings.QuickShareTargets = new() { QuickShareTarget.Mail, QuickShareTarget.Message, QuickShareTarget.AirDrop };
        
        LoadSettings();
        SettingsStore.Shared.Save();
    }

    private void CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        _settings.LastUpdateCheckAt = DateTimeOffset.Now;
        LastCheckedText.Text = UpdateService.GetRelativeLastChecked(_settings.LastUpdateCheckAt);
        SettingsStore.Shared.Save();
        
        // In production: check for updates
        UpdateService.Shared.PresentUpToDateAlert();
    }

    private void OpenCredits_Click(object sender, RoutedEventArgs e)
    {
        // Open credits URL
        _ = Windows.System.Launcher.LaunchUriAsync(new Uri("https://soundcloud.com/lucky-clover"));
    }
}

public enum QuickShareTarget
{
    Mail,
    Message,
    AirDrop
}