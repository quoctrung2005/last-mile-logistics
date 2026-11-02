using System.Text.Json;
using LastMile.Api.Services;
using LastMile.Api.Services.Routing;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

// Read only: never executes DDL, procedures or application writes. Do not print
// the connection string, credentials, JWT settings, names or contact data.
var root=Path.GetFullPath(args[0]);
var output=Path.GetFullPath(args.Length>1?args[1]:Path.Combine(root,"docs/warehouse-depot-diagnostic.json"));
if(!output.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new ArgumentException("Report must stay in workspace");
var project=Path.Combine(root,"backend/LastMile/LastMile.Api");
var config=new ConfigurationBuilder().SetBasePath(project).AddJsonFile("appsettings.json")
    .AddJsonFile("appsettings.Development.json",optional:true).AddUserSecrets(typeof(AuthTokenService).Assembly,optional:true).AddEnvironmentVariables().Build();
var builder=new SqlConnectionStringBuilder(config.GetConnectionString("DefaultConnection"));
await using var connection=new SqlConnection(builder.ConnectionString);await connection.OpenAsync();
await using var command=new SqlCommand("""
    SELECT (SELECT DB_NAME() databaseName,
      JSON_QUERY((SELECT name,TYPE_NAME(system_type_id) type FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Kho') ORDER BY column_id FOR JSON PATH)) warehouseColumns,
      JSON_QUERY((SELECT SCHEMA_NAME(o.schema_id) schemaName,o.name objectName,c.name columnName,TYPE_NAME(c.system_type_id) type
        FROM sys.columns c JOIN sys.objects o ON o.object_id=c.object_id
        WHERE o.type IN('U','V') AND (c.name LIKE '%ViDo%' OR c.name LIKE '%KinhDo%' OR c.name LIKE '%Latitud%' OR c.name LIKE '%Longitud%' OR c.name LIKE '%ToaDo%')
        ORDER BY o.name,c.column_id FOR JSON PATH)) coordinateColumns,
      CONVERT(BIT,CASE WHEN OBJECT_ID('dbo.DispatchRoutePlan','U') IS NULL THEN 0 ELSE 1 END) hasDispatchRoutePlan,
      CONVERT(BIT,CASE WHEN OBJECT_ID('dbo.TripRouteGeometry','U') IS NULL THEN 0 ELSE 1 END) hasTripRouteGeometry,
      CONVERT(BIT,CASE WHEN EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.Kho') AND name='CK_Kho_DepotCoordinates') THEN 1 ELSE 0 END) hasDepotConstraint
      FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    """,connection);
using var schema=JsonDocument.Parse((string)(await command.ExecuteScalarAsync())!);
var columns=schema.RootElement.GetProperty("warehouseColumns").EnumerateArray().Select(c=>c.GetProperty("name").GetString()).ToHashSet();
bool hasCoordinates=new[]{"ViDo","KinhDo","NguonToaDo"}.All(columns.Contains);
var coordinateSql=hasCoordinates?"k.ViDo latitude,k.KinhDo longitude,k.NguonToaDo coordinateSource,":"NULL latitude,NULL longitude,NULL coordinateSource,";
command.CommandText=$"SELECT (SELECT k.MaKho id,k.KyHieuKho code,k.TenKho name,k.DiaChi address,k.MaBuuCuc branchId,{coordinateSql}b.ViDo branchLatitude,b.KinhDo branchLongitude FROM dbo.Kho k JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc ORDER BY k.MaKho FOR JSON PATH,INCLUDE_NULL_VALUES)";
using var warehouses=JsonDocument.Parse((string)(await command.ExecuteScalarAsync())!);
command.CommandText="""
    SELECT (SELECT n.MaNhanVienGiaoHang id,n.MaNhanVien employeeCode,t.MaBuuCuc branchId,n.TrangThaiSanSang availability,n.DangHoatDong isActive,
      (SELECT COUNT(*) FROM dbo.PhanCongGiaoHang p WHERE p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND p.ThoiGianKetThuc IS NULL) activeAssignments,
      (SELECT COUNT(*) FROM dbo.ChuyenGiaoHang c WHERE c.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND c.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED')) openTrips
      FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan
      WHERE t.MaBuuCuc IN(SELECT MaBuuCuc FROM dbo.Kho WHERE KyHieuKho='KHO-TP-PL') FOR JSON PATH,INCLUDE_NULL_VALUES);
    """;
using var shippers=JsonDocument.Parse((string)(await command.ExecuteScalarAsync())!);
command.CommandText="SELECT MIN(t.MaTaiKhoan) FROM dbo.TaiKhoan t JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro WHERE r.KyHieuVaiTro='ADMIN' AND t.TrangThaiTaiKhoan='ACTIVE'";
var actor=await command.ExecuteScalarAsync();
var depotMapping=new List<object>();
JsonElement? options=null;
if(hasCoordinates&&actor is long id&&schema.RootElement.GetProperty("hasDispatchRoutePlan").GetBoolean())
{
    using var result=JsonDocument.Parse(await new DispatchData(config).Options(id,default));
    // Select only fields relevant to diagnosis, not account/contact information.
    options=JsonSerializer.SerializeToElement(new { warehouses=result.RootElement.GetProperty("warehouses"),
        shippers=result.RootElement.GetProperty("shippers").EnumerateArray().Select(s=>new {
            id=s.GetProperty("id"),branchId=s.GetProperty("branchId"),availability=s.GetProperty("availability"),eligibilityReason=s.GetProperty("eligibilityReason") }) });
    RoadGraph? graph=null;
    foreach(var warehouse in warehouses.RootElement.EnumerateArray().Where(w=>w.GetProperty("code").GetString() is "KHO-TP-PL" or "KHO-BT-PL"))
    {
        var warehouseId=warehouse.GetProperty("id").GetInt32();
        await using var tx=(SqlTransaction)await connection.BeginTransactionAsync();
        try
        {
            var access=await DispatchData.Authorize(connection,tx,id,["DIEUPHOI_GOMDON","DIEUPHOI_TOIUUTUYEN"],default);
            var request=new PlanRequest{WarehouseId=warehouseId,DepartureAt=DateTimeOffset.UtcNow.AddHours(1),OrderIds=[],ShipperIds=[]};
            var input=await DispatchData.Load(connection,tx,access,request,default);
            await tx.RollbackAsync(); // Diagnostic only; no orders or business writes.
            graph??=RoadGraph.Load(Path.GetFullPath(config["Routing:GraphPath"]??"Data/roads.osm.gz",project));
            var proposal=new VrpPlanner().Solve(input,request,graph,200,default);
            depotMapping.Add(new{warehouseId,code=warehouse.GetProperty("code").GetString(),state="CONFIGURED",inputDepot=input.Depot,proposalDepot=proposal.Depot,
                sameDepot=input.Depot==proposal.Depot,emptyDiagnosticSelection=true,businessWrites=false});
        }
        catch(DispatchProblem error)
        {
            if(tx.Connection is not null)await tx.RollbackAsync();
            depotMapping.Add(new{warehouseId,code=warehouse.GetProperty("code").GetString(),state="REJECTED",status=error.Status,message=error.Message,businessWrites=false});
        }
    }
}
var report=new { mode="Read-only Development configuration and real DispatchData.Options/live permission queries; no writes",server=builder.DataSource,
    configurationSource=config.Providers.Reverse().First(p=>p.TryGet("ConnectionStrings:DefaultConnection",out _)).ToString(),
    checkedAt=DateTimeOffset.UtcNow,schema=schema.RootElement,warehouses=warehouses.RootElement,shippers=shippers.RootElement,options,depotMapping };
var json=JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true});
await File.WriteAllTextAsync(output,json+"\n");Console.WriteLine(json);
