using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public static class PasteFormatter
{
    public static string Format(string text, bool wordWrap = false, bool flatten = false)
    {
        if (string.IsNullOrEmpty(text)) return text;

        var formatted = text;

        // Flatten: remove all newlines, collapse spaces
        if (flatten)
        {
            formatted = Regex.Replace(formatted, @"\r\n|\r|\n", " ");
            formatted = Regex.Replace(formatted, @"\s+", " ");
        }

        // Word wrap: wrap at 80 columns
        if (wordWrap)
        {
            formatted = WordWrap(formatted, 80);
        }

        return formatted.Trim();
    }

    private static string WordWrap(string text, int columns)
    {
        var words = text.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0) return text;

        var lines = new List<string>();
        var currentLine = new System.Text.StringBuilder();
        var currentLength = 0;

        foreach (var word in words)
        {
            if (currentLength + word.Length + 1 > columns && currentLength > 0)
            {
                lines.Add(currentLine.ToString());
                currentLine.Clear();
                currentLine.Append(word);
                currentLength = word.Length;
            }
            else
            {
                if (currentLength > 0)
                {
                    currentLine.Append(' ');
                    currentLength++;
                }
                currentLine.Append(word);
                currentLength += word.Length;
            }
        }

        if (currentLength > 0)
        {
            lines.Add(currentLine.ToString());
        }

        return string.Join("\n", lines);
    }
}