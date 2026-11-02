namespace LastMile.Api.Controllers;

internal static class CodQuerySupport
{
    internal static string? DateError(DateTimeOffset? from, DateTimeOffset? to)
    {
        if ((from.HasValue && from.Value.Year < 1900) || (to.HasValue && to.Value.Year < 1900))
            return "Ngày tra cứu phải từ năm 1900.";
        if (from.HasValue && to.HasValue && (to <= from || to.Value - from.Value > TimeSpan.FromDays(366)))
            return "Khoảng thời gian phải tăng dần và không quá 366 ngày.";
        return null;
    }

    internal const string ScopeSql = """
        SET NOCOUNT ON;
        DECLARE @Role VARCHAR(50), @RoleId INT, @AccountBranchId INT, @OwnShipperId BIGINT;
        SELECT @Role=v.KyHieuVaiTro,@RoleId=t.MaVaiTro,@AccountBranchId=t.MaBuuCuc
        FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro
        WHERE t.MaTaiKhoan=@AccountId AND t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1
          AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=SYSUTCDATETIME());
        IF @Role IS NULL THROW 57701,N'Tài khoản không còn hợp lệ.',1;
        IF NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen v JOIN dbo.Quyen q ON q.MaQuyen=v.MaQuyen
            WHERE v.MaVaiTro=@RoleId AND q.KyHieuQuyen=CASE WHEN @Role='SHIPPER' THEN 'COD_NOPTIEN' ELSE 'COD_DOISOAT' END)
            THROW 57702,N'Bạn không có quyền xem dữ liệu COD.',1;
        IF @Role<>'ADMIN' AND (@AccountBranchId IS NULL OR (@BranchId IS NOT NULL AND @BranchId<>@AccountBranchId))
            THROW 57702,N'Bạn chỉ được xem bưu cục của mình.',1;
        IF @Role='SHIPPER'
        BEGIN
            SELECT @OwnShipperId=MaNhanVienGiaoHang FROM dbo.NhanVienGiaoHang WHERE MaTaiKhoan=@AccountId AND DangHoatDong=1;
            IF @OwnShipperId IS NULL OR (@ShipperId IS NOT NULL AND @ShipperId<>@OwnShipperId)
                THROW 57702,N'Bạn chỉ được xem COD của mình.',1;
        END;
        """;
}
