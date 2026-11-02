using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class ReviewShipperRegistration
{
    [Required,RegularExpression("^(APPROVE|REJECT|NEEDS_INFO)$")] public string Action { get; set; }="";
    [StringLength(500)] public string? Reason { get; set; }
    [Required] public string ExpectedVersion { get; set; }="";
    public Guid CommandId { get; set; }
}

[ApiController,Authorize,Route("api/v1/admin/shipper-registrations")]
public class ShipperRegistrationsAdminController(IConfiguration configuration) : ControllerBase
{
    private long Actor => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var id)?id:0;
    private IActionResult Failure(SqlException e){var error=ShipperRegistrationService.Error(e);return StatusCode(error.Status,new{message=error.Message});}

    [HttpGet]
    public async Task<IActionResult> List([FromQuery,Range(1,100000)]int page=1,
      [FromQuery,Range(1,100)]int pageSize=10,[FromQuery,RegularExpression("^(PENDING|NEEDS_INFO|APPROVED|REJECTED)$")]string? status=null,
      [FromQuery,StringLength(100)]string? keyword=null,CancellationToken ct=default)
    {
        try{
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            await using var command=new SqlCommand(ShipperRegistrationService.AdminGuard+"""
                SELECT r.Id AS id,r.FullName AS fullName,r.Username AS username,r.Phone AS phone,
                  r.Status AS status,r.SubmittedAt AS submittedAt,b.TenBuuCuc AS branchName
                INTO #Rows FROM dbo.ShipperRegistration r JOIN dbo.BuuCuc b ON b.MaBuuCuc=r.BranchId
                WHERE (@Status IS NULL OR r.Status=@Status) AND (@Keyword IS NULL OR CHARINDEX(@Keyword,r.FullName)>0
                  OR CHARINDEX(@Keyword,r.Username)>0 OR CHARINDEX(@Keyword,r.Phone)>0);
                SELECT @Page AS page,@PageSize AS pageSize,(SELECT COUNT(*) FROM #Rows) AS totalItems,
                  JSON_QUERY(COALESCE((SELECT * FROM #Rows ORDER BY submittedAt DESC,id
                    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY FOR JSON PATH),N'[]')) AS items
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;
                """,connection);
            ShipperRegistrationService.AdminParameters(command,Actor,"TAIKHOAN_XEM");
            command.Parameters.Add("@Status",SqlDbType.VarChar,20).Value=(object?)status??DBNull.Value;
            command.Parameters.Add("@Keyword",SqlDbType.NVarChar,100).Value=string.IsNullOrWhiteSpace(keyword)?DBNull.Value:keyword.Trim();
            command.Parameters.Add("@Page",SqlDbType.Int).Value=page;command.Parameters.Add("@PageSize",SqlDbType.Int).Value=pageSize;
            command.Parameters.Add("@Offset",SqlDbType.Int).Value=(page-1)*pageSize;
            Response.Headers.CacheControl="no-store";
            return Content((string)(await command.ExecuteScalarAsync(ct))!,"application/json");
        }catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
        catch(SqlException e)when(e.Number==57501){return Failure(e);}
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Detail(Guid id,CancellationToken ct)
    {
        try{
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            await using var command=new SqlCommand(ShipperRegistrationService.AdminGuard+ShipperRegistrationService.DetailSelect,connection);
            ShipperRegistrationService.AdminParameters(command,Actor,"TAIKHOAN_XEM");
            command.Parameters.Add("@Id",SqlDbType.UniqueIdentifier).Value=id;
            var result=await command.ExecuteScalarAsync(ct) as string;
            if(string.IsNullOrWhiteSpace(result))return NotFound(new{message="Không tìm thấy hồ sơ."});
            Response.Headers.CacheControl="no-store";
            return Content(result,"application/json");
        }catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
        catch(SqlException e)when(e.Number==57501){return Failure(e);}
    }

    [HttpGet("{id:guid}/documents/{kind}")]
    public async Task<IActionResult> Document(Guid id,string kind,CancellationToken ct)
    {
        try{
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            await using var command=new SqlCommand(ShipperRegistrationService.AdminGuard+
              "SELECT Bytes,ContentType FROM dbo.ShipperRegistrationDocument WHERE RegistrationId=@Id AND Kind=@Kind;",connection);
            ShipperRegistrationService.AdminParameters(command,Actor,"TAIKHOAN_XEM");
            command.Parameters.Add("@Id",SqlDbType.UniqueIdentifier).Value=id;
            command.Parameters.Add("@Kind",SqlDbType.VarChar,20).Value=kind;
            await using var reader=await command.ExecuteReaderAsync(ct);
            if(!await reader.ReadAsync(ct))return NotFound();
            Response.Headers.CacheControl="no-store";Response.Headers.XContentTypeOptions="nosniff";
            return File((byte[])reader[0],reader.GetString(1));
        }catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
        catch(SqlException e)when(e.Number==57501){return Failure(e);}
    }

    [HttpPost("{id:guid}/review")]
    public async Task<IActionResult> Review(Guid id,ReviewShipperRegistration request,CancellationToken ct)
    {
        byte[] version;
        try{version=Convert.FromBase64String(request.ExpectedVersion);}catch(FormatException){return BadRequest(new{message="Phiên bản hồ sơ không hợp lệ."});}
        if(version.Length!=8||request.CommandId==Guid.Empty||
          (request.Action!="APPROVE"&&string.IsNullOrWhiteSpace(request.Reason)))
            return BadRequest(new{message="Hãy tải lại hồ sơ và nhập lý do xử lý."});
        var sql="SET NOCOUNT ON;SET XACT_ABORT ON;BEGIN TRY BEGIN TRAN;"+ShipperRegistrationService.AdminGuard+"""
            DECLARE @Status VARCHAR(20),@Version BINARY(8),@BranchId INT,@AreaId INT,@LicenseExpires DATE,
              @Username VARCHAR(100),@PasswordHash VARCHAR(255),@FullName NVARCHAR(150),@Phone VARCHAR(20),@Email VARCHAR(150),
              @IdentityNumber VARCHAR(20),@LicenseNumber VARCHAR(50),@RoleId INT,@AccountId BIGINT=NULL,@ShipperId BIGINT=NULL;
            SELECT @Status=Status,@Version=Version,@BranchId=BranchId,@AreaId=AreaId,@LicenseExpires=LicenseExpiresAt,
              @Username=Username,@PasswordHash=PasswordHash,@FullName=FullName,@Phone=Phone,@Email=Email,
              @IdentityNumber=IdentityNumber,@LicenseNumber=LicenseNumber
            FROM dbo.ShipperRegistration WITH(UPDLOCK,HOLDLOCK) WHERE Id=@Id;
            IF @Status IS NULL THROW 57502,N'Không tìm thấy hồ sơ.',1;
            IF EXISTS(SELECT 1 FROM dbo.ShipperRegistrationEvent WHERE RegistrationId=@Id AND CommandId=@CommandId)
            BEGIN COMMIT;
            """+ShipperRegistrationService.DetailSelect+"""
              RETURN;END;
            IF @Version<>@ExpectedVersion OR @Status NOT IN ('PENDING','NEEDS_INFO')
               OR (@Action<>'REJECT' AND @Status<>'PENDING')
              THROW 57503,N'Hồ sơ đã thay đổi hoặc không còn chờ quyết định này. Hãy tải lại.',1;
            IF @Action='APPROVE'
            BEGIN
              IF @PasswordHash IS NULL OR @LicenseExpires<CONVERT(DATE,DATEADD(MINUTE,420,SYSUTCDATETIME()))
                THROW 57504,N'Giấy phép đã hết hạn hoặc thông tin chưa đầy đủ. Hãy yêu cầu bổ sung.',1;
              IF (SELECT COUNT(*) FROM dbo.ShipperRegistrationDocument WHERE RegistrationId=@Id)<>4
                THROW 57504,N'Hồ sơ thiếu ảnh giấy tờ.',1;
              IF NOT EXISTS(SELECT 1 FROM dbo.BuuCuc b WITH(HOLDLOCK)
                JOIN dbo.KhuVucPhucVuBuuCuc p WITH(HOLDLOCK) ON p.MaBuuCuc=b.MaBuuCuc
                JOIN dbo.KhuVuc k WITH(HOLDLOCK) ON k.MaKhuVuc=p.MaKhuVuc
                WHERE b.MaBuuCuc=@BranchId AND b.DangHoatDong=1 AND k.MaKhuVuc=@AreaId AND k.DangHoatDong=1)
                THROW 57504,N'Bưu cục hoặc khu vực không còn hoạt động. Hãy yêu cầu bổ sung.',1;
              SELECT @RoleId=MaVaiTro FROM dbo.VaiTro WITH(HOLDLOCK) WHERE KyHieuVaiTro='SHIPPER' AND DangHoatDong=1;
              IF @RoleId IS NULL OR (SELECT COUNT(*) FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
                WHERE vq.MaVaiTro=@RoleId AND q.KyHieuQuyen IN ('NHIEMVU_XEM','NHIEMVU_CAPNHAT'))<>2
                THROW 57504,N'Vai trò tài xế chưa sẵn sàng. Kiểm tra phân quyền.',1;
              IF EXISTS(SELECT 1 FROM dbo.TaiKhoan WITH(UPDLOCK,HOLDLOCK) WHERE TenDangNhap=@Username OR Email=@Email OR SoDienThoai=@Phone)
                 OR EXISTS(SELECT 1 FROM dbo.NhanVienGiaoHang WITH(UPDLOCK,HOLDLOCK) WHERE CCCD=@IdentityNumber)
                THROW 57504,N'Thông tin đăng ký đã có tài khoản hoặc hồ sơ tài xế. Hãy kiểm tra trước khi duyệt.',1;
              INSERT dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
              VALUES(CONCAT('TKR-',LEFT(REPLACE(CONVERT(VARCHAR(36),@Id),'-',''),26)),@Username,@PasswordHash,@FullName,@Phone,@Email,@RoleId,@BranchId,'ACTIVE');
              SET @AccountId=SCOPE_IDENTITY();
              INSERT dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,CCCD,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,DangHoatDong)
              VALUES(@AccountId,CONCAT('NVR-',LEFT(REPLACE(CONVERT(VARCHAR(36),@Id),'-',''),26)),@IdentityNumber,@LicenseNumber,@LicenseExpires,'OFFLINE',1);
              SET @ShipperId=SCOPE_IDENTITY();
              INSERT dbo.KhuVucNhanVienGiaoHang(MaNhanVienGiaoHang,MaKhuVuc,LaChinh)VALUES(@ShipperId,@AreaId,1);
            END;
            SET @Status=CASE @Action WHEN 'APPROVE' THEN 'APPROVED' WHEN 'REJECT' THEN 'REJECTED' ELSE 'NEEDS_INFO' END;
            UPDATE dbo.ShipperRegistration SET Status=@Status,ReviewReason=@Reason,ReviewedAt=SYSUTCDATETIME(),ReviewedBy=@ActorId,
              UpdatedAt=SYSUTCDATETIME(),ClosedAt=CASE WHEN @Status IN ('APPROVED','REJECTED') THEN SYSUTCDATETIME() ELSE NULL END,
              AccountId=@AccountId,ShipperId=@ShipperId,PasswordHash=CASE WHEN @Status IN ('APPROVED','REJECTED') THEN NULL ELSE PasswordHash END WHERE Id=@Id;
            INSERT dbo.ShipperRegistrationEvent(RegistrationId,CommandId,Status,Reason,ActorId)VALUES(@Id,@CommandId,@Status,@Reason,@ActorId);
            INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuMoiJson)
            VALUES(@ActorId,'REVIEW_SHIPPER_REGISTRATION','ShipperRegistration',CONVERT(VARCHAR(36),@Id),
              (SELECT @Status AS status,@AccountId AS accountId,@ShipperId AS shipperId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER));
            COMMIT;
            END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK;THROW;END CATCH;
            """+ShipperRegistrationService.DetailSelect;
        try{
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            await using var command=new SqlCommand(sql,connection);
            ShipperRegistrationService.AdminParameters(command,Actor,"TAIKHOAN_QUANLY");
            command.Parameters.Add("@Id",SqlDbType.UniqueIdentifier).Value=id;
            command.Parameters.Add("@CommandId",SqlDbType.UniqueIdentifier).Value=request.CommandId;
            command.Parameters.Add("@ExpectedVersion",SqlDbType.Binary,8).Value=version;
            command.Parameters.Add("@Action",SqlDbType.VarChar,20).Value=request.Action;
            command.Parameters.Add("@Reason",SqlDbType.NVarChar,500).Value=string.IsNullOrWhiteSpace(request.Reason)?DBNull.Value:request.Reason.Trim();
            Response.Headers.CacheControl="no-store";
            return Content((string)(await command.ExecuteScalarAsync(ct))!,"application/json");
        }catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
        catch(SqlException e)when(e.Number is 2601 or 2627 or 1205 or >=57501 and<=57504){return Failure(e);}
    }
}
