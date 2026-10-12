using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;

namespace Textractor.Windows.Models;

public class TextObservation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Text { get; set; } = "";
    public float Confidence { get; set; }
    public RectangleF BoundingBox { get; set; }
}

public class OCRResult
{
    public List<TextObservation> RawObservations { get; set; } = new();
    public double RecognizedAtSeconds { get; set; }
    public List<string> LanguageCandidates { get; set; } = new();
    public List<(string Mode, int Count)> RevisionsUsed { get; set; } = new();

    public string JoinedText
    {
        get
        {
            var sorted = RawObservations
                .OrderByDescending(o => o.BoundingBox.CenterY())
                .ThenBy(o => o.BoundingBox.CenterX())
                .ToList();
            return string.Join("\n", sorted.Select(o => o.Text)).Trim();
        }
    }

    public float AverageConfidence =>
        RawObservations.Count > 0 ? RawObservations.Average(o => o.Confidence) : 0;

    public bool IsEmpty => RawObservations.Count == 0 || string.IsNullOrWhiteSpace(JoinedText);
}

public static class RectangleFExtensions
{
    public static float CenterX(this RectangleF rect) => rect.X + rect.Width / 2f;
    public static float CenterY(this RectangleF rect) => rect.Y + rect.Height / 2f;
    public static float Left(this RectangleF rect) => rect.X;
    public static float Right(this RectangleF rect) => rect.X + rect.Width;
    public static float Top(this RectangleF rect) => rect.Y;
    public static float Bottom(this RectangleF rect) => rect.Y + rect.Height;
}