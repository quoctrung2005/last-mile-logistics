using System.Data;
using System.Security.Claims;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

// Adds read-only monitoring data to the existing Orders resource.
public partial class OrdersController
{
    private async Task<bool> CanMonitor(SqlConnection connection, CancellationToken token)
    {
        const string sql = """
            SELECT COUNT(*) FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro v ON v.MaVaiTro=tk.MaVaiTro
            WHERE tk.MaTaiKhoan=@AccountId AND tk.TrangThaiTaiKhoan='ACTIVE'
              AND v.DangHoatDong=1 AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME())
              AND EXISTS (SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
                  WHERE vq.MaVaiTro=v.MaVaiTro AND q.KyHieuQuyen='DIEUPHOI_GIAMSAT');
            """;
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = long.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        return Convert.ToInt32(await command.ExecuteScalarAsync(token)) == 1;
    }

    [HttpGet("tracking-options")]
    public async Task<IActionResult> TrackingOptions(CancellationToken cancellationToken)
    {
        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);
        var scope = await GetScope(connection, cancellationToken);
        if (scope is null || !await CanMonitor(connection, cancellationToken)) return Forbid();
        const string sql = """
            SELECT (SELECT
                JSON_QUERY(COALESCE((SELECT b.MaBuuCuc AS id,b.TenBuuCuc AS name FROM dbo.BuuCuc b
                    WHERE @IsAdmin=1 OR b.MaBuuCuc=@BranchId ORDER BY b.TenBuuCuc FOR JSON PATH),N'[]')) AS branches,
                JSON_QUERY(COALESCE((SELECT n.MaNhanVienGiaoHang AS id,t.HoTen AS name,t.MaBuuCuc AS branchId
                    FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan
                    WHERE @IsAdmin=1 OR t.MaBuuCuc=@BranchId ORDER BY t.HoTen FOR JSON PATH),N'[]')) AS shippers,
                JSON_QUERY(COALESCE((SELECT KyHieuTrangThai AS code,TenTrangThai AS name FROM dbo.TrangThaiDonHang
                    ORDER BY MaTrangThaiDonHang FOR JSON PATH),N'[]')) AS statuses
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
            """;
        await using var command = new SqlCommand(sql, connection);
        AddScopeParameters(command, scope.Value.IsAdmin, scope.Value.BranchId);
        return Content((string)(await command.ExecuteScalarAsync(cancellationToken))!, "application/json");
    }

    private async Task<JsonNode?> ReadTracking(SqlConnection connection, long orderId,
        (bool IsAdmin, int? BranchId) scope, CancellationToken token)
    {
        const string sql = """
            SELECT (SELECT
                JSON_QUERY((SELECT TOP(1) pc.MaPhanCongGiaoHang AS id,
                    n.MaNhanVienGiaoHang AS shipperId,t.HoTen AS shipperName,
                    v.BienSo AS licensePlate,pc.TrangThaiPhanCong AS status,
                    c.KyHieuChuyenGiao AS tripCode,c.TrangThaiChuyen AS tripStatus,
                    n.ViDoHienTai AS latitude,n.KinhDoHienTai AS longitude,
                    n.ThoiGianCapNhatViTri AS locationUpdatedAt,pc.ThoiGianPhanCong AS assignedAt
                    FROM dbo.PhanCongGiaoHang pc
                    JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
                    JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan AND t.MaBuuCuc=d.MaBuuCuc
                    LEFT JOIN dbo.PhuongTien v ON v.MaPhuongTien=pc.MaPhuongTien
                    LEFT JOIN dbo.ChuyenGiaoHang c ON c.MaChuyenGiao=pc.MaChuyenGiao
                    WHERE pc.MaDonHang=d.MaDonHang AND pc.ThoiGianKetThuc IS NULL
                      AND pc.TrangThaiPhanCong IN ('PENDING','ACCEPTED','IN_PROGRESS')
                    ORDER BY pc.MaPhanCongGiaoHang DESC
                    FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)) AS currentAssignment,
                JSON_QUERY(COALESCE((SELECT l.MaLanGiaoHang AS id,l.SoLanThu AS attemptNumber,
                    l.KetQua AS result,l.ThoiGianThuGiao AS attemptedAt,reason.TenLyDo AS failureReason,
                    l.GhiChu AS notes,l.ThoiGianGiaoLaiDuKien AS retryExpectedAt,actor.HoTen AS recordedByName,
                    shipper.HoTen AS shipperName
                    FROM dbo.LanGiaoHang l
                    LEFT JOIN dbo.LyDoGiaoThatBai reason ON reason.MaLyDoGiaoThatBai=l.MaLyDoGiaoThatBai
                    LEFT JOIN dbo.TaiKhoan actor ON actor.MaTaiKhoan=l.MaTaiKhoanGhiNhan
                    JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang=l.MaPhanCongGiaoHang AND pc.MaDonHang=l.MaDonHang
                    JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
                    JOIN dbo.TaiKhoan shipper ON shipper.MaTaiKhoan=n.MaTaiKhoan
                    WHERE l.MaDonHang=d.MaDonHang ORDER BY l.SoLanThu DESC
                    FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) AS attempts
                FROM dbo.DonHang d WHERE d.MaDonHang=@Id AND (@IsAdmin=1 OR d.MaBuuCuc=@BranchId)
                FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
            """;
        await using var command = new SqlCommand(sql, connection);
        AddScopeParameters(command, scope.IsAdmin, scope.BranchId);
        command.Parameters.Add("@Id", SqlDbType.BigInt).Value = orderId;
        var json = await command.ExecuteScalarAsync(token) as string;
        return string.IsNullOrWhiteSpace(json) ? null : JsonNode.Parse(json);
    }
}
