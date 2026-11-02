using System.ComponentModel.DataAnnotations;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class RefreshTokenRequest
{
    [Required]
    [StringLength(43, MinimumLength = 43)]
    [RegularExpression(@"^[A-Za-z0-9_-]{43}$")]
    public string RefreshToken { get; set; } = "";
}

[ApiController]
[Route("api/v1/auth")]
public class AuthRefreshController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AuthRefreshController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [AllowAnonymous]
    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(
        RefreshTokenRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var tokenService = new AuthTokenService(_configuration);

            var result = await tokenService.RefreshAsync(
                request.RefreshToken,
                cancellationToken);

            return Ok(result);
        }
        catch (UnauthorizedAccessException)
        {
            return Unauthorized(new
            {
                message = "Refresh token không hợp lệ, đã hết hạn hoặc đã bị thu hồi. Hãy đăng nhập lại."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Phiên đăng nhập đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
    }
}