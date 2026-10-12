using System;
using System.Collections.Generic;
using System.Drawing;

namespace Textractor.Windows.Models;

/// <summary>
/// Represents a history entry of extracted text.
/// </summary>
public class HistoryRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Text { get; set; } = "";
    public CaptureMode Mode { get; set; }
    public DateTimeOffset Timestamp { get; set; }
    public CaptureInfo CaptureInfo { get; set; } = new();
}

/// <summary>
/// Information about the capture that produced this history entry.
/// </summary>
public class CaptureInfo
{
    public RectangleF Rect { get; set; }
    public CaptureMode Mode { get; set; }
    public CaptureOrigin Origin { get; set; }
}

/// <summary>
/// Represents an extraction record (more detailed than HistoryRecord).
/// </summary>
public class ExtractionRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset Timestamp { get; set; }
    public string Text { get; set; } = "";
    public CaptureMode Mode { get; set; }
    public CaptureOrigin Origin { get; set; }
    public RectangleF Rect { get; set; }
    public string? ImagePath { get; set; }
    public int WordCount { get; set; }
    public float AverageConfidence { get; set; }
    public string? Language { get; set; }
    public double ProcessingTimeSeconds { get; set; }
    public bool WasSaved { get; set; }
    public StorageDecision StorageDecision { get; set; }
}

/// <summary>
/// Telemetry event for local analytics.
/// </summary>
public class TelemetryEvent
{
    public string Kind { get; set; } = "";
    public bool Success { get; set; }
    public double LatencyMs { get; set; }
    public Dictionary<string, string> Meta { get; set; } = new();
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>
/// Toast notification state.
/// </summary>
public class ToastState
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public string Message { get; set; } = "";
    public ToastKind Kind { get; set; }
    public ToastSentiment Sentiment { get; set; }
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.Now;
    public int DurationSeconds { get; set; } = 8;
    public Action? OnClick { get; set; }
    public Action? OnDismiss { get; set; }
    public bool IsVisible { get; set; } = true;
}

/// <summary>
/// Kind of toast notification.
/// </summary>
public enum ToastKind
{
    Success,
    Error,
    Info,
    Warning,
    StorageDecision
}

/// <summary>
/// Sentiment for toast display.
/// </summary>
public enum ToastSentiment
{
    Positive,
    Neutral,
    Negative,
    Mixed
}

/// <summary>
/// App state for the main view model.
/// </summary>
public class AppState
{
    public bool IsCapturing { get; set; }
    public CaptureMode CurrentCaptureMode { get; set; } = CaptureMode.Crosshair;
    public ToastState? CurrentToast { get; set; }
    public bool IsSettingsOpen { get; set; }
    public bool IsHistoryOpen { get; set; }
    public bool HasPermissionIssues { get; set; }
    public string? PermissionMessage { get; set; }
}