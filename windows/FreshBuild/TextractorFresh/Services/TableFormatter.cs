using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

/// <summary>
/// Converts OCR text observations into Markdown tables by clustering
/// observations into rows and columns based on spatial alignment.
/// Mirrors the Swift TableFormatter.
/// </summary>
public static class TableFormatter
{
    private const double ColumnGapThreshold = 0.02;  // Normalized space between columns
    private const double RowGapThreshold = 0.015;    // Normalized space between rows
    private const double MinTableCellCoverage = 0.4; // Minimum fraction of observations in a cell

    public static string? ToMarkdownTable(List<TextObservation> observations)
    {
        if (observations == null || observations.Count == 0)
            return null;

        var clusters = ClusterIntoGrid(observations);
        if (!looksTabular(clusters, observations.Count))
            return null;

        var table = BuildMarkdownTable(clusters);
        return table;
    }

    /// <summary>
    /// Clusters observations into a grid of cells based on bounding box alignment.
    /// </summary>
    private static List<List<List<string>>> ClusterIntoGrid(List<TextObservation> observations)
    {
        // Determine column boundaries from X positions
        var columns = DetermineColumns(observations);
        var rows = DetermineRows(observations);

        // Fill cells
        var grid = new List<List<List<string>>>();
        foreach (var row in rows)
        {
            var gridRow = new List<List<string>>();
            foreach (var col in columns)
            {
                var cellTexts = observations
                    .Where(obs =>
                        obs.BoundingBox.CenterX() >= col.Min && obs.BoundingBox.CenterX() <= col.Max &&
                        obs.BoundingBox.CenterY() >= row.Min && obs.BoundingBox.CenterY() <= row.Max)
                    .Select(obs => obs.Text)
                    .OrderBy(t => t)
                    .ToList();
                gridRow.Add(cellTexts);
            }
            grid.Add(gridRow);
        }

        // Sort rows by Y descending (top to bottom)
        grid = grid.OrderByDescending(r => 
        {
            var firstObs = observations.FirstOrDefault(o => r.Any(c => c.Contains(o.Text)));
            return firstObs?.BoundingBox.CenterY() ?? 0;
        }).ToList();

        return grid;
    }

    private static List<Range> DetermineColumns(List<TextObservation> observations)
    {
        // Sort observations by X center
        var sorted = observations.OrderBy(o => o.BoundingBox.CenterX()).ToList();
        if (sorted.Count == 0) return new();

        var columns = new List<Range>();
        var currentStart = sorted[0].BoundingBox.Left;
        var currentEnd = sorted[0].BoundingBox.Right;

        foreach (var obs in sorted.Skip(1))
        {
            var gap = obs.BoundingBox.Left - currentEnd;
            if (gap > ColumnGapThreshold)
            {
                columns.Add(new Range(currentStart, currentEnd));
                currentStart = obs.BoundingBox.Left;
            }
            currentEnd = obs.BoundingBox.Right;
        }
        columns.Add(new Range(currentStart, currentEnd));

        return columns;
    }

    private static List<Range> DetermineRows(List<TextObservation> observations)
    {
        // Sort observations by Y center (top = highest Y)
        var sorted = observations.OrderByDescending(o => o.BoundingBox.CenterY()).ToList();
        if (sorted.Count == 0) return new();

        var rows = new List<Range>();
        var currentStart = sorted[0].BoundingBox.Top;
        var currentEnd = sorted[0].BoundingBox.Bottom;

        foreach (var obs in sorted.Skip(1))
        {
            var gap = currentEnd - obs.BoundingBox.Bottom;
            if (gap > RowGapThreshold)
            {
                rows.Add(new Range(currentStart, currentEnd));
                currentStart = obs.BoundingBox.Top;
            }
            currentEnd = obs.BoundingBox.Bottom;
        }
        rows.Add(new Range(currentStart, currentEnd));

        return rows;
    }

    private static bool looksTabular(List<List<List<string>>> clusters, int totalObservations)
    {
        if (clusters.Count == 0) return false;

        // Heuristic: looks tabular if we have >= 2 rows and >= 2 columns
        // with reasonable cell coverage
        var cellCount = 0;
        var nonEmptyCells = 0;

        foreach (var row in clusters)
        {
            foreach (var cell in row)
            {
                cellCount++;
                if (cell.Count > 0)
                    nonEmptyCells++;
            }
        }

        var coverage = (double)nonEmptyCells / Math.Max(cellCount, 1);
        return clusters.Count >= 2 && clusters[0].Count >= 2 && coverage >= MinTableCellCoverage;
    }

    private static string BuildMarkdownTable(List<List<List<string>>> grid)
    {
        if (grid.Count == 0 || grid[0].Count == 0) return "";

        var colCount = grid[0].Count;
        var sb = new System.Text.StringBuilder();

        // Header
        for (int i = 0; i < colCount; i++)
        {
            sb.Append("| ");
            sb.Append(string.Join(" ", grid[0][i]));
            sb.Append(" ");
        }
        sb.AppendLine("|");

        // Separator
        for (int i = 0; i < colCount; i++)
        {
            sb.Append("| --- ");
        }
        sb.AppendLine("|");

        // Rows
        for (int r = 1; r < grid.Count; r++)
        {
            for (int c = 0; c < grid[r].Count; c++)
            {
                sb.Append("| ");
                sb.Append(string.Join(" ", grid[r][c]));
                sb.Append(" ");
            }
            sb.AppendLine("|");
        }

        return sb.ToString();
    }

    private class Range
    {
        public float Min { get; }
        public float Max { get; }
        public Range(float min, float max) { Min = min; Max = max; }
    }
}