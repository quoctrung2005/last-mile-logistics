namespace LastMile.Api.Services;

public sealed class VehicleTypeDefinition
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public decimal MaxCargoWeightKg { get; set; }
    public decimal? MaxCargoVolumeM3 { get; set; }
    public bool RequiresConfirmation { get; set; }
    public string Source { get; set; } = "";
}

// One operational catalog for both the API form and save validation.
// These are business settings, not statutory payload limits.
public sealed class VehicleTypeCatalog(IConfiguration configuration)
{
    public VehicleTypeDefinition[] GetTypes()
    {
        var types = configuration.GetSection("VehicleTypeCatalog:Types")
            .Get<VehicleTypeDefinition[]>() ?? [];
        if (types.Length == 0 || types.Select(t => t.Code).Distinct(StringComparer.Ordinal).Count() != types.Length
            || types.Any(t => string.IsNullOrWhiteSpace(t.Code) || t.Code.Length > 30
                || !System.Text.RegularExpressions.Regex.IsMatch(t.Code, "^[A-Za-z0-9_ -]+$")
                || string.IsNullOrWhiteSpace(t.Name) || t.MaxCargoWeightKg <= 0
                || t.MaxCargoWeightKg > 99999999.99m || decimal.Round(t.MaxCargoWeightKg, 2) != t.MaxCargoWeightKg
                || (t.MaxCargoVolumeM3.HasValue && (t.MaxCargoVolumeM3 <= 0 || t.MaxCargoVolumeM3 > 9999999.999m
                    || decimal.Round(t.MaxCargoVolumeM3.Value, 3) != t.MaxCargoVolumeM3.Value))))
            throw new InvalidOperationException("Cấu hình danh mục loại phương tiện không hợp lệ.");
        return types;
    }
}
