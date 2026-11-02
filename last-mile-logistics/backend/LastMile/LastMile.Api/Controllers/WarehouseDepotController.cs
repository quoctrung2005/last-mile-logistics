using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using static LastMile.Api.Services.Routing.DispatchData;

namespace LastMile.Api.Controllers;

public sealed record DepotSnapshot(decimal? Latitude, decimal? Longitude, string? CoordinateSource);
public sealed class UpdateDepotRequest
{
    [Required, Range(typeof(decimal), "-90", "90")] public decimal? Latitude { get; set; }
    [Required, Range(typeof(decimal), "-180", "180")] public decimal? Longitude { get; set; }
    [Required, StringLength(300)] public string CoordinateSource { get; set; } = "";
    public bool CoordinatesConfirmed { get; set; }
    [Required] public DepotSnapshot? Expected { get; set; }
}

[ApiController, Authorize, TypeFilter(typeof(DispatchExceptionFilter))]
[Route("api/v1/warehouses/{id:int}/depot")]
public sealed class WarehouseDepotController(DispatchData data, RoadNetwork network, ILogger<WarehouseDepotController> logger) : ControllerBase
{
    long AccountId => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : throw new DispatchProblem(401, "Phiên đăng nhập không hợp lệ.");

    [HttpGet]
    public async Task<IActionResult> Get(int id, CancellationToken ct)
    {
        if (id <= 0) return BadRequest(new { message = "Mã kho phải lớn hơn 0." });
        await using var connection = data.Connection(); await connection.OpenAsync(ct); await EnsureSchema(connection, ct);
        var access = await Authorize(connection, null, AccountId,
            ["DIEUPHOI_GOMDON", "DIEUPHOI_TOIUUTUYEN", "DIEUPHOI_PHANCONG", "DIEUPHOI_GIAMSAT", "BUUCUC_QUANLY"], ct, true);
        await using var command = Command(connection, null, $$"""
            SELECT k.MaKho Id,k.KyHieuKho Code,k.TenKho Name,COALESCE(k.DiaChi,N'') Address,k.MaBuuCuc BranchId,
              (SELECT {{DepotColumns}},k.NguonToaDo coordinateSource FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER) Coordinates,
              CONVERT(BIT,CASE WHEN @admin=1 AND EXISTS(SELECT 1 FROM dbo.TaiKhoan t JOIN dbo.VaiTroQuyen p ON p.MaVaiTro=t.MaVaiTro JOIN dbo.Quyen q ON q.MaQuyen=p.MaQuyen WHERE t.MaTaiKhoan=@account AND q.KyHieuQuyen='BUUCUC_QUANLY') THEN 1 ELSE 0 END) CanManage
            FROM dbo.Kho k JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc
            WHERE k.MaKho=@id AND k.DangHoatDong=1 AND b.DangHoatDong=1 AND (@admin=1 OR k.MaBuuCuc=@branch);
            """, ("@id", id), ("@admin", access.Role == "ADMIN"), ("@branch", access.BranchId), ("@account", AccountId));
        await using var reader = await command.ExecuteReaderAsync(ct);
        var row = await SqlResult.ReadSingleAsync(reader, ["Id", "Code", "Name", "Address", "BranchId", "Coordinates", "CanManage"], r => new
        {
            Id = r.IntId("Id"), Code = r.Text("Code"), Name = r.Text("Name"), Address = r.Required<string>("Address"),
            BranchId = r.IntId("BranchId"), Coordinates = System.Text.Json.JsonSerializer.Deserialize<DepotSnapshot>(r.Text("Coordinates"), Json)!,
            CanManage = r.Required<bool>("CanManage")
        }, ct, whenEmpty: () => null!);
        await reader.DisposeAsync();
        if (row is null) return NotFound(new { message = "Không tìm thấy kho hoạt động trong phạm vi được phép." });
        var coordinates = row.Coordinates;
        var assessment = DepotCoordinates.Check((double?)coordinates.Latitude, (double?)coordinates.Longitude);
        var connectivity = new List<object>();
        if (assessment.State == "CONFIGURED")
        {
            try
            {
                var graph = network.Graph;
                foreach (var profile in new[] { "motorcycle", "hgv" })
                {
                    ct.ThrowIfCancellationRequested();
                    var snap = graph.Snap(new((double)coordinates.Latitude!.Value, (double)coordinates.Longitude!.Value), profile, network.MaxSnapMeters);
                    connectivity.Add(new { profile, state = snap.HasValue ? "CONNECTED" : "DISCONNECTED", snapDistanceMeters = snap?.Distance,
                        message = snap.HasValue ? "Kho nối được mạng đường." : $"Tọa độ kho hợp lệ nhưng không nối được mạng đường {profile} trong {network.MaxSnapMeters:0} m. Kiểm tra vị trí đã xác minh và vùng dữ liệu OSM." });
                }
            }
            catch (Exception error) when (error is IOException or InvalidDataException or System.Xml.XmlException or UnauthorizedAccessException or ArgumentException)
            {
                logger.LogWarning("Depot road diagnostics unavailable for warehouse {WarehouseId}: {ErrorType}", id, error.GetType().Name);
                connectivity.Add(new { profile = "all", state = "UNAVAILABLE", message = "Chưa đọc được mạng đường. Tọa độ kho vẫn được giữ; cần kiểm tra cấu hình mạng đường." });
            }
        }
        return Ok(new { id = row.Id, code = row.Code, name = row.Name, address = row.Address, branchId = row.BranchId,
            latitude = coordinates.Latitude, longitude = coordinates.Longitude, coordinateSource = coordinates.CoordinateSource,
            canManageDepot = row.CanManage, coordinateState = assessment.State, coordinateMessage = assessment.Message, connectivity });
    }

