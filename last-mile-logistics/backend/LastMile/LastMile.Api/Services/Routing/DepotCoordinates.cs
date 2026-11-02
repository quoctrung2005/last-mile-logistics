namespace LastMile.Api.Services.Routing;

public static class DepotCoordinates
{
    public sealed record Assessment(string State, string Message);
    public static Assessment Check(double? latitude, double? longitude, string? source = null, bool requireSource = false)
    {
        if (latitude is null && longitude is null)
            return new("MISSING", "Kho đang chọn chưa có tọa độ xuất phát.");
        if (latitude is null || longitude is null || !new GeoPoint(latitude.Value, longitude.Value).IsValid || latitude == 0 && longitude == 0)
            return new("INVALID", "Tọa độ kho đang chọn thiếu hoặc không hợp lệ.");
        if (requireSource && string.IsNullOrWhiteSpace(source))
            return new("UNVERIFIED", "Kho đã có tọa độ nhưng chưa có nguồn xác minh. Cần xác nhận vị trí thực tế của kho.");
        return new("CONFIGURED", "Đã có tọa độ kho. Khả năng nối mạng đường được kiểm tra riêng theo loại xe.");
    }
}
