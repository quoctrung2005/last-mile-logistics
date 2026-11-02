using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateCodDepositRequest
{
    [Range(1, long.MaxValue)]
    public long ShipperId { get; set; }

    [Range(1, int.MaxValue)]
    public int BranchId { get; set; }

    [Required]
    [StringLength(20)]
    public string Method { get; set; } = "CASH";

    [StringLength(100)]
    public string? ExternalReference { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    [Required]
    [MinLength(1)]
    [MaxLength(100)]
    public List<CodDepositItemRequest> Items { get; set; } = [];
}

public class CodDepositItemRequest
{
    [Range(1, long.MaxValue)]
    public long OrderId { get; set; }

    [Range(
        typeof(decimal), "0.01", "9999999999999999.99",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal Amount { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/cod/deposits")]
public class CodDepositsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CodDepositsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateCodDepositRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var method = request.Method.Trim().ToUpperInvariant();

        if (method is not ("CASH" or "BANK_TRANSFER" or "OTHER"))
        {
            return BadRequest(new
            {
                message = "Method chỉ nhận CASH, BANK_TRANSFER hoặc OTHER."
            });
        }

        var reference = string.IsNullOrWhiteSpace(
            request.ExternalReference)
            ? null
            : request.ExternalReference.Trim();

        var notes = string.IsNullOrWhiteSpace(request.Notes)
            ? null
            : request.Notes.Trim();

        if (method == "BANK_TRANSFER" && reference is null)
        {
            return BadRequest(new
            {
                message = "Nộp chuyển khoản phải có mã tham chiếu giao dịch."
            });
        }

        if (request.Items.Select(x => x.OrderId).Distinct().Count()
            != request.Items.Count)
        {
            return BadRequest(new
            {
                message = "Một đơn chỉ được xuất hiện một lần trong phiếu."
            });
        }

        if (request.Items.Any(
            x => decimal.Round(x.Amount, 2) != x.Amount))
        {
            return BadRequest(new
            {
                message = "Số tiền chỉ được có tối đa 2 chữ số thập phân."
            });
        }

        var totalAmount = request.Items.Sum(x => x.Amount);

        if (totalAmount > 9999999999999999.99m)
        {
            return BadRequest(new
            {
                message = "Tổng tiền vượt giới hạn lưu trữ của phiếu."
            });
        }

        var itemsJson = JsonSerializer.Serialize(
            request.Items,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

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
                    @OwnShipperId BIGINT,
                    @SelectedShipperBranchId INT,
                    @DepositId BIGINT,
                    @DepositCode VARCHAR(40),
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
                    THROW 53001,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'COD_NOPTIEN'
                )
                    THROW 53002,
                        N'Bạn không có quyền tạo phiếu nộp COD.',
                        1;

                IF @Role = 'SHIPPER'
                BEGIN
                    SELECT @OwnShipperId = MaNhanVienGiaoHang
                    FROM dbo.NhanVienGiaoHang
                    WHERE MaTaiKhoan = @AccountId
                      AND DangHoatDong = 1;

                    IF @OwnShipperId IS NULL
                       OR @OwnShipperId <> @ShipperId
                        THROW 53002,
                            N'Bạn chỉ được tạo phiếu nộp COD của mình.',
                            1;
                END;

                IF @Role <> 'ADMIN'
                   AND (
                       @AccountBranchId IS NULL
                       OR @AccountBranchId <> @BranchId
                   )
                    THROW 53002,
                        N'Bạn chỉ được tạo phiếu trong bưu cục của mình.',
                        1;

                -- Khóa shipper để các lần lập phiếu của cùng
                -- một người lần lượt kiểm tra phần tiền còn lại.
                SELECT @SelectedShipperBranchId = tk.MaBuuCuc
                FROM dbo.NhanVienGiaoHang nv
                    WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = nv.MaTaiKhoan
                INNER JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE nv.MaNhanVienGiaoHang = @ShipperId
                  AND nv.DangHoatDong = 1
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= @Now
                  )
                  AND vt.KyHieuVaiTro = 'SHIPPER'
                  AND vt.DangHoatDong = 1;

                IF @SelectedShipperBranchId IS NULL
                   OR @SelectedShipperBranchId <> @BranchId
                    THROW 53004,
                        N'Shipper không hoạt động hoặc không thuộc bưu cục của phiếu.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc
                    WHERE MaBuuCuc = @BranchId
                      AND DangHoatDong = 1
                )
                    THROW 53004,
                        N'Bưu cục không còn hoạt động.',
                        1;

                CREATE TABLE #DepositItems (
                    orderId BIGINT NOT NULL PRIMARY KEY,
                    amount DECIMAL(18,2) NOT NULL
                );

                INSERT INTO #DepositItems (orderId, amount)
                SELECT orderId, amount
                FROM OPENJSON(@ItemsJson)
                WITH (
                    orderId BIGINT '$.orderId',
                    amount DECIMAL(18,2) '$.amount'
                );

                -- Khóa các khoản thu để kiểm tra và giữ
                -- phần tiền phân bổ trong cùng giao dịch.
                SELECT
                    c.MaDonHang AS orderId,
                    c.SoTienThucThu AS collectedAmount
                INTO #CollectedAmounts
                FROM dbo.ThuTienCOD c WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN #DepositItems x
                    ON x.orderId = c.MaDonHang
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = c.MaDonHang
                WHERE c.MaNhanVienGiaoHang = @ShipperId
                  AND c.TrangThaiThuTien IN ('COLLECTED', 'PARTIAL')
                  AND d.MaBuuCuc = @BranchId;

                IF EXISTS (
                    SELECT 1
                    FROM #DepositItems x
                    LEFT JOIN #CollectedAmounts c
                        ON c.orderId = x.orderId
                    WHERE c.orderId IS NULL
                )
                    THROW 53004,
                        N'Có đơn không thuộc COD đã thu của shipper hoặc không cùng bưu cục.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM #DepositItems x
                    INNER JOIN #CollectedAmounts c
                        ON c.orderId = x.orderId
                    OUTER APPLY (
                        SELECT COALESCE(SUM(ct.SoTienPhanBo), 0)
                            AS allocatedAmount
                        FROM dbo.ChiTietNopTienCOD ct
                        INNER JOIN dbo.NopTienCOD n
                            ON n.MaNopTienCOD = ct.MaNopTienCOD
                        WHERE ct.MaDonHang = x.orderId
                          AND n.TrangThaiNop IN (
                              'PENDING', 'CONFIRMED'
                          )
                    ) allocated
                    WHERE x.amount >
                        c.collectedAmount - allocated.allocatedAmount
                )
                    THROW 53004,
                        N'Số tiền phân bổ vượt phần còn có thể nộp. Hãy tải lại danh sách COD.',
                        1;

                SET @Now = SYSUTCDATETIME();

                SET @DepositCode =
                    'NC-' + REPLACE(
                        CONVERT(VARCHAR(36), NEWID()), '-', ''
                    );

                INSERT INTO dbo.NopTienCOD (
                    KyHieuNopTien,
                    MaNhanVienGiaoHang,
                    MaBuuCuc,
                    SoTienNop,
                    PhuongThucNop,
                    TrangThaiNop,
                    ThoiGianNop,
                    MaThamChieuNgoai,
                    GhiChu
                )
                VALUES (
                    @DepositCode,
                    @ShipperId,
                    @BranchId,
                    @TotalAmount,
                    @Method,
                    'PENDING',
                    @Now,
                    @ExternalReference,
                    @Notes
                );

                SET @DepositId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietNopTienCOD (
                    MaNopTienCOD, MaDonHang, SoTienPhanBo
                )
                SELECT @DepositId, orderId, amount
                FROM #DepositItems;

                SET @Result = (
                    SELECT
                        @DepositId AS id,
                        @DepositCode AS depositCode,
                        @ShipperId AS shipperId,
                        @BranchId AS branchId,
                        @TotalAmount AS amount,
                        @Method AS method,
                        'PENDING' AS status,
                        @ExternalReference AS externalReference,
                        @Now AS submittedAt,
                        JSON_QUERY((
                            SELECT orderId, amount
                            FROM #DepositItems
                            ORDER BY orderId
                            FOR JSON PATH
                        )) AS items,
                        N'Đã tạo phiếu nộp COD, chờ xác nhận.'
                            AS message
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
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
                    'CREATE_COD_DEPOSIT',
                    'NopTienCOD',
                    CONVERT(VARCHAR(100), @DepositId),
                    @Result
                );

                DROP TABLE #CollectedAmounts;
                DROP TABLE #DepositItems;

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
            "@ShipperId", SqlDbType.BigInt).Value = request.ShipperId;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value = request.BranchId;

        command.Parameters.Add(
            "@Method", SqlDbType.VarChar, 20).Value = method;

        command.Parameters.Add(
            "@ExternalReference", SqlDbType.VarChar, 100).Value =
                (object?)reference ?? DBNull.Value;

        command.Parameters.Add(
            "@Notes", SqlDbType.NVarChar, 500).Value =
                (object?)notes ?? DBNull.Value;

        command.Parameters.Add(
            "@ItemsJson", SqlDbType.NVarChar, -1).Value = itemsJson;

        var amountParameter = command.Parameters.Add(
            "@TotalAmount", SqlDbType.Decimal);
        amountParameter.Precision = 18;
        amountParameter.Scale = 2;
        amountParameter.Value = totalAmount;

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
            ex.Number is 53001 or 53002 or 53004)
        {
            var statusCode = ex.Number switch
            {
                53001 => StatusCodes.Status401Unauthorized,
                53002 => StatusCodes.Status403Forbidden,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message =
                    "Mã tham chiếu đã được sử dụng hoặc dữ liệu phiếu bị trùng. Hãy kiểm tra lại."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại danh sách COD và thử lại."
            });
        }
    }
    private const string DepositReadScopeSql = """
    SET NOCOUNT ON;

    DECLARE
        @Now DATETIME2(0) = SYSUTCDATETIME(),
        @Role VARCHAR(50),
        @RoleId INT,
        @AccountBranchId INT,
        @OwnShipperId BIGINT;

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
        THROW 53101,
            N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
            1;

    IF @Role = 'SHIPPER'
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.VaiTroQuyen vtq
            INNER JOIN dbo.Quyen q
                ON q.MaQuyen = vtq.MaQuyen
            WHERE vtq.MaVaiTro = @RoleId
              AND q.KyHieuQuyen = 'COD_NOPTIEN'
        )
            THROW 53102,
                N'Bạn không có quyền xem phiếu nộp COD.',
                1;

        SELECT @OwnShipperId = MaNhanVienGiaoHang
        FROM dbo.NhanVienGiaoHang
        WHERE MaTaiKhoan = @AccountId
          AND DangHoatDong = 1;

        IF @OwnShipperId IS NULL
            THROW 53102,
                N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                1;
    END
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.VaiTroQuyen vtq
            INNER JOIN dbo.Quyen q
                ON q.MaQuyen = vtq.MaQuyen
            WHERE vtq.MaVaiTro = @RoleId
              AND q.KyHieuQuyen = 'COD_DOISOAT'
        )
            THROW 53102,
                N'Bạn không có quyền xem phiếu nộp COD.',
                1;

        IF @Role <> 'ADMIN'
           AND @AccountBranchId IS NULL
            THROW 53102,
                N'Tài khoản chưa được gán bưu cục.',
                1;
    END;

    SELECT n.*
    INTO #ScopedDeposits
    FROM dbo.NopTienCOD n
    WHERE (
        @DepositId IS NULL
        OR n.MaNopTienCOD = @DepositId
    )
      AND (
          (
              @Role = 'SHIPPER'
              AND n.MaNhanVienGiaoHang = @OwnShipperId
          )
          OR (
              @Role <> 'SHIPPER'
              AND (
                  @Role = 'ADMIN'
                  OR n.MaBuuCuc = @AccountBranchId
              )
          )
      );

    """;
    [HttpGet]
    public async Task<IActionResult> GetDeposits(
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

        if (CodQuerySupport.DateError(from,to) is string dateError) return BadRequest(new {message=dateError});

        status = string.IsNullOrWhiteSpace(status)
            ? null
            : status.Trim().ToUpperInvariant();

        if (status is not null
            && status is not (
                "PENDING" or "CONFIRMED" or "REJECTED" or "CANCELLED"))
        {
            return BadRequest(new
            {
                message =
                    "Status chỉ nhận PENDING, CONFIRMED, REJECTED hoặc CANCELLED."
            });
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        var sql = DepositReadScopeSql + """
        IF @Role = 'SHIPPER'
           AND @ShipperId IS NOT NULL
           AND @ShipperId <> @OwnShipperId
            THROW 53102,
                N'Bạn chỉ được xem phiếu của mình.',
                1;

        IF @Role <> 'ADMIN'
           AND @BranchId IS NOT NULL
           AND @BranchId <> @AccountBranchId
            THROW 53102,
                N'Bạn chỉ được xem phiếu thuộc bưu cục của mình.',
                1;

        SELECT
            n.MaNopTienCOD AS id,
            n.KyHieuNopTien AS depositCode,
            n.MaNhanVienGiaoHang AS shipperId,
            shipper.HoTen AS shipperName,
            n.MaBuuCuc AS branchId,
            b.TenBuuCuc AS branchName,
            n.SoTienNop AS amount,
            n.PhuongThucNop AS method,
            n.TrangThaiNop AS status,
            n.ThoiGianNop AS submittedAt,
            n.ThoiGianXacNhan AS confirmedAt,
            n.MaTaiKhoanXacNhan AS confirmedBy,
            confirmer.HoTen AS confirmedByName,
            n.MaThamChieuNgoai AS externalReference,
            n.GhiChu AS notes,
            (
                SELECT COUNT_BIG(*)
                FROM dbo.ChiTietNopTienCOD ct
                WHERE ct.MaNopTienCOD = n.MaNopTienCOD
            ) AS orderCount
        INTO #FilteredDeposits
        FROM #ScopedDeposits n
        INNER JOIN dbo.NhanVienGiaoHang nv
            ON nv.MaNhanVienGiaoHang = n.MaNhanVienGiaoHang
        INNER JOIN dbo.TaiKhoan shipper
            ON shipper.MaTaiKhoan = nv.MaTaiKhoan
        INNER JOIN dbo.BuuCuc b
            ON b.MaBuuCuc = n.MaBuuCuc
        LEFT JOIN dbo.TaiKhoan confirmer
            ON confirmer.MaTaiKhoan = n.MaTaiKhoanXacNhan
        WHERE (
            @Status IS NULL
            OR n.TrangThaiNop = @Status
        )
          AND (@From IS NULL OR n.ThoiGianNop>=@From)
          AND (@To IS NULL OR n.ThoiGianNop<@To)
          AND (
              @ShipperId IS NULL
              OR n.MaNhanVienGiaoHang = @ShipperId
          )
          AND (
              @BranchId IS NULL
              OR n.MaBuuCuc = @BranchId
          )
          AND (
              @Keyword IS NULL
              OR CHARINDEX(@Keyword, n.KyHieuNopTien) > 0
              OR CHARINDEX(@Keyword, n.MaThamChieuNgoai) > 0
              OR CHARINDEX(@Keyword, shipper.HoTen) > 0
          );

        SELECT (
            SELECT
                @Page AS page,
                @PageSize AS pageSize,
                (
                    SELECT COUNT_BIG(*)
                    FROM #FilteredDeposits
                ) AS totalItems,
                JSON_QUERY((SELECT
                    COALESCE(SUM(amount),0) AS totalAmount,
                    COALESCE(SUM(CASE WHEN status='PENDING' THEN amount ELSE 0 END),0) AS pendingAmount,
                    COALESCE(SUM(CASE WHEN status='CONFIRMED' THEN amount ELSE 0 END),0) AS confirmedAmount
                    FROM #FilteredDeposits FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) AS summary,
                JSON_QUERY(COALESCE((
                    SELECT *
                    FROM #FilteredDeposits
                    ORDER BY submittedAt DESC, id DESC
                    OFFSET @Offset ROWS
                    FETCH NEXT @Fetch ROWS ONLY
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                ),N'[]')) AS items
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        DROP TABLE #FilteredDeposits;
        DROP TABLE #ScopedDeposits;
        """;

        await using var command = CreateDepositReadCommand(
            connection, sql, accountId, null);
        command.Parameters.Add("@From",SqlDbType.DateTime2).Value=(object?)from?.UtcDateTime??DBNull.Value;
        command.Parameters.Add("@To",SqlDbType.DateTime2).Value=(object?)to?.UtcDateTime??DBNull.Value;
        command.Parameters.Add("@Fetch",SqlDbType.Int).Value=export?int.MaxValue:pageSize;

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
            "@Offset", SqlDbType.Int).Value = export?0:(page - 1) * pageSize;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is 53101 or 53102)
        {
            return DepositReadError(ex);
        }
    }
    [HttpGet("{id:long}")]
    public async Task<IActionResult> GetDeposit(long id)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã phiếu nộp không hợp lệ."
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

        var sql = DepositReadScopeSql + """
        IF NOT EXISTS (SELECT 1 FROM #ScopedDeposits)
            THROW 53103,
                N'Không tìm thấy phiếu nộp COD.',
                1;

        SELECT (
            SELECT
                n.MaNopTienCOD AS id,
                n.KyHieuNopTien AS depositCode,
                n.MaNhanVienGiaoHang AS shipperId,
                shipper.HoTen AS shipperName,
                n.MaBuuCuc AS branchId,
                b.TenBuuCuc AS branchName,
                n.SoTienNop AS amount,
                n.PhuongThucNop AS method,
                n.TrangThaiNop AS status,
                n.ThoiGianNop AS submittedAt,
                n.ThoiGianXacNhan AS confirmedAt,
                n.MaTaiKhoanXacNhan AS confirmedBy,
                confirmer.HoTen AS confirmedByName,
                n.MaThamChieuNgoai AS externalReference,
                n.GhiChu AS notes,
                JSON_QUERY((
                    SELECT
                        ct.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        ct.SoTienPhanBo AS allocatedAmount,
                        thu.SoTienThucThu AS collectedAmount,
                        thu.TrangThaiThuTien AS collectionStatus
                    FROM dbo.ChiTietNopTienCOD ct
                    INNER JOIN dbo.DonHang d
                        ON d.MaDonHang = ct.MaDonHang
                    LEFT JOIN dbo.ThuTienCOD thu
                        ON thu.MaDonHang = ct.MaDonHang
                    WHERE ct.MaNopTienCOD = n.MaNopTienCOD
                    ORDER BY ct.MaDonHang
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS items
            FROM #ScopedDeposits n
            INNER JOIN dbo.NhanVienGiaoHang nv
                ON nv.MaNhanVienGiaoHang = n.MaNhanVienGiaoHang
            INNER JOIN dbo.TaiKhoan shipper
                ON shipper.MaTaiKhoan = nv.MaTaiKhoan
            INNER JOIN dbo.BuuCuc b
                ON b.MaBuuCuc = n.MaBuuCuc
            LEFT JOIN dbo.TaiKhoan confirmer
                ON confirmer.MaTaiKhoan = n.MaTaiKhoanXacNhan
            FOR JSON PATH,
                INCLUDE_NULL_VALUES,
                WITHOUT_ARRAY_WRAPPER
        );

        DROP TABLE #ScopedDeposits;
        """;

        await using var command = CreateDepositReadCommand(
            connection, sql, accountId, id);

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 53101 and <= 53103)
        {
            return DepositReadError(ex);
        }
    }
    private static SqlCommand CreateDepositReadCommand(
    SqlConnection connection,
    string sql,
    long accountId,
    long? depositId)
    {
        var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@DepositId", SqlDbType.BigInt).Value =
                (object?)depositId ?? DBNull.Value;

        return command;
    }

    private IActionResult DepositReadError(SqlException ex)
    {
        var statusCode = ex.Number switch
        {
            53101 => StatusCodes.Status401Unauthorized,
            53102 => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status404NotFound
        };

        return StatusCode(statusCode, new
        {
            message = ex.Message
        });
    }
    [HttpPost("{id:long}/confirm")]
    public async Task<IActionResult> ConfirmDeposit(long id)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã phiếu nộp COD không hợp lệ."
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
                @DepositBranchId INT,
                @DepositStatus VARCHAR(20),
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
                THROW 53201,
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
                THROW 53202,
                    N'Bạn không có quyền xác nhận phiếu nộp COD.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 53202,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            SELECT
                @DepositBranchId = n.MaBuuCuc,
                @DepositStatus = n.TrangThaiNop
            FROM dbo.NopTienCOD n WITH (UPDLOCK, HOLDLOCK)
            WHERE n.MaNopTienCOD = @DepositId
              AND (
                  @Role = 'ADMIN'
                  OR n.MaBuuCuc = @AccountBranchId
              );

            IF @DepositBranchId IS NULL
                THROW 53203,
                    N'Không tìm thấy phiếu nộp COD.',
                    1;

            IF @DepositStatus <> 'PENDING'
                THROW 53204,
                    N'Chỉ phiếu PENDING mới được xác nhận.',
                    1;

            SET @OldJson = (
                SELECT
                    n.MaNopTienCOD AS id,
                    n.KyHieuNopTien AS depositCode,
                    n.MaNhanVienGiaoHang AS shipperId,
                    n.MaBuuCuc AS branchId,
                    n.SoTienNop AS amount,
                    n.TrangThaiNop AS status
                FROM dbo.NopTienCOD n
                WHERE n.MaNopTienCOD = @DepositId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            -- Procedure kiểm tra:
            -- tổng phân bổ bằng tổng phiếu,
            -- đúng shipper/bưu cục,
            -- không vượt tiền COD thực thu.
            EXEC dbo.sp_XacNhanNopTienCOD
                @MaNopTienCOD = @DepositId,
                @MaTaiKhoanXacNhan = @AccountId;

            SET @Result = (
                SELECT
                    n.MaNopTienCOD AS id,
                    n.KyHieuNopTien AS depositCode,
                    n.MaNhanVienGiaoHang AS shipperId,
                    shipper.HoTen AS shipperName,
                    n.MaBuuCuc AS branchId,
                    n.SoTienNop AS amount,
                    n.PhuongThucNop AS method,
                    n.TrangThaiNop AS status,
                    n.ThoiGianNop AS submittedAt,
                    n.ThoiGianXacNhan AS confirmedAt,
                    n.MaTaiKhoanXacNhan AS confirmedBy,
                    confirmer.HoTen AS confirmedByName,
                    (
                        SELECT COUNT_BIG(*)
                        FROM dbo.ChiTietNopTienCOD ct
                        WHERE ct.MaNopTienCOD = n.MaNopTienCOD
                    ) AS orderCount,
                    N'Đã xác nhận phiếu nộp COD.' AS message
                FROM dbo.NopTienCOD n
                INNER JOIN dbo.NhanVienGiaoHang nv
                    ON nv.MaNhanVienGiaoHang =
                       n.MaNhanVienGiaoHang
                INNER JOIN dbo.TaiKhoan shipper
                    ON shipper.MaTaiKhoan = nv.MaTaiKhoan
                INNER JOIN dbo.TaiKhoan confirmer
                    ON confirmer.MaTaiKhoan =
                       n.MaTaiKhoanXacNhan
                WHERE n.MaNopTienCOD = @DepositId
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
                'CONFIRM_COD_DEPOSIT',
                'NopTienCOD',
                CONVERT(VARCHAR(100), @DepositId),
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
            "@DepositId", SqlDbType.BigInt).Value = id;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            (ex.Number is >= 53201 and <= 53204)
            || (ex.Number is >= 51170 and <= 51175))
        {
            var statusCode = ex.Number switch
            {
                53201 => StatusCodes.Status401Unauthorized,
                53202 => StatusCodes.Status403Forbidden,
                53203 or 51170 => StatusCodes.Status404NotFound,
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
                    "Có thao tác đồng thời. Hãy tải lại phiếu và thử lại."
            });
        }
    }
}
