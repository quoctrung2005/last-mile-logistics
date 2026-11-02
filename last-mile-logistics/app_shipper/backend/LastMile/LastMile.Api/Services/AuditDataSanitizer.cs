using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace LastMile.Api.Services;

public static class AuditDataSanitizer
{
    private static bool Sensitive(string key)
    {
        var normalized = new string(key.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());
        return new[] { "password", "matkhau", "mậtkhẩu", "token", "secret", "credential", "authorization", "apikey", "privatekey", "connectionstring", "cookie", "jwt" }
            .Any(normalized.Contains);
    }

    public static string Text(string value)
    {
        const string hidden = "[Đã ẩn]";
        value = Regex.Replace(value, @"\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}", hidden, RegexOptions.None, TimeSpan.FromMilliseconds(200));
        value = Regex.Replace(value, @"\b[A-Za-z0-9_-]{3,}\.[A-Za-z0-9_-]{3,}\.[A-Za-z0-9_-]{3,}\b|\b[A-Za-z0-9_-]{43}\b", hidden, RegexOptions.None, TimeSpan.FromMilliseconds(200));
        return Regex.Replace(value, @"(?i)(password|matkhau|mật khẩu|access[_ -]?token|refresh[_ -]?token|secret|api[_ -]?key)\s*[:=]\s*[^\s,;]+", hidden, RegexOptions.None, TimeSpan.FromMilliseconds(200));
    }

    public static string Json(string json)
    {
        var node = JsonNode.Parse(json);
        Sanitize(node);
        return node?.ToJsonString() ?? "null";
    }

    private static void Sanitize(JsonNode? node)
    {
        if (node is JsonObject obj)
        {
            foreach (var property in obj.ToArray())
            {
                if (Sensitive(property.Key)) { obj.Remove(property.Key); continue; }
                if (property.Value is JsonValue val && val.TryGetValue<string>(out var text)) obj[property.Key] = Text(text);
                else Sanitize(property.Value);
            }
        }
        else if (node is JsonArray array)
        {
            for (var i = 0; i < array.Count; i++)
            {
                if (array[i] is JsonValue val && val.TryGetValue<string>(out var text)) array[i] = Text(text);
                else Sanitize(array[i]);
            }
        }
    }
}
