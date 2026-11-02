using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateCodReconciliationRequest
{
    [Range(1, long.MaxValue)]
    public long ShipperId { get; set; }

    [Range(1, int.MaxValue)]
    public int BranchId { get; set; }

    [Required]
    public DateTimeOffset? From { get; set; }

    [Required]
    public DateTimeOffset? To { get; set; }

    [StringLength(1000)]
    public string? Notes { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/cod/reconciliations")]
public class CodReconciliationsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CodReconciliationsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateCodReconciliationRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        static DateTime ToWholeUtcSecond(DateTimeOffset value)
        {
            var utc = value.UtcDateTime;
            return new DateTime(
                utc.Ticks - utc.Ticks % TimeSpan.TicksPerSecond,
                DateTimeKind.Utc);
        }

        var fromUtc = ToWholeUtcSecond(request.From!.Value);
        var toUtc = ToWholeUtcSecond(request.To!.Value);

        if (CodQuerySupport.DateError(request.From,request.To) is string dateError)
        {
            return BadRequest(new
            {
                message = dateError
            });
        }

        var notes = string.IsNullOrWhiteSpace(request.Notes)
            ? null
            : request.Notes.Trim();

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Now DATETIME2(0) = SYSUTCDATETIME(),
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranchId INT,
                    @ShipperBranchId INT,
                    @ReconciliationId BIGINT,
                    @Code VARCHAR(40),
                    @Expected DECIMAL(18,2),
                    @Collected DECIMAL(18,2),
                    @Deposited DECIMAL(18,2),
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro,
                    @AccountBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk
                INNER JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= @Now
                  );

                IF @Role IS NULL
                    THROW 53301,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF @Role = 'SHIPPER'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vtq
                       INNER JOIN dbo.Quyen q
                           ON q.MaQuyen = vtq.MaQuyen
                       WHERE vtq.MaVaiTro = @RoleId
                         AND q.KyHieuQuyen = 'COD_DOISOAT'
                   )
                    THROW 53302,
                        N'Bạn không có quyền tạo đối soát COD.',
                        1;

                IF @Role <> 'ADMIN'
                   AND (
                       @AccountBranchId IS NULL
                       OR @AccountBranchId <> @BranchId
                   )
                    THROW 53302,
                        N'Bạn chỉ được đối soát bưu cục của mình.',
                        1;

                -- Khóa shipper để tránh tạo đồng thời hai
                -- phiên chồng lấn cho cùng người.
                SELECT @ShipperBranchId = tk.MaBuuCuc
                FROM dbo.NhanVienGiaoHang nv
                    WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = nv.MaTaiKhoan
                INNER JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE nv.MaNhanVienGiaoHang = @ShipperId
                  AND nv.DangHoatDong = 1
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.KyHieuVaiTro = 'SHIPPER'
                  AND vt.DangHoatDong = 1;

                IF @ShipperBranchId IS NULL
                   OR @ShipperBranchId <> @BranchId
                    THROW 53304,
                        N'Shipper không hoạt động hoặc không thuộc bưu cục này.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc
                    WHERE MaBuuCuc = @BranchId
                      AND DangHoatDong = 1
                )
                    THROW 53304,
                        N'Bưu cục không còn hoạt động.',
                        1;

                SELECT
                    c.MaDonHang AS orderId,
                    c.SoTienPhaiThu AS expectedAmount,
                    c.SoTienThucThu AS collectedAmount,
                    COALESCE(paid.depositedAmount, 0)
                        AS depositedAmount
                INTO #ReconItems
                FROM dbo.ThuTienCOD c WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = c.MaDonHang
                OUTER APPLY (
                    SELECT SUM(ct.SoTienPhanBo) AS depositedAmount
                    FROM dbo.ChiTietNopTienCOD ct
                    INNER JOIN dbo.NopTienCOD n
                        ON n.MaNopTienCOD = ct.MaNopTienCOD
                    WHERE ct.MaDonHang = c.MaDonHang
                      AND n.MaNhanVienGiaoHang = @ShipperId
                      AND n.MaBuuCuc = @BranchId
                      AND n.TrangThaiNop = 'CONFIRMED'
                ) paid
                WHERE c.MaNhanVienGiaoHang = @ShipperId
                  AND d.MaBuuCuc = @BranchId
                  AND c.TrangThaiThuTien IN (
                      'COLLECTED', 'PARTIAL'
                  )
                  AND c.ThoiGianThuTien >= @From
                  AND c.ThoiGianThuTien < @To;

                IF NOT EXISTS (SELECT 1 FROM #ReconItems)
                    THROW 53305,
                        N'Không có khoản COD phù hợp trong kỳ đã chọn.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM #ReconItems x
                    INNER JOIN dbo.ChiTietDoiSoatCOD ct
                        ON ct.MaDonHang = x.orderId
                    INNER JOIN dbo.DoiSoatCOD ds
                        ON ds.MaDoiSoatCOD = ct.MaDoiSoatCOD
                    WHERE ds.TrangThaiDoiSoat <> 'CANCELLED'
                )
                    THROW 53304,
                        N'Có đơn COD đã thuộc phiên đối soát khác chưa hủy.',
                        1;

                SELECT
                    @Expected = SUM(expectedAmount),
                    @Collected = SUM(collectedAmount),
                    @Deposited = SUM(depositedAmount)
                FROM #ReconItems;

                SET @Code =
                    'DS-' + REPLACE(
                        CONVERT(VARCHAR(36), NEWID()), '-', ''
                    );

                INSERT INTO dbo.DoiSoatCOD (
                    KyHieuDoiSoat,
                    MaBuuCuc,
                    MaNhanVienGiaoHang,
                    TuThoiGian,
                    DenThoiGian,
                    TongTienPhaiThu,
                    TongTienDaThu,
                    TongTienDaNop,
                    TrangThaiDoiSoat,
                    GhiChu
                )
                VALUES (
                    @Code,
                    @BranchId,
                    @ShipperId,
                    @From,
                    @To,
                    @Expected,
                    @Collected,
                    @Deposited,
                    'DRAFT',
                    @Notes
                );

                SET @ReconciliationId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietDoiSoatCOD (
                    MaDoiSoatCOD,
                    MaDonHang,
                    SoTienPhaiThu,
                    SoTienDaThu,
                    SoTienDaNop,
                    TrangThaiKetQua
                )
                SELECT
                    @ReconciliationId,
                    orderId,
                    expectedAmount,
                    collectedAmount,
                    depositedAmount,
                    CASE
                        WHEN depositedAmount = collectedAmount
                            THEN 'MATCHED'
                        WHEN depositedAmount < collectedAmount
                            THEN 'SHORT'
                        ELSE 'OVER'
                    END
                FROM #ReconItems;

                SET @Result = (
                    SELECT
                        @ReconciliationId AS id,
                        @Code AS reconciliationCode,
                        @BranchId AS branchId,
                        @ShipperId AS shipperId,
                        @From AS [from],
                        @To AS [to],
                        @Expected AS totalExpected,
                        @Collected AS totalCollected,
                        @Deposited AS totalDeposited,
                        @Deposited - @Expected AS difference,
                        'DRAFT' AS status,
                        (
                            SELECT COUNT_BIG(*)
                            FROM #ReconItems
                        ) AS orderCount,
                        N'Đã tạo phiên đối soát nháp.'
                            AS message
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'CREATE_COD_RECONCILIATION',
                    'DoiSoatCOD',
                    CONVERT(VARCHAR(100), @ReconciliationId),
                    @Result
                );

                DROP TABLE #ReconItems;

                COMMIT;

                SELECT @Result;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

                THROW;
            END CATCH;
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                request.ShipperId;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                request.BranchId;

        var fromParameter = command.Parameters.Add(
            "@From", SqlDbType.DateTime2);
        fromParameter.Scale = 0;
        fromParameter.Value = fromUtc;

        var toParameter = command.Parameters.Add(
            "@To", SqlDbType.DateTime2);
        toParameter.Scale = 0;
        toParameter.Value = toUtc;

        command.Parameters.Add(
            "@Notes", SqlDbType.NVarChar, 1000).Value =
                (object?)notes ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = json
            };
        }
        catch (SqlException ex) when (
            ex.Number is >= 53301 and <= 53305)
        {
            var statusCode = ex.Number switch
            {
                53301 => StatusCodes.Status401Unauthorized,
                53302 => StatusCodes.Status403Forbidden,
                53305 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại dữ liệu COD và thử lại."
            });
        }
    }
    [HttpPost("{id:long}/confirm")]
    public async Task<IActionResult> Confirm(long id)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã phiên đối soát không hợp lệ."
            });
        }

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
        SET NOCOUNT ON;
        SET XACT_ABORT ON;

        BEGIN TRY
            BEGIN TRAN;

            DECLARE
                @Now DATETIME2(0) = SYSUTCDATETIME(),
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @ReconciliationBranchId INT,
                @CurrentStatus VARCHAR(20),
                @OldJson NVARCHAR(MAX),
                @Result NVARCHAR(MAX);

            SELECT
                @Role = vt.KyHieuVaiTro,
                @RoleId = tk.MaVaiTro,
                @AccountBranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= @Now
              );

            IF @Role IS NULL
                THROW 53401,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF @Role = 'SHIPPER'
               OR NOT EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vtq
                   INNER JOIN dbo.Quyen q
                       ON q.MaQuyen = vtq.MaQuyen
                   WHERE vtq.MaVaiTro = @RoleId
                     AND q.KyHieuQuyen = 'COD_DOISOAT'
               )
                THROW 53402,
                    N'Bạn không có quyền xác nhận đối soát COD.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 53402,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            SELECT
                @ReconciliationBranchId = ds.MaBuuCuc,
                @CurrentStatus = ds.TrangThaiDoiSoat
            FROM dbo.DoiSoatCOD ds WITH (UPDLOCK, HOLDLOCK)
            WHERE ds.MaDoiSoatCOD = @ReconciliationId
              AND (
                  @Role = 'ADMIN'
                  OR ds.MaBuuCuc = @AccountBranchId
              );

            IF @ReconciliationBranchId IS NULL
                THROW 53403,
                    N'Không tìm thấy phiên đối soát COD.',
                    1;

            IF @CurrentStatus NOT IN (
                'DRAFT', 'REVIEW', 'DIFFERENCE'
            )
                THROW 53404,
                    N'Trạng thái hiện tại không cho phép xác nhận đối soát.',
                    1;

            SET @OldJson = (
                SELECT
                    ds.MaDoiSoatCOD AS id,
                    ds.TrangThaiDoiSoat AS status,
                    ds.TongTienPhaiThu AS totalExpected,
                    ds.TongTienDaThu AS totalCollected,
                    ds.TongTienDaNop AS totalDeposited
                FROM dbo.DoiSoatCOD ds
                WHERE ds.MaDoiSoatCOD = @ReconciliationId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            -- Procedure tính lại chi tiết và tổng tiền
            -- dựa trên các khoản COD/nộp tiền hiện tại.
            EXEC dbo.sp_XacNhanDoiSoatCOD
                @MaDoiSoatCOD = @ReconciliationId,
                @MaTaiKhoanXacNhan = @AccountId;

            SET @Result = (
                SELECT
                    ds.MaDoiSoatCOD AS id,
                    ds.KyHieuDoiSoat AS reconciliationCode,
                    ds.MaBuuCuc AS branchId,
                    b.TenBuuCuc AS branchName,
                    ds.MaNhanVienGiaoHang AS shipperId,
                    tk.HoTen AS shipperName,
                    ds.TuThoiGian AS [from],
                    ds.DenThoiGian AS [to],
                    ds.TongTienPhaiThu AS totalExpected,
                    ds.TongTienDaThu AS totalCollected,
                    ds.TongTienDaNop AS totalDeposited,
                    ds.SoTienChenhLech AS difference,
                    ds.TrangThaiDoiSoat AS status,
                    ds.MaTaiKhoanXacNhan AS confirmedBy,
                    ds.ThoiGianXacNhan AS confirmedAt,
                    (
                        SELECT COUNT_BIG(*)
                        FROM dbo.ChiTietDoiSoatCOD ct
                        WHERE ct.MaDoiSoatCOD =
                              ds.MaDoiSoatCOD
                    ) AS orderCount,
                    (
                        SELECT COUNT_BIG(*)
                        FROM dbo.ChiTietDoiSoatCOD ct
                        WHERE ct.MaDoiSoatCOD =
                              ds.MaDoiSoatCOD
                          AND ct.TrangThaiKetQua <> 'MATCHED'
                    ) AS unmatchedOrderCount,
                    CASE
                        WHEN ds.TrangThaiDoiSoat = 'CONFIRMED'
                        THEN N'Đối soát khớp và đã được xác nhận.'
                        ELSE N'Đã tính lại đối soát; có chênh lệch cần xử lý.'
                    END AS message
                FROM dbo.DoiSoatCOD ds
                INNER JOIN dbo.BuuCuc b
                    ON b.MaBuuCuc = ds.MaBuuCuc
                INNER JOIN dbo.NhanVienGiaoHang nv
                    ON nv.MaNhanVienGiaoHang =
                       ds.MaNhanVienGiaoHang
                INNER JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = nv.MaTaiKhoan
                WHERE ds.MaDoiSoatCOD = @ReconciliationId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
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
                @AccountId,
                'CONFIRM_COD_RECONCILIATION',
                'DoiSoatCOD',
                CONVERT(VARCHAR(100), @ReconciliationId),
                @OldJson,
                @Result
            );

            COMMIT;

            SELECT @Result;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK;

            THROW;
        END CATCH;
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@ReconciliationId", SqlDbType.BigInt).Value = id;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            (ex.Number is >= 53401 and <= 53404)
            || (ex.Number is >= 51180 and <= 51184))
        {
            var statusCode = ex.Number switch
            {
                53401 => StatusCodes.Status401Unauthorized,
                53402 => StatusCodes.Status403Forbidden,
                53403 or 51180 => StatusCodes.Status404NotFound,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại đối soát và thử lại."
            });
        }
    }

    [HttpGet]
    public async Task<IActionResult> GetReconciliations(
    [FromQuery, Range(1, long.MaxValue)] long? id = null,
    [FromQuery, StringLength(100)] string? keyword = null,
    [FromQuery, StringLength(20)] string? status = null,
    [FromQuery, Range(1, long.MaxValue)] long? shipperId = null,
    [FromQuery, Range(1, int.MaxValue)] int? branchId = null,
    [FromQuery, Range(1, 100000)] int page = 1,
    [FromQuery, Range(1, 100)] int pageSize = 10,
    [FromQuery] DateTimeOffset? from = null,
    [FromQuery] DateTimeOffset? to = null,
    [FromQuery] bool export = false)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null
            : keyword.Trim();

        status = string.IsNullOrWhiteSpace(status)
            ? null
            : status.Trim().ToUpperInvariant();

        string[] allowedStatuses =
        [
            "DRAFT",
        "REVIEW",
        "CONFIRMED",
        "DIFFERENCE",
        "LOCKED",
        "CANCELLED"
        ];

        if (CodQuerySupport.DateError(from,to) is string dateError) return BadRequest(new {message=dateError});

        if (status is not null && !allowedStatuses.Contains(status))
        {
            return BadRequest(new
            {
                message = "Trạng thái đối soát không hợp lệ.",
                allowedStatuses
            });
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
        SET NOCOUNT ON;

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Role VARCHAR(50),
            @RoleId INT,
            @AccountBranchId INT;

        SELECT
            @Role = vt.KyHieuVaiTro,
            @RoleId = tk.MaVaiTro,
            @AccountBranchId = tk.MaBuuCuc
        FROM dbo.TaiKhoan tk
        INNER JOIN dbo.VaiTro vt
            ON vt.MaVaiTro = tk.MaVaiTro
        WHERE tk.MaTaiKhoan = @AccountId
          AND tk.TrangThaiTaiKhoan = 'ACTIVE'
          AND vt.DangHoatDong = 1
          AND (
              tk.KhoaDenLuc IS NULL
              OR tk.KhoaDenLuc <= @Now
          );

        IF @Role IS NULL
            THROW 53501,
                N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                1;

        IF @Role = 'SHIPPER'
           OR NOT EXISTS (
               SELECT 1
               FROM dbo.VaiTroQuyen vtq
               INNER JOIN dbo.Quyen q
                   ON q.MaQuyen = vtq.MaQuyen
               WHERE vtq.MaVaiTro = @RoleId
                 AND q.KyHieuQuyen = 'COD_DOISOAT'
           )
            THROW 53502,
                N'Bạn không có quyền xem đối soát COD.',
                1;

        IF @Role <> 'ADMIN'
           AND @AccountBranchId IS NULL
            THROW 53502,
                N'Tài khoản chưa được gán bưu cục.',
                1;

        IF @Id IS NULL
           AND @Role <> 'ADMIN'
           AND @BranchId IS NOT NULL
           AND @BranchId <> @AccountBranchId
            THROW 53502,
                N'Bạn chỉ được xem đối soát thuộc bưu cục của mình.',
                1;

        SELECT
            ds.MaDoiSoatCOD AS id,
            ds.KyHieuDoiSoat AS reconciliationCode,
            ds.MaBuuCuc AS branchId,
            b.TenBuuCuc AS branchName,
            ds.MaNhanVienGiaoHang AS shipperId,
            nv.MaNhanVien AS employeeCode,
            shipper.HoTen AS shipperName,
            ds.TuThoiGian AS periodFrom,
            ds.DenThoiGian AS periodTo,
            ds.TongTienPhaiThu AS totalExpected,
            ds.TongTienDaThu AS totalCollected,
            ds.TongTienDaNop AS totalDeposited,
            ds.SoTienChenhLech AS difference,
            ds.TongTienDaThu - ds.TongTienPhaiThu
                AS collectionDifference,
            ds.TongTienDaNop - ds.TongTienDaThu
                AS depositDifference,
            ds.TrangThaiDoiSoat AS status,
            ds.MaTaiKhoanXacNhan AS confirmedBy,
            confirmer.HoTen AS confirmedByName,
            ds.ThoiGianXacNhan AS confirmedAt,
            ds.ThoiGianKhoa AS lockedAt,
            ds.GhiChu AS notes,
            (
                SELECT COUNT_BIG(*)
                FROM dbo.ChiTietDoiSoatCOD ct
                WHERE ct.MaDoiSoatCOD = ds.MaDoiSoatCOD
            ) AS orderCount
        INTO #Reconciliations
        FROM dbo.DoiSoatCOD ds
        INNER JOIN dbo.BuuCuc b
            ON b.MaBuuCuc = ds.MaBuuCuc
        INNER JOIN dbo.NhanVienGiaoHang nv
            ON nv.MaNhanVienGiaoHang =
               ds.MaNhanVienGiaoHang
        INNER JOIN dbo.TaiKhoan shipper
            ON shipper.MaTaiKhoan = nv.MaTaiKhoan
        LEFT JOIN dbo.TaiKhoan confirmer
            ON confirmer.MaTaiKhoan =
               ds.MaTaiKhoanXacNhan
        WHERE (
            @Role = 'ADMIN'
            OR ds.MaBuuCuc = @AccountBranchId
        )
          AND (
              @Id IS NULL
              OR ds.MaDoiSoatCOD = @Id
          )
          AND (
              @Id IS NOT NULL
              OR (
                  (
                      @BranchId IS NULL
                      OR ds.MaBuuCuc = @BranchId
                  )
                  AND (
                      @ShipperId IS NULL
                      OR ds.MaNhanVienGiaoHang = @ShipperId
                  )
                  AND (
                      @Status IS NULL
                      OR ds.TrangThaiDoiSoat = @Status
                  )
                  AND (
                      @Keyword IS NULL
                      OR CHARINDEX(
                          @Keyword, ds.KyHieuDoiSoat
                      ) > 0
                      OR CHARINDEX(
                          @Keyword, shipper.HoTen
                      ) > 0
                      OR CHARINDEX(
                          @Keyword, nv.MaNhanVien
                      ) > 0
                  )
                  AND (@From IS NULL OR ds.DenThoiGian>@From)
                  AND (@To IS NULL OR ds.TuThoiGian<@To)
              )
          );

        IF @Id IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM #Reconciliations)
                THROW 53503,
                    N'Không tìm thấy phiên đối soát COD.',
                    1;

            SELECT (
                SELECT
                    r.*,
                    JSON_QUERY((
                        SELECT
                            ct.MaDonHang AS orderId,
                            d.KyHieuDonHang AS orderCode,
                            d.MaVanDon AS trackingNumber,
                            ct.SoTienPhaiThu AS expectedAmount,
                            ct.SoTienDaThu AS collectedAmount,
                            ct.SoTienDaNop AS depositedAmount,
                            ct.SoTienChenhLech AS difference,
                            ct.SoTienDaThu - ct.SoTienPhaiThu
                                AS collectionDifference,
                            ct.SoTienDaNop - ct.SoTienDaThu
                                AS depositDifference,
                            ct.TrangThaiKetQua AS resultStatus,
                            ct.GhiChuXuLy AS handlingNotes
                        FROM dbo.ChiTietDoiSoatCOD ct
                        INNER JOIN dbo.DonHang d
                            ON d.MaDonHang = ct.MaDonHang
                        WHERE ct.MaDoiSoatCOD = r.id
                        ORDER BY ct.MaDonHang
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    )) AS items
                FROM #Reconciliations r
                FOR JSON PATH,
                    INCLUDE_NULL_VALUES,
                    WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE
        BEGIN
            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*)
                        FROM #Reconciliations
                    ) AS totalItems,
                    JSON_QUERY((SELECT COALESCE(SUM(totalExpected),0) AS totalExpected,
                        COALESCE(SUM(totalCollected),0) AS totalCollected,COALESCE(SUM(totalDeposited),0) AS totalDeposited
                        FROM #Reconciliations FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) AS summary,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM #Reconciliations
                        ORDER BY id DESC
                        OFFSET @Offset ROWS
                        FETCH NEXT @Fetch ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ),N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END;

        DROP TABLE #Reconciliations;
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add("@From",SqlDbType.DateTime2).Value=(object?)from?.UtcDateTime??DBNull.Value;
        command.Parameters.Add("@To",SqlDbType.DateTime2).Value=(object?)to?.UtcDateTime??DBNull.Value;
        command.Parameters.Add("@Fetch",SqlDbType.Int).Value=export?int.MaxValue:pageSize;

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
                (object?)id ?? DBNull.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 20).Value =
                (object?)status ?? DBNull.Value;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                (object?)shipperId ?? DBNull.Value;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.Int).Value =
                export?0:(page - 1) * pageSize;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 53501 and <= 53503)
        {
            var statusCode = ex.Number switch
            {
                53501 => StatusCodes.Status401Unauthorized,
                53502 => StatusCodes.Status403Forbidden,
                _ => StatusCodes.Status404NotFound
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
    }
}
