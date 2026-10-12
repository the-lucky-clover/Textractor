using Microsoft.UI.Xaml;
using Microsoft.UI.Windowing;
using System;
using System.Threading.Tasks;
using Windows.Foundation;

namespace Textractor.Windows.Views;

public sealed partial class SplashScreenWindow : Window
{
    private const double FadeInDuration = 0.25;
    private const double HoldDuration = 3.0;
    private const double FadeOutDuration = 0.25;

    public SplashScreenWindow()
    {
        this.InitializeComponent();
        this.ExtendsContentIntoTitleBar = true;
        this.AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        
        // Center on primary screen
        CenterOnScreen();
    }

    public async Task ShowAsync()
    {
        this.Activate();
        
        // Run animation sequence
        await FadeInAsync();
        await Task.Delay(TimeSpan.FromSeconds(HoldDuration));
        await FadeOutAsync();
        
        this.Close();
    }

    private async Task FadeInAsync()
    {
        var storyboard = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
        
        var shadowAnim = new DoubleAnimation
        {
            From = 0,
            To = 1,
            Duration = TimeSpan.FromSeconds(FadeInDuration),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
        };
        var imageAnim = new DoubleAnimation
        {
            From = 0,
            To = 1,
            Duration = TimeSpan.FromSeconds(FadeInDuration),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
        };

        Storyboard.SetTarget(shadowAnim, ShadowBorder);
        Storyboard.SetTargetProperty(shadowAnim, "Opacity");
        
        Storyboard.SetTarget(imageAnim, ImageBorder);
        Storyboard.SetTargetProperty(imageAnim, "Opacity");

        storyboard.Children.Add(shadowAnim);
        storyboard.Children.Add(imageAnim);
        
        await storyboard.BeginAsync();
    }

    private async Task FadeOutAsync()
    {
        var storyboard = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
        
        var shadowAnim = new DoubleAnimation
        {
            From = 1,
            To = 0,
            Duration = TimeSpan.FromSeconds(FadeOutDuration),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
        };
        var imageAnim = new DoubleAnimation
        {
            From = 1,
            To = 0,
            Duration = TimeSpan.FromSeconds(FadeOutDuration),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
        };

        Storyboard.SetTarget(shadowAnim, ShadowBorder);
        Storyboard.SetTargetProperty(shadowAnim, "Opacity");
        
        Storyboard.SetTarget(imageAnim, ImageBorder);
        Storyboard.SetTargetProperty(imageAnim, "Opacity");

        storyboard.Children.Add(shadowAnim);
        storyboard.Children.Add(imageAnim);
        
        await storyboard.BeginAsync();
    }

    private void CenterOnScreen()
    {
        var displayArea = Microsoft.UI.Windowing.DisplayArea.Primary;
        if (displayArea != null)
        {
            var workArea = displayArea.WorkArea;
            var x = (workArea.Width - 540) / 2 + workArea.X;
            var y = (workArea.Height - 540) / 2 + workArea.Y;
            this.AppWindow.Move(new Windows.Graphics.PointInt32((int)x, (int)y));
        }
    }
}

// Extension for storyboard async
internal static class StoryboardExtensions
{
    public static Task BeginAsync(this Microsoft.UI.Xaml.Media.Animation.Storyboard storyboard)
    {
        var tcs = new TaskCompletionSource<object>();
        storyboard.Completed += (s, e) => tcs.SetResult(null);
        storyboard.Begin();
        return tcs.Task;
    }
}