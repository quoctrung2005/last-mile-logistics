using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class SaveCatalogRequest
{
    [Required]
    [RegularExpression(
        "^(AREAS|SERVICES|BRANCHES|WAREHOUSES|LOCATIONS)$")]
    public string Type { get; set; } = "";

    [Range(typeof(long), "1", "9223372036854775807")]
    public long? Id { get; set; }

    [Required]
    [StringLength(50)]
    [RegularExpression(
        @"^[A-Z0-9][A-Z0-9_-]*$",
        ErrorMessage =
            "Code chỉ gồm chữ in hoa, số, gạch ngang hoặc gạch dưới.")]
    public string Code { get; set; } = "";

    [StringLength(150)]
    public string? Name { get; set; }

    [Required]
    public bool? IsActive { get; set; }

    // AREAS
    [Range(1, int.MaxValue)]
    public int? ParentId { get; set; }

    [RegularExpression("^(CITY|DISTRICT|WARD|SERVICE_ZONE)$")]
    public string? AreaType { get; set; }

    // BRANCHES
    [Range(1, int.MaxValue)]
    public int? AreaId { get; set; }

    [StringLength(300)]
    public string? Address { get; set; }

    [StringLength(20)]
    [RegularExpression(
        @"^\+?[0-9]{9,15}$",
        ErrorMessage = "Số điện thoại không hợp lệ.")]
    public string? Phone { get; set; }

    [StringLength(150)]
    [EmailAddress]
    public string? Email { get; set; }

    [Range(
        typeof(decimal), "-90", "90",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Latitude { get; set; }

    [Range(
        typeof(decimal), "-180", "180",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Longitude { get; set; }

    // WAREHOUSES
    [Range(1, int.MaxValue)]
    public int? BranchId { get; set; }

    // LOCATIONS
    [Range(1, int.MaxValue)]
    public int? WarehouseId { get; set; }

    [StringLength(100)]
    public string? StorageArea { get; set; }

    [StringLength(50)]
    [RegularExpression(@"^[A-Za-z0-9 ._-]+$")]
    public string? Rack { get; set; }

    [StringLength(50)]
    [RegularExpression(@"^[A-Za-z0-9 ._-]+$")]
    public string? Slot { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/catalogs")]
public class CatalogSaveController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CatalogSaveController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    private sealed record CatalogDefinition(
        string Table,
        string IdColumn,
        string Projection,
        string InsertColumns,
        string InsertValues,
        string UpdateColumns);

    [HttpPost]
    public async Task<IActionResult> Save(
        SaveCatalogRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        var type = request.Type;
        var name = request.Name?.Trim();

        if (type != "LOCATIONS")
        {
            if (request.Id > int.MaxValue)
            {
                return BadRequest(new
                {
                    message = "Id vượt quá giới hạn của danh mục này."
                });
            }

            if (request.Code.Length > 30)
            {
                return BadRequest(new
                {
                    message = "Code tối đa 30 ký tự."
                });
            }

            if (string.IsNullOrWhiteSpace(name))
            {
                return BadRequest(new
                {
                    message = "Phải nhập name."
                });
            }
        }

        if (type == "AREAS"
            && string.IsNullOrWhiteSpace(request.AreaType))
        {
            return BadRequest(new
            {
                message = "Phải nhập areaType khi lưu khu vực."
            });
        }

        if (type == "SERVICES")
        {
            if (name!.Length > 100)
            {
                return BadRequest(new
                {
                    message = "Tên dịch vụ tối đa 100 ký tự."
                });
            }

            if (request.ParentId.HasValue
                || request.AreaType is not null)
            {
                return BadRequest(new
                {
                    message =
                        "Dịch vụ không sử dụng parentId hoặc areaType."
                });
            }
        }

        if (type == "BRANCHES"
            && (!request.AreaId.HasValue
                || string.IsNullOrWhiteSpace(request.Address)))
        {
            return BadRequest(new
            {
                message = "Bưu cục phải có areaId và address."
            });
        }

        if (type == "WAREHOUSES" && !request.BranchId.HasValue)
        {
            return BadRequest(new
            {
                message = "Kho phải có branchId."
            });
        }

        if (type == "LOCATIONS" && !request.WarehouseId.HasValue)
        {
            return BadRequest(new
            {
                message = "Vị trí lưu kho phải có warehouseId."
            });
        }

        if (request.Latitude.HasValue != request.Longitude.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải nhập đồng thời latitude và longitude."
            });
        }

        if ((request.Latitude.HasValue
             && decimal.Round(request.Latitude.Value, 6)
                != request.Latitude.Value)
            || (request.Longitude.HasValue
                && decimal.Round(request.Longitude.Value, 6)
                   != request.Longitude.Value))
        {
            return BadRequest(new
            {
                message = "Tọa độ tối đa 6 chữ số thập phân."
            });
        }

        // Tên bảng/cột chỉ được lấy từ danh sách cố định này.
        // Không lấy tên bảng hoặc tên cột từ dữ liệu người dùng.
        CatalogDefinition? definition = type switch
        {
            "AREAS" => new(
                "KhuVuc",
                "MaKhuVuc",
                """
                MaKhuVuc AS id,
                KyHieuKhuVuc AS code,
                TenKhuVuc AS name,
                MaKhuVucCha AS parentId,
                LoaiKhuVuc AS areaType,
                DangHoatDong AS isActive
                """,
                """
                KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha,
                LoaiKhuVuc, DangHoatDong
                """,
                "@Code, @Name, @ParentId, @AreaType, @IsActive",
                """
                TenKhuVuc = @Name,
                MaKhuVucCha = @ParentId,
                LoaiKhuVuc = @AreaType,
                DangHoatDong = @IsActive
                """
            ),

            "SERVICES" => new(
                "LoaiDichVu",
                "MaLoaiDichVu",
                """
                MaLoaiDichVu AS id,
                KyHieuDichVu AS code,
                TenDichVu AS name,
                DangHoatDong AS isActive
                """,
                "KyHieuDichVu, TenDichVu, DangHoatDong",
                "@Code, @Name, @IsActive",
                """
                TenDichVu = @Name,
                DangHoatDong = @IsActive
                """
            ),

            "BRANCHES" => new(
                "BuuCuc",
                "MaBuuCuc",
                """
                MaBuuCuc AS id,
                KyHieuBuuCuc AS code,
                TenBuuCuc AS name,
                MaKhuVuc AS areaId,
                DiaChi AS address,
                SoDienThoai AS phone,
                Email AS email,
                ViDo AS latitude,
                KinhDo AS longitude,
                DangHoatDong AS isActive
                """,
                """
                KyHieuBuuCuc, TenBuuCuc, MaKhuVuc,
                DiaChi, SoDienThoai, Email,
                ViDo, KinhDo, DangHoatDong
                """,
                """
                @Code, @Name, @AreaId,
                @Address, @Phone, @Email,
                @Latitude, @Longitude, @IsActive
                """,
                """
                TenBuuCuc = @Name,
                MaKhuVuc = @AreaId,
                DiaChi = @Address,
                SoDienThoai = @Phone,
                Email = @Email,
                ViDo = @Latitude,
                KinhDo = @Longitude,
                DangHoatDong = @IsActive
                """
            ),

            "WAREHOUSES" => new(
                "Kho",
                "MaKho",
                """
                MaKho AS id,
                KyHieuKho AS code,
                TenKho AS name,
                MaBuuCuc AS branchId,
                DiaChi AS address,
                DangHoatDong AS isActive
                """,
                """
                KyHieuKho, TenKho, MaBuuCuc,
                DiaChi, DangHoatDong
                """,
                "@Code, @Name, @BranchId, @Address, @IsActive",
                """
                TenKho = @Name,
                DiaChi = @Address,
                DangHoatDong = @IsActive
                """
            ),

            "LOCATIONS" => new(
                "ViTriLuuKho",
                "MaViTriLuuKho",
                """
                MaViTriLuuKho AS id,
                KyHieuViTri AS code,
                MaKho AS warehouseId,
                TenKhuLuu AS storageArea,
                MaKe AS rack,
                MaO AS slot,
                DangHoatDong AS isActive
                """,
                """
                KyHieuViTri, MaKho, TenKhuLuu,
                MaKe, MaO, DangHoatDong
                """,
                """
                @Code, @WarehouseId, @StorageArea,
                @Rack, @Slot, @IsActive
                """,
                """
                TenKhuLuu = @StorageArea,
                MaKe = @Rack,
                MaO = @Slot,
                DangHoatDong = @IsActive
                """
            ),

            _ => null
        };

        if (definition is null)
        {
            return BadRequest(new
            {
                message = "Type không hợp lệ."
            });
        }

        var sql = $"""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @ActorRole VARCHAR(50),
                    @ActorRoleId INT,
                    @RequiredPermission VARCHAR(100),
                    @ObjectId BIGINT = @Id,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @ActorRole = vt.KyHieuVaiTro,
                    @ActorRoleId = tk.MaVaiTro
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @ActorRole IS NULL
                    THROW 56501,
                        N'Tài khoản không còn hợp lệ.', 1;

                SET @RequiredPermission = CASE
                    WHEN @Type = 'SERVICES' THEN 'BANGGIA_QUANLY'
                    ELSE 'BUUCUC_QUANLY'
                END;

                IF @ActorRole <> 'ADMIN'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                       JOIN dbo.Quyen q WITH (HOLDLOCK)
                           ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @ActorRoleId
                         AND q.KyHieuQuyen = @RequiredPermission
                   )
                    THROW 56502,
                        N'Bạn không có quyền quản lý danh mục này.', 1;

                IF @ObjectId IS NOT NULL
                BEGIN
                    SELECT @OldJson = (
                        SELECT
                            @Type AS type,
                            {definition.Projection}
                        FROM dbo.{definition.Table}
                            WITH (UPDLOCK, HOLDLOCK)
                        WHERE {definition.IdColumn} = @ObjectId
                        FOR JSON PATH,
                            INCLUDE_NULL_VALUES,
                            WITHOUT_ARRAY_WRAPPER
                    );

                    IF NULLIF(@OldJson, N'') IS NULL
                        THROW 56503,
                            N'Không tìm thấy danh mục.', 1;

                    IF JSON_VALUE(@OldJson, '$.code')
                           COLLATE Latin1_General_100_BIN2
                       <> @Code COLLATE Latin1_General_100_BIN2
                        THROW 56504,
                            N'Không được đổi code của danh mục đã tạo.', 1;
                END;

                IF @Type = 'AREAS'
                BEGIN
                    IF @ParentId IS NOT NULL
                    BEGIN
                        IF @ParentId = @ObjectId
                            THROW 56504,
                                N'Khu vực không được là cha của chính nó.', 1;

                        IF NOT EXISTS (
                            SELECT 1
                            FROM dbo.KhuVuc WITH (UPDLOCK, HOLDLOCK)
                            WHERE MaKhuVuc = @ParentId
                              AND (
                                  @IsActive = 0
                                  OR DangHoatDong = 1
                              )
                        )
                            THROW 56505,
                                N'Khu vực cha không tồn tại hoặc không hoạt động.', 1;

                        DECLARE @AncestorId INT = @ParentId;
                        DECLARE @NextAncestorId INT;

                        DECLARE @Visited TABLE (
                            AreaId INT NOT NULL PRIMARY KEY
                        );

                        WHILE @AncestorId IS NOT NULL
                        BEGIN
                            IF @AncestorId = @ObjectId
                               OR EXISTS (
                                   SELECT 1
                                   FROM @Visited
                                   WHERE AreaId = @AncestorId
                               )
                                THROW 56504,
                                    N'Quan hệ khu vực cha tạo thành vòng lặp.', 1;

                            INSERT INTO @Visited (AreaId)
                            VALUES (@AncestorId);

                            SET @NextAncestorId = NULL;

                            SELECT @NextAncestorId = MaKhuVucCha
                            FROM dbo.KhuVuc WITH (UPDLOCK, HOLDLOCK)
                            WHERE MaKhuVuc = @AncestorId;

                            SET @AncestorId = @NextAncestorId;
                        END;
                    END;

                    IF @ObjectId IS NOT NULL AND @IsActive = 0
                    BEGIN
                        IF EXISTS (
                            SELECT 1
                            FROM dbo.KhuVuc WITH (UPDLOCK, HOLDLOCK)
                            WHERE MaKhuVucCha = @ObjectId
                              AND DangHoatDong = 1
                        )
                           OR EXISTS (
                               SELECT 1
                               FROM dbo.BuuCuc WITH (UPDLOCK, HOLDLOCK)
                               WHERE MaKhuVuc = @ObjectId
                                 AND DangHoatDong = 1
                           )
                            THROW 56504,
                                N'Khu vực còn khu vực con hoặc bưu cục hoạt động.', 1;
                    END;
                END;

                IF @Type = 'SERVICES'
                   AND @ObjectId IS NOT NULL
                   AND @IsActive = 0
                   AND EXISTS (
                       SELECT 1
                       FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                       JOIN dbo.TrangThaiDonHang tt
                           ON tt.MaTrangThaiDonHang =
                              d.MaTrangThaiHienTai
                       WHERE d.MaLoaiDichVu = @ObjectId
                         AND tt.KyHieuTrangThai NOT IN (
                             'DELIVERED', 'RETURNED',
                             'COMPLETED', 'CANCELLED'
                         )
                   )
                    THROW 56504,
                        N'Dịch vụ còn đơn hàng chưa xử lý xong.', 1;

                IF @Type = 'BRANCHES'
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.KhuVuc WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaKhuVuc = @AreaId
                          AND (
                              @IsActive = 0
                              OR DangHoatDong = 1
                          )
                    )
                        THROW 56505,
                            N'Khu vực không tồn tại hoặc không hoạt động.', 1;

                    IF @ObjectId IS NOT NULL AND @IsActive = 0
                    BEGIN
                        IF EXISTS (
                            SELECT 1
                            FROM dbo.TaiKhoan WITH (UPDLOCK, HOLDLOCK)
                            WHERE MaBuuCuc = @ObjectId
                              AND TrangThaiTaiKhoan IN (
                                  'ACTIVE', 'LOCKED'
                              )
                        )
                           OR EXISTS (
                               SELECT 1
                               FROM dbo.Kho WITH (UPDLOCK, HOLDLOCK)
                               WHERE MaBuuCuc = @ObjectId
                                 AND DangHoatDong = 1
                           )
                           OR EXISTS (
                               SELECT 1
                               FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                               JOIN dbo.TrangThaiDonHang tt
                                   ON tt.MaTrangThaiDonHang =
                                      d.MaTrangThaiHienTai
                               WHERE d.MaBuuCuc = @ObjectId
                                 AND tt.KyHieuTrangThai NOT IN (
                                     'DELIVERED', 'RETURNED',
                                     'COMPLETED', 'CANCELLED'
                                 )
                           )
                           OR EXISTS (
                               SELECT 1
                               FROM dbo.ChuyenGiaoHang
                                   WITH (UPDLOCK, HOLDLOCK)
                               WHERE MaBuuCuc = @ObjectId
                                 AND TrangThaiChuyen NOT IN (
                                     'COMPLETED', 'CANCELLED'
                                 )
                           )
                            THROW 56504,
                                N'Bưu cục còn tài khoản, kho hoặc công việc hoạt động.', 1;
                    END;
                END;

                IF @Type = 'WAREHOUSES'
                BEGIN
                    IF @ObjectId IS NOT NULL
                       AND CONVERT(
                           INT, JSON_VALUE(@OldJson, '$.branchId')
                       ) <> @BranchId
                        THROW 56504,
                            N'Không được đổi bưu cục của kho đã tạo.', 1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.BuuCuc WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaBuuCuc = @BranchId
                          AND (
                              @IsActive = 0
                              OR DangHoatDong = 1
                          )
                    )
                        THROW 56505,
                            N'Bưu cục không tồn tại hoặc không hoạt động.', 1;

                    IF @ObjectId IS NOT NULL AND @IsActive = 0
                    BEGIN
                        IF EXISTS (
                            SELECT 1
                            FROM dbo.TonKhoDonHang
                                WITH (UPDLOCK, HOLDLOCK)
                            WHERE MaKho = @ObjectId
                              AND TrangThaiTonKho IN (
                                  'RECEIVED', 'STORED',
                                  'ALLOCATED', 'RETURNED'
                              )
                        )
                           OR EXISTS (
                               SELECT 1
                               FROM dbo.ChuyenGiaoHang
                                   WITH (UPDLOCK, HOLDLOCK)
                               WHERE MaKho = @ObjectId
                                 AND TrangThaiChuyen NOT IN (
                                     'COMPLETED', 'CANCELLED'
                                 )
                           )
                            THROW 56504,
                                N'Kho còn hàng tồn hoặc chuyến giao chưa kết thúc.', 1;
                    END;
                END;

                IF @Type = 'LOCATIONS'
                BEGIN
                    IF @ObjectId IS NOT NULL
                       AND CONVERT(
                           INT, JSON_VALUE(@OldJson, '$.warehouseId')
                       ) <> @WarehouseId
                        THROW 56504,
                            N'Không được đổi kho của vị trí đã tạo.', 1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.Kho k WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.BuuCuc bc WITH (UPDLOCK, HOLDLOCK)
                            ON bc.MaBuuCuc = k.MaBuuCuc
                        WHERE k.MaKho = @WarehouseId
                          AND (
                              @IsActive = 0
                              OR (
                                  k.DangHoatDong = 1
                                  AND bc.DangHoatDong = 1
                              )
                          )
                    )
                        THROW 56505,
                            N'Kho hoặc bưu cục không tồn tại hoặc không hoạt động.', 1;

                    IF @ObjectId IS NOT NULL
                       AND @IsActive = 0
                       AND EXISTS (
                           SELECT 1
                           FROM dbo.TonKhoDonHang
                               WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaViTriLuuKho = @ObjectId
                             AND TrangThaiTonKho IN (
                                 'RECEIVED', 'STORED',
                                 'ALLOCATED', 'RETURNED'
                             )
                       )
                        THROW 56504,
                            N'Vị trí còn hàng tồn, chưa thể ngừng hoạt động.', 1;
                END;

                IF @ObjectId IS NULL
                BEGIN
                    INSERT INTO dbo.{definition.Table} (
                        {definition.InsertColumns}
                    )
                    VALUES (
                        {definition.InsertValues}
                    );

                    SET @ObjectId =
                        CONVERT(BIGINT, SCOPE_IDENTITY());
                END
                ELSE
                BEGIN
                    UPDATE dbo.{definition.Table}
                    SET {definition.UpdateColumns}
                    WHERE {definition.IdColumn} = @ObjectId;
                END;

                SELECT @Result = (
                    SELECT
                        @Type AS type,
                        {definition.Projection}
                    FROM dbo.{definition.Table}
                    WHERE {definition.IdColumn} = @ObjectId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuCuJson,
                    DuLieuMoiJson
                )
                VALUES (
                    @ActorId,
                    CASE
                        WHEN @Id IS NULL THEN 'CREATE_CATALOG'
                        ELSE 'UPDATE_CATALOG'
                    END,
                    @ObjectName,
                    CONVERT(VARCHAR(100), @ObjectId),
                    @OldJson,
                    @Result
                );

                COMMIT;
                SELECT @Result;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@Type", SqlDbType.VarChar, 20).Value = type;

        command.Parameters.Add(
            "@ObjectName", SqlDbType.VarChar, 100).Value =
            definition.Table;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
            (object?)request.Id ?? DBNull.Value;

        command.Parameters.Add(
            "@Code", SqlDbType.VarChar, 50).Value = request.Code;

        AddText(
            command, "@Name",
            SqlDbType.NVarChar, 150, name);

        command.Parameters.Add(
            "@IsActive", SqlDbType.Bit).Value =
            request.IsActive!.Value;

        command.Parameters.Add(
            "@ParentId", SqlDbType.Int).Value =
            (object?)request.ParentId ?? DBNull.Value;

        AddText(
            command, "@AreaType",
            SqlDbType.VarChar, 20, request.AreaType);

        command.Parameters.Add(
            "@AreaId", SqlDbType.Int).Value =
            (object?)request.AreaId ?? DBNull.Value;

        AddText(
            command, "@Address",
            SqlDbType.NVarChar, 300, request.Address);

        AddText(
            command, "@Phone",
            SqlDbType.VarChar, 20, request.Phone);

        AddText(
            command, "@Email",
            SqlDbType.VarChar, 150, request.Email);

        var latitudeParameter = command.Parameters.Add(
            "@Latitude", SqlDbType.Decimal);

        latitudeParameter.Precision = 9;
        latitudeParameter.Scale = 6;
        latitudeParameter.Value =
            (object?)request.Latitude ?? DBNull.Value;

        var longitudeParameter = command.Parameters.Add(
            "@Longitude", SqlDbType.Decimal);

        longitudeParameter.Precision = 10;
        longitudeParameter.Scale = 6;
        longitudeParameter.Value =
            (object?)request.Longitude ?? DBNull.Value;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
            (object?)request.BranchId ?? DBNull.Value;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value =
            (object?)request.WarehouseId ?? DBNull.Value;

        AddText(
            command, "@StorageArea",
            SqlDbType.NVarChar, 100, request.StorageArea);

        AddText(
            command, "@Rack",
            SqlDbType.VarChar, 50, request.Rack);

        AddText(
            command, "@Slot",
            SqlDbType.VarChar, 50, request.Slot);

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return new ContentResult
            {
                StatusCode = request.Id.HasValue
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = result?.ToString() ?? "{}"
            };
        }
        catch (SqlException ex) when (
            ex.Number is 56501 or 56502 or 56503 or 56504 or 56505
                or 2601 or 2627 or 547 or 1205)
        {
            return ex.Number switch
            {
                56501 => Unauthorized(new { message = ex.Message }),

                56502 => StatusCode(
                    403, new { message = ex.Message }),

                56503 => NotFound(new { message = ex.Message }),

                56504 => Conflict(new { message = ex.Message }),

                56505 => UnprocessableEntity(
                    new { message = ex.Message }),

                2601 or 2627 when type == "LOCATIONS" => Conflict(new
                {
                    message = "Mã vị trí đã tồn tại trong kho này.",
                    field = "code"
                }),

                2601 or 2627 => Conflict(new
                {
                    message = "Mã hoặc tên danh mục đã tồn tại."
                }),

                547 => Conflict(new
                {
                    message =
                        "Dữ liệu không thỏa mãn ràng buộc của database."
                }),

                _ => Conflict(new
                {
                    message =
                        "Danh mục đang được cập nhật đồng thời. Hãy thử lại."
                })
            };
        }
    }

    private static void AddText(
        SqlCommand command,
        string parameterName,
        SqlDbType dataType,
        int size,
        string? value)
    {
        command.Parameters.Add(
            parameterName, dataType, size).Value =
            string.IsNullOrWhiteSpace(value)
                ? DBNull.Value
                : value.Trim();
    }
}
