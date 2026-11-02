using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Globalization;
using System.Security.Claims;
using System.Text.Json;
using System.Xml;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class ShippingFeeQuoteRequest
{
    [Range(1, int.MaxValue)]
    public int BranchId { get; set; }

    [Range(1, int.MaxValue)]
    public int ServiceId { get; set; }

    [Range(1, long.MaxValue)]
    public long? OrderId { get; set; }

    [Range(1, long.MaxValue)]
    public long? PickupAddressId { get; set; }

    [Range(1, long.MaxValue)]
    public long? DeliveryAddressId { get; set; }

    // Bắt buộc khi báo giá cho đơn chưa tạo.
    // Với đơn đã có, backend dùng khối lượng trong database.
    [Range(typeof(decimal), "0.001", "1000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? WeightKg { get; set; }
}

[Authorize]
[ApiController]
[Route("api/v1/shipping-fees")]
public class ShippingFeesController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly RoadNetwork _roadNetwork;
    private readonly ILogger<ShippingFeesController> _logger;

    public ShippingFeesController(
        IConfiguration configuration,
        RoadNetwork roadNetwork,
        ILogger<ShippingFeesController> logger)
    {
        _configuration = configuration;
        _roadNetwork = roadNetwork;
        _logger = logger;
    }

    private sealed record QuoteSource(
        decimal WeightKg,
        string PointsJson);

    private sealed record QuoteRoute(
        decimal DistanceKm,
        string Profile,
        string GraphVersion,
        decimal PickupSnapMeters,
        decimal DeliverySnapMeters);

    private const string PermissionSql = """
        SET NOCOUNT ON;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              )
              AND (
                  vt.KyHieuVaiTro = 'ADMIN'
                  OR tk.MaBuuCuc = @BranchId
              )
              AND EXISTS (
                  SELECT 1
                  FROM dbo.VaiTroQuyen vq
                  INNER JOIN dbo.Quyen q
                      ON q.MaQuyen = vq.MaQuyen
                  WHERE vq.MaVaiTro = tk.MaVaiTro
                    AND (
                        q.KyHieuQuyen = 'DONHANG_TAO'
                        OR (
                            vt.KyHieuVaiTro = 'ADMIN'
                            AND q.KyHieuQuyen = 'BANGGIA_QUANLY'
                        )
                    )
              )
        )
            THROW 52103, N'Không có quyền báo giá trong bưu cục này.', 1;

        """;

    [HttpPost("quote")]
    public async Task<IActionResult> Quote(
        ShippingFeeQuoteRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        if (request.OrderId.HasValue)
        {
            if (request.PickupAddressId.HasValue
                || request.DeliveryAddressId.HasValue)
            {
                return BadRequest(new
                {
                    message = "Khi gửi orderId, không gửi thêm ID địa chỉ. API sẽ lấy điểm lấy/giao từ đơn."
                });
            }
        }
        else
        {
            if (!request.PickupAddressId.HasValue
                || !request.DeliveryAddressId.HasValue
                || !request.WeightKg.HasValue)
            {
                return BadRequest(new
                {
                    message = "Báo giá đơn chưa tạo cần pickupAddressId, deliveryAddressId và weightKg."
                });
            }
        }

        if (request.WeightKg.HasValue
            && decimal.Round(request.WeightKg.Value, 3)
                != request.WeightKg.Value)
        {
            return BadRequest(new
            {
                message = "Khối lượng tối đa 3 số lẻ."
            });
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        try
        {
            await connection.OpenAsync(cancellationToken);

            var source = await ReadSourceAsync(
                connection,
                accountId,
                request,
                cancellationToken);

            if (source.WeightKg < 0.001m
                || source.WeightKg > 1_000_000m)
            {
                return UnprocessableEntity(new
                {
                    message = "API báo giá hỗ trợ khối lượng từ 0,001 đến 1.000.000 kg."
                });
            }

            var route = CalculateRoute(
                source.PointsJson,
                cancellationToken);

            return await CalculateFeeAsync(
                connection,
                accountId,
                request,
                source,
                route,
                cancellationToken);
        }
        catch (DispatchProblem ex)
        {
            return StatusCode(ex.Status, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 52103)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52104)
        {
            return NotFound(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex)
            when (ex.Number is 52101 or 52102)
        {
            return BadRequest(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được cập nhật đồng thời. Hãy thử báo giá lại."
            });
        }
        catch (Exception ex)
            when (ex is IOException
                or InvalidDataException
                or XmlException
                or UnauthorizedAccessException)
        {
            _logger.LogError(
                ex,
                "Không đọc được mạng đường khi báo giá.");

            return StatusCode(503, new
            {
                message = "Không đọc được mạng đường. Hãy kiểm tra Routing:GraphPath và tệp OSM."
            });
        }
        catch (SqlException ex)
        {
            _logger.LogError(
                ex,
                "Không báo giá được cho bưu cục {BranchId}.",
                request.BranchId);

            return StatusCode(500, new
            {
                message = "Không báo giá được. Hãy kiểm tra log backend."
            });
        }
    }

    private static async Task<QuoteSource> ReadSourceAsync(
        SqlConnection connection,
        long accountId,
        ShippingFeeQuoteRequest request,
        CancellationToken cancellationToken)
    {
        var sql = PermissionSql + """
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.BuuCuc
                WHERE MaBuuCuc = @BranchId
                  AND DangHoatDong = 1
            )
                THROW 52101, N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.LoaiDichVu
                WHERE MaLoaiDichVu = @ServiceId
                  AND DangHoatDong = 1
            )
                THROW 52102, N'Dịch vụ không tồn tại hoặc đã ngừng hoạt động.', 1;

            DECLARE
                @ResolvedWeight DECIMAL(12,3),
                @PointsJson NVARCHAR(MAX);

            IF @OrderId IS NOT NULL
            BEGIN
                SELECT
                    @ResolvedWeight = d.TongKhoiLuongKg
                FROM dbo.DonHang d
                WHERE d.MaDonHang = @OrderId
                  AND d.MaBuuCuc = @BranchId;

                IF @@ROWCOUNT = 0
                    THROW 52104, N'Không tìm thấy đơn trong bưu cục được báo giá.', 1;

                SELECT @PointsJson = (
                    SELECT
                        p.LoaiDiem AS type,
                        p.ViDo AS latitude,
                        p.KinhDo AS longitude
                    FROM dbo.DiemGiaoNhan p
                    WHERE p.MaDonHang = @OrderId
                    ORDER BY p.MaDiemGiaoNhan
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                );
            END
            ELSE
            BEGIN
                SET @ResolvedWeight = @WeightKg;

                SELECT @PointsJson = (
                    SELECT
                        points.type,
                        points.latitude,
                        points.longitude
                    FROM (
                        SELECT
                            'PICKUP' AS type,
                            dc.ViDo AS latitude,
                            dc.KinhDo AS longitude
                        FROM dbo.DiaChiKhachHang dc
                        WHERE dc.MaDiaChiKhachHang = @PickupAddressId
                          AND dc.DangHoatDong = 1

                        UNION ALL

                        SELECT
                            'DELIVERY' AS type,
                            dc.ViDo AS latitude,
                            dc.KinhDo AS longitude
                        FROM dbo.DiaChiKhachHang dc
                        WHERE dc.MaDiaChiKhachHang = @DeliveryAddressId
                          AND dc.DangHoatDong = 1
                    ) points
                    ORDER BY points.type
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                );
            END;

            SELECT
                @ResolvedWeight AS WeightKg,
                COALESCE(@PointsJson, N'[]') AS PointsJson;
            """;

        await using var command = new SqlCommand(sql, connection);

        AddCommonParameters(command, accountId, request);

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt
        ).Value = (object?)request.OrderId ?? DBNull.Value;

        command.Parameters.Add(
            "@PickupAddressId", SqlDbType.BigInt
        ).Value = (object?)request.PickupAddressId ?? DBNull.Value;

        command.Parameters.Add(
            "@DeliveryAddressId", SqlDbType.BigInt
        ).Value = (object?)request.DeliveryAddressId ?? DBNull.Value;

        AddDecimal(
            command,
            "@WeightKg",
            request.WeightKg,
            12,
            3);

        await using var reader = await command.ExecuteReaderAsync(
            cancellationToken);

        if (!await reader.ReadAsync(cancellationToken)
            || reader["WeightKg"] == DBNull.Value)
        {
            throw new DispatchProblem(
                422,
                "Chưa có khối lượng hợp lệ để báo giá.");
        }

        return new QuoteSource(
            Convert.ToDecimal(reader["WeightKg"]),
            reader["PointsJson"].ToString() ?? "[]");
    }

    private QuoteRoute CalculateRoute(
        string pointsJson,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        using var document = JsonDocument.Parse(pointsJson);

        GeoPoint? pickup = null;
        GeoPoint? delivery = null;

        int pickupCount = 0;
        int deliveryCount = 0;

        foreach (var item in document.RootElement.EnumerateArray())
        {
            var type = item.GetProperty("type").GetString();

            if (type is not ("PICKUP" or "DELIVERY"))
                continue;

            if (type == "PICKUP")
                pickupCount++;
            else
                deliveryCount++;

            var latitude = item.GetProperty("latitude");
            var longitude = item.GetProperty("longitude");

            if (latitude.ValueKind != JsonValueKind.Number
                || longitude.ValueKind != JsonValueKind.Number
                || !latitude.TryGetDouble(out var lat)
                || !longitude.TryGetDouble(out var lng))
            {
                throw new DispatchProblem(
                    422,
                    "Địa chỉ lấy hoặc giao chưa có tọa độ hợp lệ. Hãy bổ sung tọa độ trước khi báo giá.");
            }

            var point = new GeoPoint(lat, lng);

            if (!point.IsValid)
            {
                throw new DispatchProblem(
                    422,
                    "Tọa độ điểm lấy hoặc điểm giao nằm ngoài phạm vi hợp lệ.");
            }

            if (type == "PICKUP")
                pickup = point;
            else
                delivery = point;
        }

        if (pickupCount != 1
            || deliveryCount != 1
            || pickup is null
            || delivery is null)
        {
            throw new DispatchProblem(
                422,
                "Cần đúng một địa chỉ lấy và một địa chỉ giao hợp lệ. Hãy kiểm tra địa chỉ còn hoạt động.");
        }

        var profile = (
            _configuration["Routing:FeeProfile"] ?? "motorcycle"
        ).Trim().ToLowerInvariant();

        if (profile is not ("motorcycle" or "hgv"))
        {
            throw new DispatchProblem(
                503,
                "Routing:FeeProfile chỉ hỗ trợ motorcycle hoặc hgv.");
        }

        var graph = _roadNetwork.Graph;
        var maxSnapMeters = _roadNetwork.MaxSnapMeters;

        var start = graph.Snap(pickup, profile, maxSnapMeters);
        var end = graph.Snap(delivery, profile, maxSnapMeters);

        cancellationToken.ThrowIfCancellationRequested();

        if (start is null || end is null)
        {
            throw new DispatchProblem(
                422,
                "Điểm lấy hoặc giao nằm ngoài vùng mạng đường hỗ trợ, hoặc quá xa nút đường phù hợp.");
        }

        if (start.Value.Node == end.Value.Node
            && RoadGraph.Meters(pickup, delivery) > 1)
        {
            throw new DispatchProblem(
                422,
                "Hai điểm được gắn vào cùng một nút đường nên chưa đủ độ chính xác để tính phí. Hãy kiểm tra tọa độ hoặc bổ sung mạng đường.");
        }

        var legs = graph.ShortestPaths(
            start.Value.Node,
            new[] { end.Value.Node },
            profile,
            cancellationToken);

        cancellationToken.ThrowIfCancellationRequested();

        var leg = legs[0];

        if (leg is null
            || !double.IsFinite(leg.DistanceMeters)
            || leg.DistanceMeters < 0)
        {
            throw new DispatchProblem(
                422,
                "Không tìm được đường hợp lệ từ điểm lấy đến điểm giao.");
        }

        var distance = leg.DistanceMeters / 1000d;

        if (distance > 1_000_000d)
        {
            throw new DispatchProblem(
                422,
                "Khoảng cách vượt giới hạn báo giá.");
        }

        var distanceKm = decimal.Round(
            (decimal)distance,
            2,
            MidpointRounding.AwayFromZero);

        if (distance > 0 && distanceKm == 0)
            distanceKm = 0.01m;

        return new QuoteRoute(
            distanceKm,
            profile,
            graph.Version,
            decimal.Round((decimal)start.Value.Distance, 2),
            decimal.Round((decimal)end.Value.Distance, 2));
    }

    private static async Task<IActionResult> CalculateFeeAsync(
        SqlConnection connection,
        long accountId,
        ShippingFeeQuoteRequest request,
        QuoteSource source,
        QuoteRoute route,
        CancellationToken cancellationToken)
    {
        // Kiểm tra lại quyền sau bước tính đường.
        var sql = PermissionSql + """
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.BuuCuc
                WHERE MaBuuCuc = @BranchId
                  AND DangHoatDong = 1
            )
                THROW 52101, N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.LoaiDichVu
                WHERE MaLoaiDichVu = @ServiceId
                  AND DangHoatDong = 1
            )
                THROW 52102, N'Dịch vụ không tồn tại hoặc đã ngừng hoạt động.', 1;

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

            SELECT TOP (1)
                q.MaQuyTacTinhPhi,
                bc.MaKhuVuc AS MaKhuVucBuuCuc,
                q.MaKhuVuc AS MaKhuVucQuyTac,
                dv.TenDichVu,
                q.PhiCoBan,
                q.PhiMoiKm,
                q.PhiMoiKg,
                @Now AS ThoiDiemTinhPhi
            FROM dbo.QuyTacTinhPhi q
            INNER JOIN dbo.BuuCuc bc
                ON bc.MaBuuCuc = @BranchId
            INNER JOIN dbo.LoaiDichVu dv
                ON dv.MaLoaiDichVu = q.MaLoaiDichVu
            WHERE q.MaLoaiDichVu = @ServiceId
              AND q.DangHoatDong = 1
              AND bc.DangHoatDong = 1
              AND dv.DangHoatDong = 1
              AND (
                  q.MaKhuVuc = bc.MaKhuVuc
                  OR q.MaKhuVuc IS NULL
              )
              AND q.HieuLucTu <= @Now
              AND (
                  q.HieuLucDen IS NULL
                  OR @Now < q.HieuLucDen
              )
              AND (
                  q.KhoangCachTuKm IS NULL
                  OR @DistanceKm >= q.KhoangCachTuKm
              )
              AND (
                  q.KhoangCachDenKm IS NULL
                  OR @DistanceKm <= q.KhoangCachDenKm
              )
              AND (
                  q.KhoiLuongTuKg IS NULL
                  OR @WeightKg >= q.KhoiLuongTuKg
              )
              AND (
                  q.KhoiLuongDenKg IS NULL
                  OR @WeightKg <= q.KhoiLuongDenKg
              )
            ORDER BY
                CASE
                    WHEN q.MaKhuVuc = bc.MaKhuVuc
                    THEN 0 ELSE 1
                END,
                q.HieuLucTu DESC,
                q.MaQuyTacTinhPhi;
            """;

        await using var command = new SqlCommand(sql, connection);

        AddCommonParameters(command, accountId, request);

        AddDecimal(
            command,
            "@DistanceKm",
            route.DistanceKm,
            10,
            2);

        AddDecimal(
            command,
            "@WeightKg",
            source.WeightKg,
            12,
            3);

        await using var reader = await command.ExecuteReaderAsync(
            cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return new UnprocessableEntityObjectResult(new
            {
                message = "Chưa có quy tắc phí phù hợp với dịch vụ, khu vực, khoảng cách, khối lượng và thời điểm hiện tại."
            });
        }

        var baseFee = Convert.ToDecimal(reader["PhiCoBan"]);
        var feePerKm = Convert.ToDecimal(reader["PhiMoiKm"]);
        var feePerKg = Convert.ToDecimal(reader["PhiMoiKg"]);

        var distanceFee = route.DistanceKm * feePerKm;
        var weightFee = source.WeightKg * feePerKg;

        var shippingFee = decimal.Round(
            baseFee + distanceFee + weightFee,
            0,
            MidpointRounding.AwayFromZero);

        if (shippingFee < 0
            || shippingFee > 9_999_999_999_999_999.99m)
        {
            return new UnprocessableEntityObjectResult(new
            {
                message = "Phí tính được nằm ngoài giới hạn lưu trữ. Hãy kiểm tra quy tắc tính phí."
            });
        }

        return new OkObjectResult(new
        {
            orderId = request.OrderId,
            branchId = request.BranchId,
            serviceId = request.ServiceId,
            serviceName = reader["TenDichVu"].ToString(),
            ruleId = Convert.ToInt64(reader["MaQuyTacTinhPhi"]),
            branchAreaId = Convert.ToInt32(reader["MaKhuVucBuuCuc"]),
            ruleAreaId = reader["MaKhuVucQuyTac"] == DBNull.Value
                ? (int?)null
                : Convert.ToInt32(reader["MaKhuVucQuyTac"]),

            distanceKm = route.DistanceKm,
            distanceSource = "DIJKSTRA",
            distanceBasis = "SNAPPED_ROAD",
            routingProfile = route.Profile,
            graphVersion = route.GraphVersion,
            pickupSnapMeters = route.PickupSnapMeters,
            deliverySnapMeters = route.DeliverySnapMeters,

            weightKg = source.WeightKg,
            baseFee,
            feePerKm,
            feePerKg,
            distanceFee,
            weightFee,
            shippingFee,

            baseFeeExact = baseFee.ToString(
                "0.00", CultureInfo.InvariantCulture),

            distanceFeeExact = distanceFee.ToString(
                "0.00", CultureInfo.InvariantCulture),

            weightFeeExact = weightFee.ToString(
                "0.00", CultureInfo.InvariantCulture),

            shippingFeeExact = shippingFee.ToString(
                "0", CultureInfo.InvariantCulture),

            currency = "VND",

            quotedAt = DateTime.SpecifyKind(
                Convert.ToDateTime(reader["ThoiDiemTinhPhi"]),
                DateTimeKind.Utc),

            message = "Báo giá tham khảo theo mạng đường. Phí chính thức được tính lại khi xác nhận đơn."
        });
    }

    private static void AddCommonParameters(
        SqlCommand command,
        long accountId,
        ShippingFeeQuoteRequest request)
    {
        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt
        ).Value = accountId;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int
        ).Value = request.BranchId;

        command.Parameters.Add(
            "@ServiceId", SqlDbType.Int
        ).Value = request.ServiceId;
    }

    private static void AddDecimal(
        SqlCommand command,
        string name,
        decimal? value,
        byte precision,
        byte scale)
    {
        var parameter = command.Parameters.Add(
            name,
            SqlDbType.Decimal);

        parameter.Precision = precision;
        parameter.Scale = scale;
        parameter.Value = (object?)value ?? DBNull.Value;
    }
}