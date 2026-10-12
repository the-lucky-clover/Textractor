using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.Linq;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows.Views;

public sealed partial class HistoryWindow : Window
{
    public HistoryWindow()
    {
        this.InitializeComponent();
        
        this.ExtendsContentIntoTitleBar = true;
        this.AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        
        // Center on screen
        var displayArea = DisplayArea.Primary;
        if (displayArea != null)
        {
            var workArea = displayArea.WorkArea;
            var x = (workArea.Width - 400) / 2 + workArea.X;
            var y = (workArea.Height - 600) / 2 + workArea.Y;
            this.AppWindow.Move(new PointInt32(x, y));
        }
        
        LoadHistory();
    }

    private void LoadHistory()
    {
        var records = HistoryStore.Shared.GetRecent(50);
        
        var displayItems = records.Select(r => new HistoryDisplayItem
        {
            Id = r.Id,
            PreviewText = r.Text.Length > 120 ? r.Text.Substring(0, 120) + "…" : r.Text,
            Timestamp = r.Timestamp.ToString("MMM d, h:mm tt"),
            ModeText = r.Mode.ToString().ToUpper(),
            ModeIcon = r.Mode switch
            {
                CaptureMode.Crosshair => "\uE773",      // viewfinder
                CaptureMode.Window => "\uE7C3",        // macwindow
                CaptureMode.FullScreen => "\uE7EF",    // rectangle.dashed.badge.record
                CaptureMode.File => "\uE7C5",          // photo.on.rectangle
                _ => "\uE773"
            }
        }).ToList();
        
        HistoryItemsControl.ItemsSource = displayItems;
        
        VersionFooter.Text = UpdateService.GetVersionDescription();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        this.Close();
    }

    private void CopyHistoryItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is HistoryDisplayItem item)
        {
            var record = HistoryStore.Shared.GetRecent(50).FirstOrDefault(r => r.Id == item.Id);
            if (record != null)
            {
                ClipboardService.Copy(record.Text);
                
                // Show toast
                var toastWindow = new ToastNotificationWindow();
                var toast = new Models.ToastState
                {
                    Kind = "success",
                    Headline = "Copied",
                    Body = "History item copied to clipboard",
                    Copy = () => { }
                };
                _ = toastWindow.ShowToastAsync(toast);
            }
        }
    }

    private void DeleteHistoryItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is HistoryDisplayItem item)
        {
            // In production: remove from history store
            LoadHistory();
        }
    }

    private void ClearHistory_Click(object sender, RoutedEventArgs e)
    {
        HistoryStore.Shared.Clear();
        LoadHistory();
    }
}

public class HistoryDisplayItem
{
    public Guid Id { get; set; }
    public string PreviewText { get; set; } = "";
    public string Timestamp { get; set; } = "";
    public string ModeText { get; set; } = "";
    public string ModeIcon { get; set; } = "";
}