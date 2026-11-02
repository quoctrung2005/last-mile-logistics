using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using System.Xml;
using LastMile.Api.Services.Routing;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class ConfirmOrderRequest
{
    // Không bắt buộc để tương thích frontend hiện tại.
    // Khi frontend có gửi, API kiểm tra phiên bản người dùng đang xem.
    [StringLength(16)]
    public string? ExpectedVersion { get; set; }
}

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public class OrderConfirmController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderConfirmController> _logger;
    private readonly RoadNetwork _roadNetwork;

    public OrderConfirmController(
        IConfiguration configuration,
        ILogger<OrderConfirmController> logger,
        RoadNetwork roadNetwork)
    {
        _configuration = configuration;
        _logger = logger;
        _roadNetwork = roadNetwork;
    }

    private sealed record OrderSnapshot(
        byte[] Version,
        string PointsJson,
        string Status);

    private sealed record RoutingResult(
        decimal DistanceKm,
        string Profile,
        string GraphVersion,
        decimal PickupSnapMeters,
        decimal DeliverySnapMeters);

    [HttpPost("{id:long}/confirm")]
    public async Task<IActionResult> Confirm(
        long id,
        ConfirmOrderRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã đơn phải lớn hơn 0."
            });
        }

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        byte[]? expectedVersion = null;

        if (request.ExpectedVersion is not null)
        {
            try
            {
                expectedVersion = Convert.FromBase64String(
                    request.ExpectedVersion);

                if (expectedVersion.Length != 8)
                {
                    return BadRequest(new
                    {
                        message = "ExpectedVersion phải là rowversion Base64 gồm 8 byte."
                    });
                }
            }
            catch (FormatException)
            {
                return BadRequest(new
                {
                    message = "ExpectedVersion không phải chuỗi Base64 hợp lệ."
                });
            }
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        var writeAttempted = false;

        try
        {
            await connection.OpenAsync(cancellationToken);

            // Đọc dữ liệu để tính đường, chưa giữ transaction ghi.
            var snapshot = await ReadSnapshotAsync(
                connection,
                id,
                accountId,
                cancellationToken);

            if (expectedVersion is not null
                && !expectedVersion.AsSpan().SequenceEqual(snapshot.Version))
            {
                return Conflict(new
                {
                    message = "Đơn đã được cập nhật. Hãy tải lại chi tiết trước khi xác nhận."
                });
            }

            var route = CalculateRoute(
                snapshot.PointsJson,
                cancellationToken);

            // Khi ghi, SQL kiểm tra lại phiên bản và tọa độ.
            // Nếu đơn thay đổi trong lúc tính đường, toàn bộ thao tác bị hủy.
            writeAttempted = true;
            return await SaveConfirmationAsync(
                connection,
                id,
                accountId,
                snapshot,
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
        catch (SqlException ex) when (ex.Number == 52201)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52202)
        {
            return NotFound(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 52204)
        {
            return UnprocessableEntity(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex)
            when (ex.Number is 52205 or 51002)
        {
            return BadRequest(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex)
            when (ex.Number is
                52203 or 52206 or 52207 or
                51110 or 51001 or 1205)
        {
            return Conflict(new
            {
                message = ex.Number == 1205
                    ? "Dữ liệu đang được xử lý đồng thời. Hãy tải lại và thử xác nhận."
                    : ex.Message
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
                "Không đọc được dữ liệu đường khi xác nhận đơn {OrderId}.",
                id);

            return StatusCode(503, new
            {
                message = "Không đọc được mạng đường. Hãy kiểm tra Routing:GraphPath và tệp OSM."
            });
        }
        catch (SqlException ex)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/orders/{id}/confirm", id, SqlResult.ErrorReason(ex), writeAttempted);
        }
        catch (SqlResultContractException ex)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/orders/{id}/confirm", id, ex.Message, writeAttempted);
        }
        catch (OperationCanceledException) when (writeAttempted)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/orders/{id}/confirm", id, "Command cancelled while saving or reading its result", true);
        }
    }

    private static async Task<OrderSnapshot> ReadSnapshotAsync(
        SqlConnection connection,
        long orderId,
        long accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @IsAdmin BIT = 0,
                @AccountBranchId INT,
                @Allowed BIT = 0;

            SELECT
                @Allowed = 1,
                @IsAdmin = CASE
                    WHEN vt.KyHieuVaiTro = 'ADMIN'
                    THEN 1 ELSE 0
                END,
                @AccountBranchId = tk.MaBuuCuc
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
              AND EXISTS (
                  SELECT 1
                  FROM dbo.VaiTroQuyen vq
                  INNER JOIN dbo.Quyen q
                      ON q.MaQuyen = vq.MaQuyen
                  WHERE vq.MaVaiTro = tk.MaVaiTro
                    AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
              );

            IF @Allowed = 0
               OR (@IsAdmin = 0 AND @AccountBranchId IS NULL)
                THROW 52201, N'Không có quyền xác nhận đơn.', 1;

            SELECT
                d.PhienBan AS Version,
                tt.KyHieuTrangThai AS Status,
                (
                    SELECT
                        p.MaDiemGiaoNhan AS id,
                        p.LoaiDiem AS type,
                        p.ViDo AS latitude,
                        p.KinhDo AS longitude
                    FROM dbo.DiemGiaoNhan p
                    WHERE p.MaDonHang = d.MaDonHang
                    ORDER BY p.MaDiemGiaoNhan
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                ) AS PointsJson
            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND (
                  @IsAdmin = 1
                  OR d.MaBuuCuc = @AccountBranchId
              );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt
        ).Value = orderId;

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt
        ).Value = accountId;

        await using var reader = await command.ExecuteReaderAsync(
            cancellationToken);

        var result = await SqlResult.ReadSingleAsync(reader, ["Version", "Status", "PointsJson"],
            row => (OrderSnapshot?)new OrderSnapshot(row.Version(), row.JsonArray("PointsJson"), row.Text("Status")),
            cancellationToken, whenEmpty: () => null);

        if (result is null)
        {
            throw new DispatchProblem(
                404,
                "Không tìm thấy đơn trong phạm vi được xem.");
        }

        if (result.Status != "NEW")
        {
            throw new DispatchProblem(
                409,
                "Chỉ được xác nhận đơn ở trạng thái NEW.");
        }

        return result;
    }

    private RoutingResult CalculateRoute(
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
                    "Điểm lấy hoặc điểm giao chưa có tọa độ. Hãy bổ sung tọa độ trước khi xác nhận.");
            }

            var point = new GeoPoint(lat, lng);

            if (!point.IsValid)
            {
                throw new DispatchProblem(
                    422,
                    "Tọa độ điểm lấy hoặc điểm giao không hợp lệ.");
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
                "Đơn phải có đúng một điểm lấy và một điểm giao có tọa độ.");
        }

        // Profile tham chiếu tính phí, độc lập với xe được phân công sau này.
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
                "Điểm lấy hoặc điểm giao nằm ngoài vùng mạng đường hỗ trợ, hoặc quá xa nút đường phù hợp.");
        }

        // Hai địa chỉ khác nhau nhưng cùng được gắn vào một nút:
        // không tự tính khoảng cách bằng 0 để tránh tính phí sai.
        if (start.Value.Node == end.Value.Node
            && RoadGraph.Meters(pickup, delivery) > 1)
        {
            throw new DispatchProblem(
                422,
                "Hai điểm đang được gắn vào cùng một nút đường nên chưa đủ độ chính xác để tính phí. Hãy kiểm tra tọa độ hoặc bổ sung dữ liệu mạng đường.");
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
                "Không tìm được đường hợp lệ từ điểm lấy đến điểm giao theo mạng đường hiện tại.");
        }

        var distance = leg.DistanceMeters / 1000d;

        if (distance > 1_000_000d)
        {
            throw new DispatchProblem(
                422,
                "Khoảng cách tuyến vượt giới hạn tính phí.");
        }

        var distanceKm = decimal.Round(
            (decimal)distance,
            2,
            MidpointRounding.AwayFromZero);

        if (distance > 0 && distanceKm == 0)
            distanceKm = 0.01m;

        return new RoutingResult(
            distanceKm,
            profile,
            graph.Version,
            decimal.Round((decimal)start.Value.Distance, 2),
            decimal.Round((decimal)end.Value.Distance, 2));
    }

    private static async Task<IActionResult> SaveConfirmationAsync(
        SqlConnection connection,
        long orderId,
        long accountId,
        OrderSnapshot snapshot,
        RoutingResult route,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @IsAdmin BIT = 0,
                    @AccountBranchId INT,
                    @Allowed BIT = 0;

                SELECT
                    @Allowed = 1,
                    @IsAdmin = CASE
                        WHEN vt.KyHieuVaiTro = 'ADMIN'
                        THEN 1 ELSE 0
                    END,
                    @AccountBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  )
                  AND EXISTS (
                      SELECT 1
                      FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                      INNER JOIN dbo.Quyen q WITH (HOLDLOCK)
                          ON q.MaQuyen = vq.MaQuyen
                      WHERE vq.MaVaiTro = tk.MaVaiTro
                        AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                  );

                IF @Allowed = 0
                   OR (@IsAdmin = 0 AND @AccountBranchId IS NULL)
                    THROW 52201, N'Không có quyền xác nhận đơn.', 1;

                DECLARE
                    @BranchId INT,
                    @ServiceId INT,
                    @Status VARCHAR(40),
                    @WeightKg DECIMAL(12,3),
                    @OldFee DECIMAL(18,2),
                    @CurrentVersion BINARY(8);

                SELECT
                    @BranchId = d.MaBuuCuc,
                    @ServiceId = d.MaLoaiDichVu,
                    @Status = tt.KyHieuTrangThai,
                    @WeightKg = d.TongKhoiLuongKg,
                    @OldFee = d.PhiVanChuyen,
                    @CurrentVersion = d.PhienBan
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt WITH (HOLDLOCK)
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @IsAdmin = 1
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @Status IS NULL
                    THROW 52202, N'Không tìm thấy đơn trong phạm vi được xem.', 1;

                IF @Status <> 'NEW'
                    THROW 52203, N'Chỉ được xác nhận đơn ở trạng thái NEW.', 1;

                IF @CurrentVersion IS NULL
                   OR @CurrentVersion <> @SnapshotVersion
                    THROW 52207, N'Đơn đã thay đổi trong lúc tính đường. Hãy tải lại và xác nhận lại.', 1;

                DECLARE @CurrentPoints NVARCHAR(MAX);

                SELECT @CurrentPoints = (
                    SELECT
                        p.MaDiemGiaoNhan AS id,
                        p.LoaiDiem AS type,
                        p.ViDo AS latitude,
                        p.KinhDo AS longitude
                    FROM dbo.DiemGiaoNhan p WITH (UPDLOCK, HOLDLOCK)
                    WHERE p.MaDonHang = @OrderId
                    ORDER BY p.MaDiemGiaoNhan
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                );

                IF @CurrentPoints IS NULL
                   OR @CurrentPoints COLLATE Latin1_General_100_BIN2
                      <> @PointsJson COLLATE Latin1_General_100_BIN2
                    THROW 52207, N'Điểm lấy hoặc điểm giao đã thay đổi. Hãy tải lại và xác nhận lại.', 1;

                IF @WeightKg IS NULL OR @WeightKg <= 0
                    THROW 52205, N'Đơn phải có hàng hóa với khối lượng lớn hơn 0.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc WITH (HOLDLOCK)
                    WHERE MaBuuCuc = @BranchId
                      AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.LoaiDichVu WITH (HOLDLOCK)
                    WHERE MaLoaiDichVu = @ServiceId
                      AND DangHoatDong = 1
                )
                    THROW 52205, N'Bưu cục hoặc dịch vụ đã ngừng hoạt động.', 1;

                DECLARE
                    @RuleId BIGINT,
                    @BaseFee DECIMAL(18,2),
                    @FeePerKm DECIMAL(18,2),
                    @FeePerKg DECIMAL(18,2),
                    @Now DATETIME2(0) = SYSUTCDATETIME();

                SELECT TOP (1)
                    @RuleId = q.MaQuyTacTinhPhi,
                    @BaseFee = q.PhiCoBan,
                    @FeePerKm = q.PhiMoiKm,
                    @FeePerKg = q.PhiMoiKg
                FROM dbo.QuyTacTinhPhi q WITH (HOLDLOCK)
                INNER JOIN dbo.BuuCuc bc WITH (HOLDLOCK)
                    ON bc.MaBuuCuc = @BranchId
                WHERE q.MaLoaiDichVu = @ServiceId
                  AND q.DangHoatDong = 1
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

                IF @RuleId IS NULL
                    THROW 52204, N'Chưa có quy tắc tính phí phù hợp.', 1;

                DECLARE @CalculatedFee DECIMAL(18,2) =
                    ROUND(
                        @BaseFee
                        + @DistanceKm * @FeePerKm
                        + @WeightKg * @FeePerKg,
                        0
                    );

                DELETE FROM dbo.KhoanPhiDonHang
                WHERE MaDonHang = @OrderId
                  AND LoaiKhoanPhi = 'SHIPPING';

                INSERT INTO dbo.KhoanPhiDonHang (
                    MaDonHang,
                    LoaiKhoanPhi,
                    SoTien,
                    MoTa
                )
                VALUES (
                    @OrderId,
                    'SHIPPING',
                    @CalculatedFee,
                    CONCAT(
                        N'Quy tắc #', @RuleId,
                        N'; Dijkstra; profile ', @Profile,
                        N'; khoảng cách nút đường ', @DistanceKm,
                        N' km; khối lượng ', @WeightKg, N' kg.'
                    )
                );

                DECLARE @TotalFee DECIMAL(18,2);

                SELECT @TotalFee = COALESCE(SUM(SoTien), 0)
                FROM dbo.KhoanPhiDonHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId;

                IF @TotalFee < 0
                    THROW 52206, N'Tổng phí sau giảm giá không được âm.', 1;

                UPDATE dbo.DonHang
                SET PhiVanChuyen = @TotalFee,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_XacNhanDonHang
                    @MaDonHang = @OrderId,
                    @MaTaiKhoan = @AccountId
                    WITH RESULT SETS NONE;

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuCuJson,
                    DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'CONFIRM_ORDER',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    (
                        SELECT
                            'NEW' AS status,
                            @OldFee AS shippingFee
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT
                            'CONFIRMED' AS status,
                            @TotalFee AS shippingFee,
                            @RuleId AS ruleId,
                            @DistanceKm AS distanceKm,
                            'DIJKSTRA' AS distanceSource,
                            'SNAPPED_ROAD' AS distanceBasis,
                            @Profile AS routingProfile,
                            @GraphVersion AS graphVersion,
                            @PickupSnapMeters AS pickupSnapMeters,
                            @DeliverySnapMeters AS deliverySnapMeters
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )
                );

                DECLARE @ResultVersion BINARY(8);

                SELECT @ResultVersion = PhienBan
                FROM dbo.DonHang
                WHERE MaDonHang = @OrderId;

                COMMIT;

                SELECT
                    @RuleId AS RuleId,
                    @WeightKg AS WeightKg,
                    @CalculatedFee AS CalculatedFee,
                    @TotalFee AS TotalFee,
                    @ResultVersion AS Version;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

                THROW;
            END CATCH;
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt
        ).Value = orderId;

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt
        ).Value = accountId;

        command.Parameters.Add(
            "@SnapshotVersion", SqlDbType.Binary, 8
        ).Value = snapshot.Version;

        command.Parameters.Add(
            "@PointsJson", SqlDbType.NVarChar, -1
        ).Value = snapshot.PointsJson;

        AddDecimal(command, "@DistanceKm", route.DistanceKm, 10, 2);

        AddDecimal(
            command,
            "@PickupSnapMeters",
            route.PickupSnapMeters,
            10,
            2);

        AddDecimal(
            command,
            "@DeliverySnapMeters",
            route.DeliverySnapMeters,
            10,
            2);

        command.Parameters.Add(
            "@Profile", SqlDbType.VarChar, 20
        ).Value = route.Profile;

        command.Parameters.Add(
            "@GraphVersion", SqlDbType.VarChar, 64
        ).Value = route.GraphVersion;

        await using var reader = await command.ExecuteReaderAsync(
            cancellationToken);

        var result = await SqlResult.ReadSingleAsync(reader,
            ["RuleId", "WeightKg", "CalculatedFee", "TotalFee", "Version"], row => new
        {
            RuleId = row.Id("RuleId"), WeightKg = row.NonNegative("WeightKg"),
            CalculatedFee = row.NonNegative("CalculatedFee"), TotalFee = row.NonNegative("TotalFee"), Version = row.Version()
        }, cancellationToken);

        return new OkObjectResult(new
        {
            id = orderId,
            status = "CONFIRMED",
            version = Convert.ToBase64String(result.Version),
            ruleId = result.RuleId,
            distanceKm = route.DistanceKm,
            distanceSource = "DIJKSTRA",
            distanceBasis = "SNAPPED_ROAD",
            routingProfile = route.Profile,
            graphVersion = route.GraphVersion,
            pickupSnapMeters = route.PickupSnapMeters,
            deliverySnapMeters = route.DeliverySnapMeters,
            weightKg = result.WeightKg,
            calculatedShippingFee = result.CalculatedFee,
            shippingFee = result.TotalFee,
            message = "Đã tính phí theo mạng đường và xác nhận đơn thành công."
        });
    }

    private static void AddDecimal(
        SqlCommand command,
        string name,
        decimal value,
        byte precision,
        byte scale)
    {
        var parameter = command.Parameters.Add(
            name,
            SqlDbType.Decimal);

        parameter.Precision = precision;
        parameter.Scale = scale;
        parameter.Value = value;
    }
}
