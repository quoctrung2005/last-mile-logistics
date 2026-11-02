using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Route("api/database")]
public class DatabaseController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly IWebHostEnvironment _environment;

    public DatabaseController(
        IConfiguration configuration,
        IWebHostEnvironment environment)
    {
        _configuration = configuration;
        _environment = environment;
    }

    [HttpGet("check")]
    public async Task<IActionResult> Check()
    {
        // API kiểm tra chỉ dùng khi phát triển trên máy.
        if (!_environment.IsDevelopment())
            return NotFound();

        var connectionString =
            _configuration.GetConnectionString("DefaultConnection");

        if (string.IsNullOrWhiteSpace(connectionString))
            return StatusCode(500, new
            {
                message = "Chưa cấu hình DefaultConnection."
            });

        try
        {
            await using var connection =
                new SqlConnection(connectionString);

            await connection.OpenAsync();

            await using var command = new SqlCommand(
                "SELECT COUNT_BIG(*) FROM dbo.DonHang",
                connection);

            var orderCount = (long)(await command.ExecuteScalarAsync())!;

            return Ok(new
            {
                message = "Kết nối database thành công",
                database = connection.Database,
                orderCount
            });
        }
        catch (SqlException)
        {
            return StatusCode(500, new
            {
                message = "Không đọc được database. Kiểm tra tên database, bảng DonHang và kết nối SQL Server."
            });
        }
    }
}