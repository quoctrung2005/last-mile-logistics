using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSignalR();
builder.Services.AddSingleton<LastMile.Api.Services.VehicleTypeCatalog>();

// Cho phép frontend truy cập API.
builder.Services.AddCors(options =>
{
    options.AddPolicy("FrontendWeb", policy =>
    {
        policy
            .WithOrigins(
                "http://localhost:5500",
                "http://127.0.0.1:5500"
            )
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

// Cấu hình JWT.
var jwtKey = builder.Configuration["Jwt:Key"]
    ?? throw new InvalidOperationException("Chưa cấu hình Jwt:Key.");

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,

            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],

            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtKey)),

            ClockSkew = TimeSpan.Zero
        };

        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var token = context.Request.Query["access_token"].FirstOrDefault();
                if (!string.IsNullOrEmpty(token)
                    && context.HttpContext.Request.Path.StartsWithSegments("/hubs/shipper"))
                    context.Token = token;
                return Task.CompletedTask;
            },
            OnTokenValidated = async context =>
            {
                var idText = context.Principal?
                    .FindFirst(ClaimTypes.NameIdentifier)?.Value;

                if (!long.TryParse(idText, out var accountId))
                {
                    context.Fail(
                        "Thông tin tài khoản trong token không hợp lệ.");

                    return;
                }

                var configuration = context.HttpContext.RequestServices
                    .GetRequiredService<IConfiguration>();

                await using var connection = new SqlConnection(
                    configuration.GetConnectionString("DefaultConnection"));

                await using var command = new SqlCommand("""
                    SELECT COUNT(*)
                    FROM dbo.TaiKhoan tk
                    INNER JOIN dbo.VaiTro vt
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @Id
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND vt.DangHoatDong = 1
                      AND (
                          tk.KhoaDenLuc IS NULL
                          OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                      );
                    """, connection);

                command.Parameters.Add(
                    "@Id",
                    System.Data.SqlDbType.BigInt
                ).Value = accountId;

                await connection.OpenAsync(
                    context.HttpContext.RequestAborted);

                var count = Convert.ToInt32(
                    await command.ExecuteScalarAsync(
                        context.HttpContext.RequestAborted));

                if (count == 0)
                {
                    context.Fail(
                        "Tài khoản đã bị khóa hoặc ngừng hoạt động.");
                }
            }
        };
    });

builder.Services.AddAuthorization();

// Giới hạn số lần gọi API theo địa chỉ IP.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode =
        StatusCodes.Status429TooManyRequests;

    options.AddPolicy("password-recovery", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?
                .ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));

    options.AddPolicy("public-tracking", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?
                .ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 30,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
});

// Cấu hình Swagger.
builder.Services.AddEndpointsApiExplorer();

builder.Services.AddSwaggerGen(options =>
{
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "Dán accessToken vào đây."
    });

    options.AddSecurityRequirement(document =>
        new OpenApiSecurityRequirement
        {
            [new OpenApiSecuritySchemeReference("Bearer", document)] = []
        });
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();

    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint(
            "/swagger/v1/swagger.json",
            "Last-mile Logistics API v1");

        options.EnablePersistAuthorization();
    });
}

// Local development uses the same-origin frontend proxy over loopback HTTP.
// Redirecting its API requests to another origin drops the Bearer header in browsers.
// Production continues to require HTTPS; development still supports the HTTPS profile.
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

app.UseRouting();

// CORS phải đặt trước xác thực và phân quyền.
app.UseCors("FrontendWeb");

app.UseRateLimiter();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapHub<LastMile.Api.Hubs.ShipperHub>("/hubs/shipper").RequireAuthorization();

app.Run();
