using System.ComponentModel.DataAnnotations;

namespace LastMile.Api.Services;

public sealed class LoginSecurityOptions
{
    public const string SectionName = "LoginSecurity";

    [Range(1, 100)]
    public int MaxFailedAttempts { get; set; } = 5;

    [Range(1, 1440)]
    public int LockoutMinutes { get; set; } = 15;

    [Range(1, 10000)]
    public int IpPermitLimit { get; set; } = 20;

    [Range(1, 3600)]
    public int IpWindowSeconds { get; set; } = 60;
}
