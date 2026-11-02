using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Services;

public sealed class RegistrationProblem(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
}

public static class ShipperRegistrationService
{
    public static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    public static async Task<SqlConnection> Open(IConfiguration config, CancellationToken ct)
    {
        var connection = new SqlConnection(config.GetConnectionString("DefaultConnection"));
        try
        {
            await connection.OpenAsync(ct);
            await using var command = new SqlCommand("SELECT CASE WHEN OBJECT_ID(N'dbo.ShipperRegistration',N'U') IS NULL THEN 0 ELSE 1 END;",connection);
            if (Convert.ToInt32(await command.ExecuteScalarAsync(ct)) != 1)
                throw new RegistrationProblem(503,"Chức năng đăng ký tài xế chưa được cài đặt trên máy chủ.");
            return connection;
        }
        catch { await connection.DisposeAsync(); throw; }
    }

    public const string AdminGuard = """
        IF NOT EXISTS (
            SELECT 1 FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro
            JOIN dbo.VaiTroQuyen vq ON vq.MaVaiTro=vt.MaVaiTro
            JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
            WHERE tk.MaTaiKhoan=@ActorId AND tk.TrangThaiTaiKhoan='ACTIVE'
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME())
              AND vt.KyHieuVaiTro='ADMIN' AND vt.DangHoatDong=1
              AND q.KyHieuQuyen=@Permission
        ) THROW 57501,N'Bạn không có quyền xét duyệt hồ sơ tài xế.',1;
        """;

    public const string DetailSelect = """
        SELECT r.Id AS id,r.Username AS username,r.FullName AS fullName,r.Phone AS phone,r.Email AS email,
          r.BirthDate AS birthDate,r.IdentityNumber AS identityNumber,r.LicenseNumber AS licenseNumber,
          r.LicenseExpiresAt AS licenseExpiresAt,r.BranchId AS branchId,b.TenBuuCuc AS branchName,
          r.AreaId AS areaId,kv.TenKhuVuc AS areaName,r.VehicleType AS vehicleType,r.LicensePlate AS licensePlate,
          r.Status AS status,r.SubmittedAt AS submittedAt,r.UpdatedAt AS updatedAt,r.ReviewedAt AS reviewedAt,
          r.ReviewReason AS reviewReason,r.AccountId AS accountId,r.ShipperId AS shipperId,
          CONVERT(BINARY(8),r.Version) AS version,
          JSON_QUERY((SELECT d.Kind AS kind FROM dbo.ShipperRegistrationDocument d WHERE d.RegistrationId=r.Id ORDER BY d.Kind FOR JSON PATH)) AS documents,
          JSON_QUERY((SELECT e.Status AS status,e.Reason AS reason,e.CreatedAt AS createdAt FROM dbo.ShipperRegistrationEvent e
            WHERE e.RegistrationId=r.Id ORDER BY e.Id FOR JSON PATH,INCLUDE_NULL_VALUES)) AS history
        FROM dbo.ShipperRegistration r JOIN dbo.BuuCuc b ON b.MaBuuCuc=r.BranchId
        JOIN dbo.KhuVuc kv ON kv.MaKhuVuc=r.AreaId WHERE r.Id=@Id
        FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER;
        """;

    public static void AdminParameters(SqlCommand command,long actor,string permission)
    {
        command.Parameters.Add("@ActorId",SqlDbType.BigInt).Value=actor;
        command.Parameters.Add("@Permission",SqlDbType.VarChar,100).Value=permission;
    }

    public static (int Status,string Message) Error(SqlException error) => error.Number switch {
        57501 => (403,error.Message), 57502 => (404,"Không tìm thấy hồ sơ hoặc mã theo dõi không hợp lệ."),
        57503 or 57504 or 2601 or 2627 or 1205 => (409,error.Number is 2601 or 2627
            ? "Thông tin đăng ký đã được sử dụng hoặc có hồ sơ đang chờ xét duyệt." : error.Number==1205
            ? "Hồ sơ đang được xử lý đồng thời. Vui lòng tải lại để kiểm tra." : error.Message),
        _ => (500,"Chưa thể xử lý hồ sơ. Vui lòng thử lại.")
    };
}
