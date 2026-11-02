using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Text;
using System.Text.RegularExpressions;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class SubmitShipperRegistration
{
    public Guid ApplicationId { get; set; }
    [Required,RegularExpression(@"^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$")] public string Username { get; set; }="";
    [Required,StringLength(72,MinimumLength=8)] public string Password { get; set; }="";
    [Required,Compare(nameof(Password))] public string ConfirmPassword { get; set; }="";
    [Required,StringLength(150)] public string FullName { get; set; }="";
    [Required,RegularExpression(@"^\+?[0-9]{9,15}$")] public string Phone { get; set; }="";
    [Required,EmailAddress,StringLength(150)] public string Email { get; set; }="";
    public DateOnly? BirthDate { get; set; }
    [Required,RegularExpression(@"^[0-9]{12}$")] public string IdentityNumber { get; set; }="";
    [Required,RegularExpression(@"^[A-Za-z0-9 -]{1,50}$")] public string LicenseNumber { get; set; }="";
    public DateOnly LicenseExpiresAt { get; set; }
    [Range(1,int.MaxValue)] public int BranchId { get; set; }
    [Range(1,int.MaxValue)] public int AreaId { get; set; }
    [Required,RegularExpression("^(MOTORBIKE|VAN|TRUCK)$")] public string VehicleType { get; set; }="";
    [Required,RegularExpression(@"^[A-Za-z0-9. -]{3,20}$")] public string LicensePlate { get; set; }="";
    public string? ExpectedVersion { get; set; }
    [Required] public IFormFile? IdentityFront { get; set; }
    [Required] public IFormFile? IdentityBack { get; set; }
    [Required] public IFormFile? LicensePhoto { get; set; }
    [Required] public IFormFile? Portrait { get; set; }
}

[ApiController,AllowAnonymous,EnableRateLimiting("shipper-registration")]
[Route("api/v1/shipper-registrations")]
public class ShipperRegistrationsPublicController(IConfiguration configuration) : ControllerBase
{
    [HttpGet("catalogs")]
    public async Task<IActionResult> Catalogs(CancellationToken ct)
    {
        try {
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            await using var command=new SqlCommand("""
                SELECT JSON_QUERY(COALESCE((SELECT b.MaBuuCuc AS id,b.TenBuuCuc AS name,b.DiaChi AS address,
                  JSON_QUERY((SELECT k.MaKhuVuc AS id,k.TenKhuVuc AS name FROM dbo.KhuVucPhucVuBuuCuc p
                    JOIN dbo.KhuVuc k ON k.MaKhuVuc=p.MaKhuVuc WHERE p.MaBuuCuc=b.MaBuuCuc AND k.DangHoatDong=1
                    ORDER BY k.MaKhuVuc FOR JSON PATH)) AS areas
                  FROM dbo.BuuCuc b WHERE b.DangHoatDong=1 AND EXISTS(SELECT 1 FROM dbo.KhuVucPhucVuBuuCuc p
                    JOIN dbo.KhuVuc k ON k.MaKhuVuc=p.MaKhuVuc WHERE p.MaBuuCuc=b.MaBuuCuc AND k.DangHoatDong=1)
                  ORDER BY b.TenBuuCuc FOR JSON PATH),N'[]')) AS items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;
                """,connection);
            return Content((string)(await command.ExecuteScalarAsync(ct))!,"application/json");
        } catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
    }

    private string? TokenHash() => Regex.IsMatch(Request.Headers["X-Application-Token"].ToString(),@"^[A-Za-z0-9_-]{43}$")
        ? ShipperRegistrationService.Hash(Request.Headers["X-Application-Token"].ToString()) : null;

    [HttpGet("{id:guid}/status")]
    public async Task<IActionResult> Status(Guid id,CancellationToken ct)
    {
        var hash=TokenHash();if(hash is null)return NotFound(new{message="Mã theo dõi hồ sơ không hợp lệ."});
        try {
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            await using var command=new SqlCommand("IF NOT EXISTS(SELECT 1 FROM dbo.ShipperRegistration WHERE Id=@Id AND TokenHash=@Hash) THROW 57502,N'Không tìm thấy hồ sơ.',1; "+ShipperRegistrationService.DetailSelect,connection);
            command.Parameters.Add("@Id",SqlDbType.UniqueIdentifier).Value=id;
            command.Parameters.Add("@Hash",SqlDbType.VarChar,64).Value=hash;
            Response.Headers.CacheControl="no-store";
            return Content((string)(await command.ExecuteScalarAsync(ct))!,"application/json");
        }catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
        catch(SqlException e)when(e.Number is>=57501 and<=57504){var error=ShipperRegistrationService.Error(e);return StatusCode(error.Status,new{message=error.Message});}
    }

