using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Textractor.Windows.Services;

public class AIInferenceService
{
    public static readonly AIInferenceService Shared = new();

    public class Analysis
    {
        public string CleanedText { get; set; } = "";
        public Sentiment Sentiment { get; set; }
        public string? Language { get; set; }
        public List<string> Keywords { get; set; } = new();
        public List<Entity> Entities { get; set; } = new();
        public int Tokens { get; set; }
    }

    public enum Sentiment
    {
        Positive,
        Neutral,
        Negative,
        Mixed
    }

    public class Entity
    {
        public EntityType Type { get; set; }
        public string Value { get; set; } = "";

        public static Entity Url(string value) => new Entity { Type = EntityType.Url, Value = value };
        public static Entity Email(string value) => new Entity { Type = EntityType.Email, Value = value };
        public static Entity Phone(string value) => new Entity { Type = EntityType.Phone, Value = value };
        public static Entity Hashtag(string value) => new Entity { Type = EntityType.Hashtag, Value = value };
        public static Entity Mention(string value) => new Entity { Type = EntityType.Mention, Value = value };
    }

    public enum EntityType
    {
        Url,
        Email,
        Phone,
        Hashtag,
        Mention
    }

    public async Task<Analysis> Analyze(string text, double weirdness = 0.45)
    {
        return await Task.Run(() =>
        {
            var cleaned = Clean(text, weirdness);
            var sentiment = SentimentScore(cleaned);
            var language = DetectLanguage(cleaned);
            var keywords = ExtractKeywords(cleaned, weirdness);
            var entities = ExtractEntities(cleaned);
            var tokens = cleaned.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;

            return new Analysis
            {
                CleanedText = cleaned,
                Sentiment = sentiment,
                Language = language,
                Keywords = keywords,
                Entities = entities,
                Tokens = tokens
            };
        });
    }

    public static string Clean(string text, double weirdness)
    {
        if (string.IsNullOrEmpty(text)) return text;

        var s = text;

        // Always: Unicode normalization, strip zero-width space & BOM
        s = s.Replace("\u200B", "");   // zero-width space
        s = s.Replace("\uFEFF", "");  // BOM
        s = s.Replace("\r\n", "\n");
        s = s.Replace("\t", " ");

        if (weirdness < 0.05)
        {
            s = CollapseRuns(s, "\n\n\n", "\n\n");
            return s.Trim();
        }

        // Smart-quote normalisation
        s = s.Replace("\u201C", "\"") // "
        .Replace("\u201D", "\"") // "
        .Replace("\u2018", "'")  // '
        .Replace("\u2019", "'"); // '

        // Strip non-printables except newlines
        s = new string(s
            .Where(c => c == '\n' || (c >= 0x20 && c != 0x7F))
            .ToArray());

        // Collapse runs of spaces & blank lines
        s = CollapseRuns(s, "   ", "  ");
        s = CollapseRuns(s, "  ", " ");
        s = CollapseRuns(s, "\n\n\n", "\n\n");
        s = CollapseRuns(s, "\n\n", "\n");

        if (weirdness >= 0.5)
        {
            // Dehyphenate words split across lines
            s = Regex.Replace(s, @"([A-Za-z])-\s*\n\s*([A-Za-z])", "$1$2");
            // Collapse ragged single newlines
            s = Regex.Replace(s, @"([A-Za-z0-9,;:!?)\]\.""])\n([A-Za-z0-9])", "$1 $2");
        }

        // Trim trailing whitespace per line
        s = string.Join("\n",
            s.Split('\n', StringSplitOptions.None)
                .Select(line => line.Trim()));

        return s.Trim();
    }

    private static string CollapseRuns(string text, string pattern, string replacement)
    {
        var regex = new Regex(
            Regex.Escape(pattern) + @"{2,}",
            RegexOptions.Compiled);
        return regex.Replace(text, replacement);
    }

