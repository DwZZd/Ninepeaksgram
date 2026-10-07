using System.Collections.Generic;
using System.Text.Json;

internal static class JsonMap
{
    public static Dictionary<string, object> Read(string json)
    {
        var result = new Dictionary<string, object>();
        using (var doc = JsonDocument.Parse(json))
        {
            foreach (var property in doc.RootElement.EnumerateObject())
            {
                result[property.Name] = Box(property.Value);
            }
        }
        return result;
    }

    public static string Write(object value)
    {
        return JsonSerializer.Serialize(value);
    }

    private static object Box(JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.True:
                return true;
            case JsonValueKind.False:
                return false;
            case JsonValueKind.String:
                return value.GetString();
            case JsonValueKind.Number:
                long whole;
                if (value.TryGetInt64(out whole))
                {
                    return whole;
                }
                return value.GetDouble();
            default:
                return value.ToString();
        }
    }
}