    [HttpPost]
    [Consumes("multipart/form-data"),RequestSizeLimit(24*1024*1024),RequestFormLimits(MultipartBodyLengthLimit=24*1024*1024)]
    public Task<IActionResult> Submit([FromForm]SubmitShipperRegistration request,CancellationToken ct)=>Save(request,false,ct);

    [HttpPut("{id:guid}")]
    [Consumes("multipart/form-data"),RequestSizeLimit(24*1024*1024),RequestFormLimits(MultipartBodyLengthLimit=24*1024*1024)]
    public Task<IActionResult> Resubmit(Guid id,[FromForm]SubmitShipperRegistration request,CancellationToken ct)
        =>id!=request.ApplicationId?Task.FromResult<IActionResult>(BadRequest(new{message="Mã hồ sơ không khớp."})):Save(request,true,ct);

    private async Task<IActionResult> Save(SubmitShipperRegistration r,bool resubmit,CancellationToken ct)
    {
        var hash=TokenHash();
        if(hash is null||r.ApplicationId==Guid.Empty)return BadRequest(new{message="Mã theo dõi hồ sơ không hợp lệ."});
        var today=VietnamDate.FromInstant(DateTimeOffset.UtcNow);
        if(string.IsNullOrWhiteSpace(r.Password)||Encoding.UTF8.GetByteCount(r.Password)>72
           ||string.IsNullOrWhiteSpace(r.FullName)||string.IsNullOrWhiteSpace(r.LicenseNumber)
           ||r.LicenseExpiresAt<today||r.BirthDate>=today)
            return BadRequest(new{message="Kiểm tra thông tin cá nhân, mật khẩu và hạn giấy phép lái xe."});
        byte[]? version=null;
        if(resubmit){try{version=Convert.FromBase64String(r.ExpectedVersion??"");}catch(FormatException){}if(version?.Length!=8)return BadRequest(new{message="Thiếu phiên bản hồ sơ. Hãy tải lại trạng thái."});}
        try {
            await using var connection=await ShipperRegistrationService.Open(configuration,ct);
            var docs=new List<(string Kind,DeliveryEvidenceImage Image)>();
            foreach(var(kind,file)in new[]{("IDENTITY_FRONT",r.IdentityFront),("IDENTITY_BACK",r.IdentityBack),("LICENSE",r.LicensePhoto),("PORTRAIT",r.Portrait)})
                docs.Add((kind,await DeliveryEvidenceImage.ReadAsync(file!,ct)));
            var passwordHash=BCrypt.Net.BCrypt.HashPassword(r.Password,workFactor:12);
            var sql="""
                SET NOCOUNT ON; SET XACT_ABORT ON;
                BEGIN TRY
                  BEGIN TRAN;
                  DECLARE @Status VARCHAR(20),@ExistingHash VARCHAR(64),@Version BINARY(8);
                  SELECT @Status=Status,@ExistingHash=TokenHash,@Version=Version FROM dbo.ShipperRegistration WITH(UPDLOCK,HOLDLOCK) WHERE Id=@Id;
                  IF @Status IS NOT NULL
                  BEGIN
                    IF @ExistingHash<>@Hash THROW 57502,N'Mã theo dõi không hợp lệ.',1;
                    IF @Resubmit=0 BEGIN COMMIT;
                """+ShipperRegistrationService.DetailSelect+"""
                      RETURN; END;
                    IF @Status<>'NEEDS_INFO' OR @Version<>@ExpectedVersion
                      THROW 57503,N'Hồ sơ đã thay đổi hoặc không ở trạng thái cần bổ sung. Hãy tải lại.',1;
                  END
                  ELSE IF @Resubmit=1 THROW 57502,N'Không tìm thấy hồ sơ.',1;
                  IF NOT EXISTS(SELECT 1 FROM dbo.BuuCuc b JOIN dbo.KhuVucPhucVuBuuCuc p ON p.MaBuuCuc=b.MaBuuCuc
                     JOIN dbo.KhuVuc k ON k.MaKhuVuc=p.MaKhuVuc WHERE b.MaBuuCuc=@BranchId AND b.DangHoatDong=1 AND k.MaKhuVuc=@AreaId AND k.DangHoatDong=1)
                     THROW 57503,N'Bưu cục hoặc khu vực không còn tiếp nhận đăng ký. Hãy chọn lại.',1;
                  IF EXISTS(SELECT 1 FROM dbo.TaiKhoan WITH(UPDLOCK,HOLDLOCK) WHERE TenDangNhap=@Username OR Email=@Email OR SoDienThoai=@Phone)
                     OR EXISTS(SELECT 1 FROM dbo.NhanVienGiaoHang WITH(UPDLOCK,HOLDLOCK) WHERE CCCD=@IdentityNumber)
                     THROW 57503,N'Thông tin đăng ký đã được sử dụng. Vui lòng liên hệ quản trị viên nếu bạn đã có tài khoản.',1;
                  IF @Status IS NULL
                    INSERT dbo.ShipperRegistration(Id,TokenHash,Username,PasswordHash,FullName,Phone,Email,BirthDate,IdentityNumber,LicenseNumber,LicenseExpiresAt,BranchId,AreaId,VehicleType,LicensePlate)
                    VALUES(@Id,@Hash,@Username,@PasswordHash,@FullName,@Phone,@Email,@BirthDate,@IdentityNumber,@LicenseNumber,@LicenseExpiresAt,@BranchId,@AreaId,@VehicleType,@LicensePlate);
                  ELSE
                    UPDATE dbo.ShipperRegistration SET Username=@Username,PasswordHash=@PasswordHash,FullName=@FullName,Phone=@Phone,Email=@Email,
                      BirthDate=@BirthDate,IdentityNumber=@IdentityNumber,LicenseNumber=@LicenseNumber,LicenseExpiresAt=@LicenseExpiresAt,
                      BranchId=@BranchId,AreaId=@AreaId,VehicleType=@VehicleType,LicensePlate=@LicensePlate,Status='PENDING',
                      UpdatedAt=SYSUTCDATETIME(),ReviewReason=NULL,ReviewedAt=NULL,ReviewedBy=NULL WHERE Id=@Id;
                  DELETE dbo.ShipperRegistrationDocument WHERE RegistrationId=@Id;
                """;
            for(var i=0;i<docs.Count;i++)sql+=$"INSERT dbo.ShipperRegistrationDocument(RegistrationId,Kind,ContentType,Bytes)VALUES(@Id,@Kind{i},@Type{i},@Bytes{i});";
            sql+="""
                  INSERT dbo.ShipperRegistrationEvent(RegistrationId,Status) VALUES(@Id,'PENDING');
                  COMMIT;
                END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
                """+ShipperRegistrationService.DetailSelect;
            await using var command=new SqlCommand(sql,connection);
            command.Parameters.Add("@Id",SqlDbType.UniqueIdentifier).Value=r.ApplicationId;
            command.Parameters.Add("@Hash",SqlDbType.VarChar,64).Value=hash;
            command.Parameters.Add("@Resubmit",SqlDbType.Bit).Value=resubmit;
            command.Parameters.Add("@ExpectedVersion",SqlDbType.Binary,8).Value=(object?)version??DBNull.Value;
            command.Parameters.Add("@PasswordHash",SqlDbType.VarChar,255).Value=passwordHash;
            foreach(var(name,value,size,unicode)in new[]{("Username",r.Username.Trim(),100,false),("FullName",r.FullName.Trim(),150,true),
              ("Phone",r.Phone.Trim(),20,false),("Email",r.Email.Trim(),150,false),("IdentityNumber",r.IdentityNumber,20,false),
              ("LicenseNumber",r.LicenseNumber.Trim(),50,false),("VehicleType",r.VehicleType,30,false),("LicensePlate",r.LicensePlate.Trim().ToUpperInvariant(),20,true)})
                command.Parameters.Add("@"+name,unicode?SqlDbType.NVarChar:SqlDbType.VarChar,size).Value=value;
            command.Parameters.Add("@BirthDate",SqlDbType.Date).Value=r.BirthDate.HasValue?r.BirthDate.Value.ToDateTime(TimeOnly.MinValue):DBNull.Value;
            command.Parameters.Add("@LicenseExpiresAt",SqlDbType.Date).Value=r.LicenseExpiresAt.ToDateTime(TimeOnly.MinValue);
            command.Parameters.Add("@BranchId",SqlDbType.Int).Value=r.BranchId;
            command.Parameters.Add("@AreaId",SqlDbType.Int).Value=r.AreaId;
            for(var i=0;i<docs.Count;i++){
                command.Parameters.Add("@Kind"+i,SqlDbType.VarChar,20).Value=docs[i].Kind;
                command.Parameters.Add("@Type"+i,SqlDbType.VarChar,30).Value=docs[i].Image.Extension==".png"?"image/png":"image/jpeg";
                command.Parameters.Add("@Bytes"+i,SqlDbType.VarBinary,-1).Value=docs[i].Image.Bytes;
            }
            Response.Headers.CacheControl="no-store";
            return Content((string)(await command.ExecuteScalarAsync(ct))!,"application/json");
        }catch(RegistrationProblem e){return StatusCode(e.Status,new{message=e.Message});}
        catch(EvidenceImageException e){return StatusCode(e.StatusCode,new{message=e.Message});}
        catch(SqlException e)when(e.Number is 2601 or 2627 or 1205 or >=57501 and<=57504){var error=ShipperRegistrationService.Error(e);return StatusCode(error.Status,new{message=error.Message});}
    }
}