    [HttpPut]
    public async Task<IActionResult> Update(int id, UpdateDepotRequest request, CancellationToken ct)
    {
        if (id <= 0 || request.Latitude is null || request.Longitude is null || request.Expected is null ||
            !request.CoordinatesConfirmed || string.IsNullOrWhiteSpace(request.CoordinateSource) || request.CoordinateSource.Length > 300 ||
            decimal.Round(request.Latitude.Value, 6) != request.Latitude || decimal.Round(request.Longitude.Value, 6) != request.Longitude ||
            DepotCoordinates.Check((double?)request.Latitude, (double?)request.Longitude).State != "CONFIGURED")
            return BadRequest(new { message = "Nhập tọa độ kho hợp lệ tối đa 6 số lẻ, nguồn xác minh và xác nhận đúng vị trí thực tế; không dùng tọa độ mẫu hoặc tự lấy từ bưu cục." });
        await using var connection = data.Connection(); await connection.OpenAsync(ct); await EnsureSchema(connection, ct);
        await using var tx = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var access = await Authorize(connection, tx, AccountId, ["BUUCUC_QUANLY"], ct);
        if (access.Role != "ADMIN") throw new DispatchProblem(403, "Chỉ admin có quyền quản lý bưu cục được cập nhật tọa độ kho.");
        bool commitAttempted = false;
        try
        {
            await using var command = Command(connection, tx, """
                SET NOCOUNT ON;
                DECLARE @old NVARCHAR(MAX),@currentLat DECIMAL(9,6),@currentLon DECIMAL(10,6),@currentSource NVARCHAR(300);
                SELECT @old=(SELECT k.MaKho id,k.ViDo latitude,k.KinhDo longitude,k.NguonToaDo coordinateSource FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),
                  @currentLat=k.ViDo,@currentLon=k.KinhDo,@currentSource=k.NguonToaDo
                FROM dbo.Kho k WITH(UPDLOCK,HOLDLOCK) JOIN dbo.BuuCuc b WITH(HOLDLOCK) ON b.MaBuuCuc=k.MaBuuCuc
                WHERE k.MaKho=@id AND k.DangHoatDong=1 AND b.DangHoatDong=1;
                IF @old IS NULL THROW 54804,N'Không tìm thấy kho hoạt động.',1;
                IF (@currentLat<>@expectedLat OR (@currentLat IS NULL AND @expectedLat IS NOT NULL) OR (@currentLat IS NOT NULL AND @expectedLat IS NULL))
                 OR (@currentLon<>@expectedLon OR (@currentLon IS NULL AND @expectedLon IS NOT NULL) OR (@currentLon IS NOT NULL AND @expectedLon IS NULL))
                 OR (@currentSource COLLATE Latin1_General_100_BIN2<>@expectedSource COLLATE Latin1_General_100_BIN2 OR (@currentSource IS NULL AND @expectedSource IS NOT NULL) OR (@currentSource IS NOT NULL AND @expectedSource IS NULL))
                    THROW 54805,N'Tọa độ kho đã được thay đổi. Hãy tải lại để kiểm tra trước khi cập nhật.',1;
                UPDATE dbo.Kho SET ViDo=@lat,KinhDo=@lon,NguonToaDo=@source WHERE MaKho=@id;
                INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson)
                VALUES(@account,'UPDATE_WAREHOUSE_DEPOT','Kho',CONVERT(VARCHAR(100),@id),@old,
                  (SELECT @id id,@lat latitude,@lon longitude,@source coordinateSource FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
                SELECT @id Id,@lat Latitude,@lon Longitude,@source CoordinateSource;
                """, ("@id", id), ("@lat", request.Latitude), ("@lon", request.Longitude), ("@source", request.CoordinateSource.Trim()),
                ("@expectedLat", request.Expected.Latitude), ("@expectedLon", request.Expected.Longitude), ("@expectedSource", request.Expected.CoordinateSource), ("@account", AccountId));
            // Explicit types are required when the original snapshot contains NULL.
            foreach (var name in new[] { "@lat", "@expectedLat" }) { command.Parameters[name].SqlDbType = SqlDbType.Decimal; command.Parameters[name].Precision = 9; command.Parameters[name].Scale = 6; }
            foreach (var name in new[] { "@lon", "@expectedLon" }) { command.Parameters[name].SqlDbType = SqlDbType.Decimal; command.Parameters[name].Precision = 10; command.Parameters[name].Scale = 6; }
            foreach (var name in new[] { "@source", "@expectedSource" }) { command.Parameters[name].SqlDbType = SqlDbType.NVarChar; command.Parameters[name].Size = 300; }
            object result;
            await using (var reader = await command.ExecuteReaderAsync(ct))
                result = await SqlResult.ReadSingleAsync(reader, ["Id", "Latitude", "Longitude", "CoordinateSource"], r => new
                {
                    id = r.IntId("Id"), latitude = r.Required<decimal>("Latitude"), longitude = r.Required<decimal>("Longitude"),
                    coordinateSource = r.Text("CoordinateSource"), message = "Đã cập nhật tọa độ kho. Hãy tải lại dữ liệu và tính lại phương án."
                }, ct);
            commitAttempted = true; await tx.CommitAsync(ct); return Ok(result);
        }
        catch (SqlException error) when (error.Number is 54804 or 54805)
        { return StatusCode(error.Number == 54804 ? 404 : 409, new { message = error.Message }); }
        catch (SqlResultContractException error)
        { return SqlResult.Failure(logger, "PUT /api/v1/warehouses/{id}/depot", id, error.Message, commitAttempted); }
        catch (SqlException error)
        { return SqlResult.Failure(logger, "PUT /api/v1/warehouses/{id}/depot", id, SqlResult.ErrorReason(error), commitAttempted); }
        catch (OperationCanceledException) when (commitAttempted)
        { return SqlResult.Failure(logger, "PUT /api/v1/warehouses/{id}/depot", id, "Commit cancelled; outcome unknown", true); }
    }
}
