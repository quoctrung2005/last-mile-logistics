using System.Globalization;

namespace LastMile.Api.Services;

/// <summary>Business calendar dates in Vietnam (UTC+07, no daylight saving).</summary>
public static class VietnamDate
{
    public const int UtcOffsetMinutes = 420;

    public static DateOnly FromInstant(DateTimeOffset instant) =>
        DateOnly.FromDateTime(instant.ToOffset(TimeSpan.FromMinutes(UtcOffsetMinutes)).DateTime);

    // A date-only expiry remains valid for the entire date. Preserve optional licences.
    public static bool IsLicenseExpired(DateOnly? expiresAt, DateTimeOffset instant) =>
        expiresAt.HasValue && expiresAt.Value < FromInstant(instant);

    public static bool IsLicenseExpired(DateOnly? expiresAt) =>
        IsLicenseExpired(expiresAt, TimeProvider.System.GetUtcNow());

    // Only developer-owned UTC SQL expressions belong here, never request input.
    // Convert the comparison clock, never the stored DATE or other UTC timestamps.
    public static string SqlDate(string utcExpression) =>
        $"CONVERT(DATE, DATEADD(MINUTE, {UtcOffsetMinutes.ToString(CultureInfo.InvariantCulture)}, {utcExpression}))";
}
