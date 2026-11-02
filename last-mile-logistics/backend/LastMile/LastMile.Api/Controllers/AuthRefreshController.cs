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
    private readonly ILogger<AuthRefreshController> _logger;

    public AuthRefreshController(IConfiguration configuration, ILogger<AuthRefreshController> logger)
    {
        _configuration = configuration;
        _logger = logger;
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
        catch (SqlException ex)
        {
            // Keep schema/infrastructure failures as server errors with their
            // original stack. Never turn these into "invalid token" responses.
            // Do not log the connection string, request body or credentials.
            var target = new SqlConnectionStringBuilder(_configuration.GetConnectionString("DefaultConnection"));
            _logger.LogError(ex,
                "Refresh thất bại vì lỗi SQL {SqlNumber} trên {Server}/{Database}. Kiểm tra schema và migration 20261019_auth_sessions.sql.",
                ex.Number, target.DataSource, target.InitialCatalog);
            throw;
        }
    }
}