    public static Sentiment SentimentScore(string text)
    {
        if (string.IsNullOrEmpty(text)) return Sentiment.Neutral;

        // Simple heuristic sentiment analysis
        var positiveWords = new[] { "good", "great", "excellent", "awesome", "happy", "love", "best" };
        var negativeWords = new[] { "bad", "terrible", "awful", "hate", "worst", "sad", "angry" };

        var lowerText = text.ToLower();
        var positiveCount = positiveWords.Count(w => lowerText.Contains(w));
        var negativeCount = negativeWords.Count(w => lowerText.Contains(w));

        if (positiveCount > negativeCount && positiveCount > 0) return Sentiment.Positive;
        if (negativeCount > positiveCount && negativeCount > 0) return Sentiment.Negative;
        if (positiveCount > 0 && negativeCount > 0) return Sentiment.Mixed;
        return Sentiment.Neutral;
    }

    public static string? DetectLanguage(string text)
    {
        if (string.IsNullOrEmpty(text)) return null;

        // Simple language detection heuristic
        var lowerText = text.ToLower();

        if (Regex.IsMatch(lowerText, @"\b(el|la|los|las|de|y|en|que)\b")) return "es";
        if (Regex.IsMatch(lowerText, @"\b(le|la|les|de|et|en|que|est)\b")) return "fr";
        if (Regex.IsMatch(lowerText, @"\b(der|die|und|ist|von|mit)\b")) return "de";
        if (Regex.IsMatch(lowerText, @"\b(il|la|le|di|e|in|un)\b")) return "it";
        if (Regex.IsMatch(lowerText, @"\b(els|van|met|is|een)\b")) return "nl";
        if (Regex.IsMatch(lowerText, @"\b(и|на|в|по|что|это)\b")) return "ru";
        if (Regex.IsMatch(lowerText, @"\b(は|が|の|に|を|と)\b")) return "ja";
        if (Regex.IsMatch(lowerText, @"\b(이|가|의|에|를|과)\b")) return "ko";
        if (Regex.IsMatch(lowerText, @"\b(是|的|在|和|有|我)\b")) return "zh";

        return "en";
    }

    public static List<string> ExtractKeywords(string text, double weirdness)
    {
        var minLength = weirdness >= 0.5 ? 2 : 3;
        var words = text
            .Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(w => w.Trim())
            .Where(w => w.Length >= minLength)
            .Select(w => w.ToLower())
            .Distinct()
            .ToList();

        var counts = new Dictionary<string, int>();
        foreach (var word in words)
        {
            if (counts.ContainsKey(word))
                counts[word]++;
            else
                counts[word] = 1;
        }

        return counts
            .Where(kv => kv.Value >= 2 || weirdness >= 0.7)
            .OrderByDescending(kv => kv.Value)
            .ThenBy(kv => kv.Key)
            .Take(12)
            .Select(kv => kv.Key)
            .ToList();
    }

    public static List<Entity> ExtractEntities(string text)
    {
        var entities = new List<Entity>();

        var urlPattern = @"(https?://[^\s)]+|www\.[^\s)]+)";
        var emailPattern = @"[\w.+-]+@[\w-]+\.[\w.-]+";
        var phonePattern = @"(?:\+?\d[\d\s().-]{7,})";
        var hashtagPattern = @"#[A-Za-z0-9_]+";
        var mentionPattern = @"@[A-Za-z0-9_]+";

        entities.AddRange(Matches(text, urlPattern, s => Entity.Url(s)));
        entities.AddRange(Matches(text, emailPattern, s => Entity.Email(s)));
        entities.AddRange(Matches(text, phonePattern, s => Entity.Phone(s)));
        entities.AddRange(Matches(text, hashtagPattern, s => Entity.Hashtag(s)));
        entities.AddRange(Matches(text, mentionPattern, s => Entity.Mention(s)));

        return entities;
    }

    private static List<Entity> Matches(string text, string pattern, Func<string, Entity> make)
    {
        return new Regex(pattern, RegexOptions.IgnoreCase)
            .Matches(text)
            .Cast<Match>()
            .Select(m => make(m.Value))
            .ToList();
    }
}