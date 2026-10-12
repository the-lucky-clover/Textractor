using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public static class TextFormatter
{
    public static string Attributed(string text, AIInferenceService.Analysis? analysis, double weirdness)
    {
        if (string.IsNullOrEmpty(text)) return text;

        var formatted = text;

        // Highlight URLs - teal/cyan
        formatted = Regex.Replace(formatted,
            @"(https?://[^\s)]+|www\.[^\s)]+)",
            m => $"<ulink>{m.Value}</ulink>",
            RegexOptions.IgnoreCase);

        // Highlight emails - teal/cyan
        formatted = Regex.Replace(formatted,
            @"[\w.+-]+@[\w-]+\.[\w.-]+",
            m => $"<ulink>{m.Value}</ulink>",
            RegexOptions.IgnoreCase);

        // Highlight phone numbers - amber/orange
        formatted = Regex.Replace(formatted,
            @"(?:\\+?\d[\d\s().-]{7,})",
            m => $"<uphone>{m.Value}</uphone>",
            RegexOptions.IgnoreCase);

        // Highlight keywords from analysis
        if (analysis?.Keywords != null)
        {
            foreach (var keyword in analysis.Keywords.Where(k => k.Length >= 3))
            {
                formatted = Regex.Replace(formatted,
                    Regex.Escape(keyword),
                    m => $"<ukeyword>{m.Value}</ukeyword>",
                    RegexOptions.IgnoreCase);
            }
        }

        return formatted;
    }

    /// <summary>
    /// Generates RTF formatted text with typographic styling.
    /// </summary>
    public static string ToRtf(string text, AIInferenceService.Analysis? analysis = null, double weirdness = 0.45)
    {
        if (string.IsNullOrEmpty(text)) return "";

        var keywords = analysis?.Keywords ?? new List<string>();
        var sentiment = analysis?.Sentiment ?? AIInferenceService.Sentiment.Neutral;

        // Base RTF header with styling for keywords and entities
        var sb = new StringBuilder();
        sb.Append(@"\{\rtf1\ansi\deff0{\fonttbl{\f0\fnil\fcharset0 SF Pro Rounded;}{\f1\fnil\fcharset0 SF Mono;}}");
        sb.Append(@"\deflang1033{\viewgood\pard\sa200\sl276\slmult1\f0\fs28 ");

        // Color table: 0 Default, 1 Link (teal), 2 Phone (amber), 3 Keyword (lime)
        sb.Append(@"\red0\green0\blue0");
        sb.Append(@"\red0\green151\blue216");  // Teal for links
        sb.Append(@"\ased255\green164\blue29"); // Amber for phones
        sb.Append(@"\ared57\green255\blue69");  // Lime for keywords

        // Apply formatting
        var lines = text.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (i > 0) sb.Append(@"\par ");

            // Apply keyword highlighting
            foreach (var keyword in keywords.Where(k => k.Length >= 3))
            {
                line = System.Text.RegularExpressions.Regex.Replace(
                    line,
                    Regex.Escape(keyword),
                    m => $@"\cf4\f1\fs24 {m.Value}\cf0\f0\fs28",
                    RegexOptions.IgnoreCase);
            }

            sb.Append(line);
        }

        sb.Append(@"\par\}\}");
        return sb.ToString();
    }
}