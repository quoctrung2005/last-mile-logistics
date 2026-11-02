# Chỉ mục tài liệu và mã nguồn

Ngày rà soát: 29/10/2026. Chỉ mục cấu trúc tự động; không đồng nghĩa đã kiểm chứng mọi nhánh xử lý. Bỏ qua thư viện bên thứ ba, bản biên dịch, bộ nhớ đệm và hồ sơ trình duyệt.

## backend/LastMile/LastMile.Api/Controllers/AccountActionsController.cs

Số dòng: 536
- Dòng 11: public class AccountActionRequest
- Dòng 26: public class AdminResetPasswordRequest
- Dòng 40: [Route("api/v1/accounts")]
- Dòng 41: public class AccountActionsController : ControllerBase
- Dòng 52: [HttpPost("{id:long}/reset-password")]
- Dòng 137: [HttpPost("{id:long}/actions")]

## backend/LastMile/LastMile.Api/Controllers/AccountCreateController.cs

Số dòng: 363
- Dòng 11: public class CreateAccountRequest
- Dòng 46: [Route("api/v1/accounts")]
- Dòng 47: public class AccountCreateController : ControllerBase
- Dòng 56: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/AccountsController.cs

Số dòng: 334
- Dòng 11: [Route("api/v1/accounts")]
- Dòng 12: public class AccountsController : ControllerBase
- Dòng 21: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/AccountUpdateController.cs

Số dòng: 488
- Dòng 10: public class UpdateAccountRequest
- Dòng 38: [Route("api/v1/accounts")]
- Dòng 39: public class AccountUpdateController : ControllerBase
- Dòng 48: [HttpPut("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/AuditLogsController.cs

Số dòng: 361
- Dòng 13: [Route("api/v1/audit-logs")]
- Dòng 14: public class AuditLogsController : ControllerBase
- Dòng 23: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/AuthChangePasswordController.cs

Số dòng: 259
- Dòng 11: public class ChangePasswordRequest
- Dòng 30: [Route("api/v1/auth")]
- Dòng 31: public class AuthChangePasswordController : ControllerBase
- Dòng 40: [HttpPost("change-password")]

## backend/LastMile/LastMile.Api/Controllers/AuthController.cs

Số dòng: 218
- Dòng 13: public class LoginRequest
- Dòng 25: [Route("api/v1/auth")]
- Dòng 26: public class AuthController : ControllerBase
- Dòng 39: [HttpPost("login")]
- Dòng 172: [HttpGet("permissions")]
- Dòng 204: [HttpGet("me")]

## backend/LastMile/LastMile.Api/Controllers/AuthLogoutController.cs

Số dòng: 163
- Dòng 11: public class LogoutRequest
- Dòng 22: [Route("api/v1/auth")]
- Dòng 23: public class AuthLogoutController : ControllerBase
- Dòng 33: [HttpPost("logout")]

## backend/LastMile/LastMile.Api/Controllers/AuthPasswordRecoveryController.cs

Số dòng: 413
- Dòng 15: public class PasswordRecoveryRequest
- Dòng 41: [Route("api/v1/auth")]
- Dòng 42: public class AuthPasswordRecoveryController : ControllerBase
- Dòng 55: [HttpPost("password-recovery")]

## backend/LastMile/LastMile.Api/Controllers/AuthRefreshController.cs

Số dòng: 72
- Dòng 9: public class RefreshTokenRequest
- Dòng 18: [Route("api/v1/auth")]
- Dòng 19: public class AuthRefreshController : ControllerBase
- Dòng 31: [HttpPost("refresh")]

## backend/LastMile/LastMile.Api/Controllers/AuthTokenService.cs

Số dòng: 440
- Dòng 11: public class AuthTokenService

## backend/LastMile/LastMile.Api/Controllers/CatalogSaveController.cs

Số dòng: 903
- Dòng 10: public class SaveCatalogRequest
- Dòng 92: [Route("api/v1/catalogs")]
- Dòng 93: public class CatalogSaveController : ControllerBase
- Dòng 110: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/CatalogsController.cs

Số dòng: 286
- Dòng 11: [Route("api/v1/catalogs")]
- Dòng 12: public class CatalogsController : ControllerBase
- Dòng 21: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/CodCollectionsController.cs

Số dòng: 363
- Dòng 12: [Route("api/v1/cod")]
- Dòng 13: public class CodCollectionsController : ControllerBase
- Dòng 22: [HttpGet("collections")]

## backend/LastMile/LastMile.Api/Controllers/CodDepositsController.cs

Số dòng: 1101
- Dòng 11: public class CreateCodDepositRequest
- Dòng 35: public class CodDepositItemRequest
- Dòng 49: [Route("api/v1/cod/deposits")]
- Dòng 50: public class CodDepositsController : ControllerBase
- Dòng 59: [HttpPost]
- Dòng 569: [HttpGet]
- Dòng 752: [HttpGet("{id:long}")]
- Dòng 879: [HttpPost("{id:long}/confirm")]

## backend/LastMile/LastMile.Api/Controllers/CodFormController.cs

Số dòng: 93
- Dòng 11: public class CodFormController(IConfiguration configuration) : ControllerBase
- Dòng 13: [HttpGet("options")]
- Dòng 34: [HttpGet("reconciliations/preview")]

## backend/LastMile/LastMile.Api/Controllers/CodQuerySupport.cs

Số dòng: 34
- Dòng 3: internal static class CodQuerySupport

## backend/LastMile/LastMile.Api/Controllers/CodReconciliationsController.cs

Số dòng: 948
- Dòng 10: public class CreateCodReconciliationRequest
- Dòng 30: [Route("api/v1/cod/reconciliations")]
- Dòng 31: public class CodReconciliationsController : ControllerBase
- Dòng 40: [HttpPost]
- Dòng 394: [HttpPost("{id:long}/confirm")]
- Dòng 630: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/CustomerAddressCreateController.cs

Số dòng: 398
- Dòng 10: public class AddCustomerAddressRequest
- Dòng 47: [Route("api/v1/customers")]
- Dòng 48: public class CustomerAddressCreateController : ControllerBase
- Dòng 57: [HttpPost("{customerId:long}/addresses")]

## backend/LastMile/LastMile.Api/Controllers/CustomerAddressUpdateController.cs

Số dòng: 485
- Dòng 10: public class UpdateCustomerAddressRequest
- Dòng 54: [Route("api/v1/customers")]
- Dòng 55: public class CustomerAddressUpdateController : ControllerBase
- Dòng 64: [HttpPut("{customerId:long}/addresses/{addressId:long}")]

## backend/LastMile/LastMile.Api/Controllers/CustomerCreateController.cs

Số dòng: 416
- Dòng 10: public class CreateCustomerRequest
- Dòng 35: public class CreateCustomerInitialAddressRequest
- Dòng 68: [Route("api/v1/customers")]
- Dòng 69: public class CustomerCreateController : ControllerBase
- Dòng 78: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/CustomerDetailController.cs

Số dòng: 301
- Dòng 11: [Route("api/v1/customers")]
- Dòng 12: public class CustomerDetailController : ControllerBase
- Dòng 21: [HttpGet("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/CustomerUpdateController.cs

Số dòng: 286
- Dòng 10: public class UpdateCustomerRequest
- Dòng 41: [Route("api/v1/customers")]
- Dòng 42: public class CustomerUpdateController : ControllerBase
- Dòng 51: [HttpPut("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/DashboardController.cs

Số dòng: 163
- Dòng 11: public sealed class DashboardProblem(int status, string message) : Exception(message) { public int Status { get; } = status; }
- Dòng 12: public sealed class DashboardExceptionFilter(ILogger<DashboardExceptionFilter> logger) : IExceptionFilter
- Dòng 30: [Route("api/v1/dashboard")]
- Dòng 31: public sealed class DashboardController(IConfiguration configuration) : ControllerBase
- Dòng 75: [HttpGet("context")]
- Dòng 91: [HttpGet("operations")]
- Dòng 142: [HttpGet("delivery-today")]

## backend/LastMile/LastMile.Api/Controllers/DatabaseController.cs

Số dòng: 65
- Dòng 7: [Route("api/database")]
- Dòng 8: public class DatabaseController : ControllerBase
- Dòng 21: [HttpGet("check")]

## backend/LastMile/LastMile.Api/Controllers/DeliveryEvidenceDeleteController.cs

Số dòng: 435
- Dòng 10: public class DeleteDeliveryEvidenceRequest
- Dòng 19: [Route("api/v1/orders/{orderId:long}/evidence")]
- Dòng 20: public class DeliveryEvidenceDeleteController : ControllerBase
- Dòng 36: [HttpDelete("{evidenceId:long}")]

## backend/LastMile/LastMile.Api/Controllers/DeliveryEvidenceFileController.cs

Số dòng: 365
- Dòng 12: [Route("api/v1/orders/{orderId:long}/evidence")]
- Dòng 13: public class DeliveryEvidenceFileController : ControllerBase
- Dòng 26: [HttpGet("{evidenceId:long}/file")]

## backend/LastMile/LastMile.Api/Controllers/DeliveryEvidenceReadController.cs

Số dòng: 290
- Dòng 12: [Route("api/v1/orders/{orderId:long}/evidence")]
- Dòng 13: public class DeliveryEvidenceReadController : ControllerBase
- Dòng 23: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/DeliveryEvidenceUploadController.cs

Số dòng: 449
- Dòng 11: public class UploadDeliveryEvidenceRequest
- Dòng 41: [Route("api/v1/orders/{orderId:long}/evidence")]
- Dòng 42: public class DeliveryEvidenceUploadController : ControllerBase
- Dòng 60: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/DispatchAssignmentsController.cs

Số dòng: 1644
- Dòng 11: public class CreateDispatchAssignmentRequest
- Dòng 28: [Route("api/v1/dispatch/assignments")]
- Dòng 29: public class DispatchAssignmentsController : ControllerBase
- Dòng 38: [HttpPost]
- Dòng 571: [HttpGet]
- Dòng 837: public class CancelDispatchAssignmentRequest
- Dòng 843: [HttpPost("{id:long}/cancel")]
- Dòng 1146: public class ReassignDispatchRequest
- Dòng 1158: [HttpPost("{id:long}/reassign")]

## backend/LastMile/LastMile.Api/Controllers/DispatchOrdersController.cs

Số dòng: 299
- Dòng 12: [Route("api/v1/dispatch")]
- Dòng 13: public class DispatchOrdersController : ControllerBase
- Dòng 22: [HttpGet("orders")]

## backend/LastMile/LastMile.Api/Controllers/DispatchPlanningController.cs

Số dòng: 50
- Dòng 12: public sealed class DispatchExceptionFilter(ILogger<DispatchExceptionFilter> logger) : IExceptionFilter
- Dòng 32: [Route("api/v1")]
- Dòng 33: public sealed class DispatchPlanningController(DispatchData data,DispatchPlanningService planning,RoadNetwork network) : ControllerBase
- Dòng 36: [HttpGet("dispatch/options")]
- Dòng 42: [HttpPost("dispatch/plans")]
- Dòng 44: [HttpGet("dispatch/plans/{id:guid}")]
- Dòng 46: [HttpPost("dispatch/plans/{id:guid}/confirm")]
- Dòng 48: [HttpGet("trips/{id:long}/route")]

## backend/LastMile/LastMile.Api/Controllers/DispatchShippersController.cs

Số dòng: 389
- Dòng 13: [Route("api/v1/dispatch")]
- Dòng 14: public class DispatchShippersController : ControllerBase
- Dòng 23: [HttpGet("shippers")]

## backend/LastMile/LastMile.Api/Controllers/MyHandoversController.cs

Số dòng: 759
- Dòng 12: [Route("api/v1/my/handovers")]
- Dòng 13: public class MyHandoversController : ControllerBase
- Dòng 22: [HttpPost("{id:long}/confirm")]
- Dòng 432: [HttpPost("/api/v1/my/tasks/{id:long}/start-delivery")]

## backend/LastMile/LastMile.Api/Controllers/MyShipperStatusController.cs

Số dòng: 432
- Dòng 10: public class UpdateMyShipperStatusRequest
- Dòng 38: [Route("api/v1/my/shipper-status")]
- Dòng 39: public class MyShipperStatusController : ControllerBase
- Dòng 48: [HttpPatch]

## backend/LastMile/LastMile.Api/Controllers/MyTasksController.cs

Số dòng: 1536
- Dòng 13: [Route("api/v1/my/tasks")]
- Dòng 14: public class MyTasksController : ControllerBase
- Dòng 23: [HttpPost("{id:long}/accept")]
- Dòng 338: [HttpPost("{id:long}/start-retry")]
- Dòng 668: [HttpGet]
- Dòng 944: [HttpGet("{id:long}")]
- Dòng 1239: public class RejectMyTaskRequest
- Dòng 1245: [HttpPost("{id:long}/reject")]

## backend/LastMile/LastMile.Api/Controllers/NotificationsReadController.cs

Số dòng: 187
- Dòng 12: [Route("api/v1/notifications")]
- Dòng 13: public class NotificationsReadController : ControllerBase
- Dòng 22: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/NotificationsReadStatusController.cs

Số dòng: 225
- Dòng 11: public class MarkNotificationsReadRequest : IValidatableObject
- Dòng 66: [Route("api/v1/notifications")]
- Dòng 67: public class NotificationsReadStatusController : ControllerBase
- Dòng 77: [HttpPatch("read")]

## backend/LastMile/LastMile.Api/Controllers/OperationalOrderQuery.cs

Số dòng: 31
- Dòng 4: internal static class OperationalOrderQuery

## backend/LastMile/LastMile.Api/Controllers/OrderCancelController.cs

Số dòng: 336
- Dòng 10: public class CancelOrderRequest
- Dòng 23: [Route("api/v1/orders")]
- Dòng 24: public class OrderCancelController : ControllerBase
- Dòng 37: [HttpPost("{id:long}/cancel")]

## backend/LastMile/LastMile.Api/Controllers/OrderCompleteController.cs

Số dòng: 333
- Dòng 10: public class CompleteOrderRequest
- Dòng 18: [Route("api/v1/orders")]
- Dòng 19: public class OrderCompleteController : ControllerBase
- Dòng 28: [HttpPost("{id:long}/complete")]

## backend/LastMile/LastMile.Api/Controllers/OrderConfirmController.cs

Số dòng: 828
- Dòng 14: public class ConfirmOrderRequest
- Dòng 24: [Route("api/v1/orders")]
- Dòng 25: public class OrderConfirmController : ControllerBase
- Dòng 53: [HttpPost("{id:long}/confirm")]

## backend/LastMile/LastMile.Api/Controllers/OrderCreateController.cs

Số dòng: 671
- Dòng 13: public class CreateOrderRequest : IValidatableObject
- Dòng 75: public class CreateOrderItemRequest : IValidatableObject
- Dòng 148: public sealed class OrderDateTimeOffsetConverter
- Dòng 212: [Route("api/v1/orders")]
- Dòng 213: public class OrderCreateController : ControllerBase
- Dòng 226: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/OrderDeliveryFailureController.cs

Số dòng: 568
- Dòng 12: public class DeliveryFailureRequest
- Dòng 26: [Route("api/v1")]
- Dòng 27: public class OrderDeliveryFailureController : ControllerBase
- Dòng 104: [HttpGet("delivery-failure-reasons")]
- Dòng 147: [HttpPost("orders/{id:long}/delivery-failure")]

## backend/LastMile/LastMile.Api/Controllers/OrderDeliveryScheduleController.cs

Số dòng: 447
- Dòng 10: public class UpdateOrderDeliveryScheduleRequest
- Dòng 26: [Route("api/v1/orders")]
- Dòng 27: public class OrderDeliveryScheduleController : ControllerBase
- Dòng 40: [HttpPut("{id:long}/delivery-schedule")]

## backend/LastMile/LastMile.Api/Controllers/OrderDeliverySuccessController.cs

Số dòng: 429
- Dòng 10: public class DeliverySuccessRequest
- Dòng 41: [Route("api/v1/orders")]
- Dòng 42: public class OrderDeliverySuccessController : ControllerBase
- Dòng 51: [HttpPost("{id:long}/delivery-success")]

## backend/LastMile/LastMile.Api/Controllers/OrderFormController.cs

Số dòng: 312
- Dòng 11: [Route("api/v1")]
- Dòng 12: public class OrderFormController : ControllerBase
- Dòng 81: [HttpGet("customers")]
- Dòng 180: [HttpGet("customers/{id:long}/addresses")]
- Dòng 243: [HttpGet("order-form/options")]

## backend/LastMile/LastMile.Api/Controllers/OrderReadyForDispatchController.cs

Số dòng: 543
- Dòng 9: public class ReadyForDispatchRequest
- Dòng 17: [Route("api/v1/orders")]
- Dòng 18: public class OrderReadyForDispatchController : ControllerBase
- Dòng 31: [HttpPost("{id:long}/ready-for-dispatch")]

## backend/LastMile/LastMile.Api/Controllers/OrderRetryController.cs

Số dòng: 370
- Dòng 10: public class OrderRetryRequest
- Dòng 22: [Route("api/v1/orders")]
- Dòng 23: public class OrderRetryController : ControllerBase
- Dòng 32: [HttpPost("{id:long}/retry")]

## backend/LastMile/LastMile.Api/Controllers/OrderReturnRequestController.cs

Số dòng: 354
- Dòng 10: public class CreateOrderReturnRequest
- Dòng 19: [Route("api/v1/orders")]
- Dòng 20: public class OrderReturnRequestController : ControllerBase
- Dòng 29: [HttpPost("{id:long}/return-request")]

## backend/LastMile/LastMile.Api/Controllers/OrderReturnStartController.cs

Số dòng: 374
- Dòng 11: public class StartOrderReturnRequest
- Dòng 19: [Route("api/v1/orders")]
- Dòng 20: public class OrderReturnStartController : ControllerBase
- Dòng 29: [HttpPost("{id:long}/return-start")]

## backend/LastMile/LastMile.Api/Controllers/OrdersController.cs

Số dòng: 902
- Dòng 11: [Route("api/v1/orders")]
- Dòng 12: public partial class OrdersController : ControllerBase
- Dòng 101: [HttpGet]
- Dòng 573: [HttpGet("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/OrdersTracking.cs

Số dòng: 91
- Dòng 10: public partial class OrdersController
- Dòng 27: [HttpGet("tracking-options")]

## backend/LastMile/LastMile.Api/Controllers/OrderUpdateController.cs

Số dòng: 618
- Dòng 12: public class UpdateOrderRequest : CreateOrderRequest
- Dòng 20: [Route("api/v1/orders")]
- Dòng 21: public class OrderUpdateController : ControllerBase
- Dòng 34: [HttpPut("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/PublicTrackingController.cs

Số dòng: 115
- Dòng 13: [Route("api/v1/tracking")]
- Dòng 14: public class PublicTrackingController : ControllerBase
- Dòng 23: [HttpGet("{trackingNumber}")]

## backend/LastMile/LastMile.Api/Controllers/PublicTrackingHistoryController.cs

Số dòng: 151
- Dòng 13: [Route("api/v1/tracking")]
- Dòng 14: public class PublicTrackingHistoryController : ControllerBase
- Dòng 23: [HttpGet("{trackingNumber}/history")]

## backend/LastMile/LastMile.Api/Controllers/ReportsDashboardController.cs

Số dòng: 552
- Dòng 12: [Route("api/v1/reports")]
- Dòng 13: public class ReportsDashboardController : ControllerBase
- Dòng 22: [HttpGet("dashboard")]

## backend/LastMile/LastMile.Api/Controllers/ReportsQuery.cs

Số dòng: 141
- Dòng 5: internal static class ReportsQuery

## backend/LastMile/LastMile.Api/Controllers/RolePermissionsController.cs

Số dòng: 386
- Dòng 11: public class UpdateRolePermissionsRequest
- Dòng 28: [Route("api/v1/roles")]
- Dòng 29: public class RolePermissionsController : ControllerBase
- Dòng 38: [HttpPut("{id:int}/permissions")]

## backend/LastMile/LastMile.Api/Controllers/RoleSaveController.cs

Số dòng: 309
- Dòng 10: public class SaveRoleRequest
- Dòng 35: [Route("api/v1/roles")]
- Dòng 36: public class RoleSaveController : ControllerBase
- Dòng 45: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/RolesController.cs

Số dòng: 272
- Dòng 11: [Route("api/v1/roles")]
- Dòng 12: public class RolesController : ControllerBase
- Dòng 21: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/ShipperCreateController.cs

Số dòng: 420
- Dòng 12: public class CreateShipperRequest
- Dòng 35: public class CreateShipperAreaRequest
- Dòng 45: [Route("api/v1/shippers")]
- Dòng 46: public class ShipperCreateController : ControllerBase
- Dòng 55: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/ShippersController.cs

Số dòng: 364
- Dòng 11: [Route("api/v1/shippers")]
- Dòng 12: public class ShippersController : ControllerBase
- Dòng 21: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/ShipperUpdateController.cs

Số dòng: 499
- Dòng 13: public class UpdateShipperRequest
- Dòng 39: public class UpdateShipperAreaRequest
- Dòng 49: [Route("api/v1/shippers")]
- Dòng 50: public class ShipperUpdateController : ControllerBase
- Dòng 62: [HttpPut("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/ShipperVehicleController.cs

Số dòng: 415
- Dòng 11: public class SetShipperVehicleRequest
- Dòng 26: [Route("api/v1/shippers")]
- Dòng 27: public class ShipperVehicleController : ControllerBase
- Dòng 36: [HttpPut("{id:long}/vehicle")]

## backend/LastMile/LastMile.Api/Controllers/ShippingFeeRulesController.cs

Số dòng: 568
- Dòng 10: public class SaveShippingFeeRuleRequest : IValidatableObject
- Dòng 137: [Route("api/v1/shipping-fees/rules")]
- Dòng 138: public class ShippingFeeRulesController : ControllerBase
- Dòng 147: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/ShippingFeeRulesReadController.cs

Số dòng: 275
- Dòng 12: [Route("api/v1/shipping-fees/rules")]
- Dòng 13: public class ShippingFeeRulesReadController : ControllerBase
- Dòng 23: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/ShippingFeesController.cs

Số dòng: 730
- Dòng 14: public class ShippingFeeQuoteRequest
- Dòng 41: [Route("api/v1/shipping-fees")]
- Dòng 42: public class ShippingFeesController : ControllerBase
- Dòng 107: [HttpPost("quote")]

## backend/LastMile/LastMile.Api/Controllers/TripActionsController.cs

Số dòng: 591
- Dòng 11: public class TripActionRequest
- Dòng 25: [Route("api/v1/trips")]
- Dòng 26: public class TripActionsController : ControllerBase
- Dòng 35: [HttpPost("{id:long}/actions")]

## backend/LastMile/LastMile.Api/Controllers/TripOptimizationController.cs

Số dòng: 28
- Dòng 9: public sealed class OptimizeTripRequest
- Dòng 19: [Route("api/v1/trips")]
- Dòng 20: public sealed class TripOptimizationController(DispatchPlanningService planning) : ControllerBase
- Dòng 22: [HttpPost("{id:long}/optimize")]

## backend/LastMile/LastMile.Api/Controllers/TripsController.cs

Số dòng: 1415
- Dòng 12: public class CreateTripRequest
- Dòng 30: [Route("api/v1/trips")]
- Dòng 31: public class TripsController : ControllerBase
- Dòng 40: [HttpPost]
- Dòng 416: [HttpGet]
- Dòng 829: public class UpdateTripRequest
- Dòng 844: [HttpPut("{id:long}")]

## backend/LastMile/LastMile.Api/Controllers/VehicleSaveController.cs

Số dòng: 525
- Dòng 12: public class SaveVehicleRequest
- Dòng 52: [Route("api/v1/vehicles")]
- Dòng 53: public class VehicleSaveController : ControllerBase
- Dòng 74: [HttpPost]

## backend/LastMile/LastMile.Api/Controllers/VehiclesController.cs

Số dòng: 503
- Dòng 12: [Route("api/v1/vehicles")]
- Dòng 13: public class VehiclesController : ControllerBase
- Dòng 22: [HttpGet("types")]
- Dòng 33: [HttpGet]

## backend/LastMile/LastMile.Api/Controllers/WarehouseDepotController.cs

Số dòng: 135
- Dòng 13: public sealed record DepotSnapshot(decimal? Latitude, decimal? Longitude, string? CoordinateSource);
- Dòng 14: public sealed class UpdateDepotRequest
- Dòng 24: [Route("api/v1/warehouses/{id:int}/depot")]
- Dòng 25: public sealed class WarehouseDepotController(DispatchData data, RoadNetwork network, ILogger<WarehouseDepotController> logger) : ControllerBase
- Dòng 29: [HttpGet]
- Dòng 79: [HttpPut]

## backend/LastMile/LastMile.Api/Controllers/WarehouseHandoverOrdersController.cs

Số dòng: 358
- Dòng 13: [Route("api/v1/warehouses")]
- Dòng 14: public class WarehouseHandoverOrdersController : ControllerBase
- Dòng 24: [HttpGet("{id:int}/handover-orders")]

## backend/LastMile/LastMile.Api/Controllers/WarehouseInboundController.cs

Số dòng: 312
- Dòng 11: public class WarehouseInboundRequest
- Dòng 28: [Route("api/v1/warehouse-transactions")]
- Dòng 29: public class WarehouseInboundController : ControllerBase
- Dòng 42: [HttpPost("inbound")]

## backend/LastMile/LastMile.Api/Controllers/WarehouseMoveController.cs

Số dòng: 316
- Dòng 11: public class WarehouseMoveRequest
- Dòng 28: [Route("api/v1/warehouse-transactions")]
- Dòng 29: public class WarehouseMoveController : ControllerBase
- Dòng 42: [HttpPost("move")]

## backend/LastMile/LastMile.Api/Controllers/WarehouseOutboundController.cs

Số dòng: 524
- Dòng 11: public class WarehouseOutboundRequest
- Dòng 31: [Route("api/v1/warehouse-transactions")]
- Dòng 32: public class WarehouseOutboundController : ControllerBase
- Dòng 41: [HttpPost("outbound")]

## backend/LastMile/LastMile.Api/Controllers/WarehouseReturnInController.cs

Số dòng: 452
- Dòng 10: public class WarehouseReturnInRequest
- Dòng 34: [Route("api/v1/warehouse-transactions")]
- Dòng 35: public class WarehouseReturnInController : ControllerBase
- Dòng 44: [HttpPost("return-in")]

## backend/LastMile/LastMile.Api/Controllers/WarehouseReturnRequestsController.cs

Số dòng: 165
- Dòng 12: [Route("api/v1/warehouses")]
- Dòng 13: public class WarehouseReturnRequestsController : ControllerBase
- Dòng 23: [HttpGet("{id:int}/return-requests")]

## backend/LastMile/LastMile.Api/Controllers/WarehousesController.cs

Số dòng: 358
- Dòng 12: [Route("api/v1/warehouses")]
- Dòng 13: public class WarehousesController : ControllerBase
- Dòng 116: [HttpGet]
- Dòng 160: [HttpGet("{id:int}/locations")]
- Dòng 221: [HttpGet("{id:int}/inventory")]

## backend/LastMile/LastMile.Api/Controllers/WarehouseTransactionsController.cs

Số dòng: 335
- Dòng 12: [Route("api/v1/warehouse-transactions")]
- Dòng 13: public class WarehouseTransactionsController : ControllerBase
- Dòng 92: [HttpGet]
- Dòng 254: [HttpGet("{id:long}")]

## backend/LastMile/LastMile.Api/LastMile.Api.csproj

Số dòng: 27

## backend/LastMile/LastMile.Api/Program.cs

Số dòng: 242

## backend/LastMile/LastMile.Api/Services/AuditDataSanitizer.cs

Số dòng: 51
- Dòng 7: public static class AuditDataSanitizer

## backend/LastMile/LastMile.Api/Services/DeliveryEvidenceImage.cs

Số dòng: 125
- Dòng 6: public sealed class EvidenceImageException(int statusCode, string message, Exception? inner = null) : Exception(message, inner)
- Dòng 11: public sealed record DeliveryEvidenceImage(byte[] Bytes, string Extension)

## backend/LastMile/LastMile.Api/Services/LoginAttemptService.cs

Số dòng: 54
- Dòng 7: public sealed class LoginAttemptService(IConfiguration configuration, IOptions<LoginSecurityOptions> options)

## backend/LastMile/LastMile.Api/Services/LoginSecurityOptions.cs

Số dòng: 20
- Dòng 5: public sealed class LoginSecurityOptions

## backend/LastMile/LastMile.Api/Services/Routing/DepotCoordinates.cs

Số dòng: 16
- Dòng 3: public static class DepotCoordinates
- Dòng 5: public sealed record Assessment(string State, string Message);

## backend/LastMile/LastMile.Api/Services/Routing/DispatchData.cs

Số dòng: 153
- Dòng 9: public sealed class DispatchData(IConfiguration configuration)
- Dòng 24: public sealed record Access(string Role, int? BranchId);

## backend/LastMile/LastMile.Api/Services/Routing/DispatchPlanningService.cs

Số dòng: 173
- Dòng 8: public sealed class DispatchPlanningService(DispatchData data,RoadNetwork network,VrpPlanner planner)

## backend/LastMile/LastMile.Api/Services/Routing/RoadGraph.cs

Số dòng: 138
- Dòng 13: public sealed class RoadGraph
- Dòng 15: public sealed record Edge(long To, double Meters, double Seconds);
- Dòng 132: public sealed class RoadNetwork(IConfiguration config, IWebHostEnvironment environment)

## backend/LastMile/LastMile.Api/Services/Routing/RoutingModels.cs

Số dòng: 54
- Dòng 5: public sealed record GeoPoint(double Latitude, double Longitude)
- Dòng 9: public sealed record RoadLeg(double DistanceMeters, double TravelSeconds, GeoPoint[] Geometry);
- Dòng 10: public sealed class DispatchProblem(int status, string message) : Exception(message)
- Dòng 14: public sealed class PlanRequest
- Dòng 35: public sealed record ManualRoute(long ShipperId, List<long> OrderIds);
- Dòng 36: public sealed record PlanningOrder(long Id, string Version, string TrackingNumber, string ReceiverName, string Address,
- Dòng 39: public sealed record PlanningVehicle(long ShipperId, string ShipperName, long VehicleId, string LicensePlate,
- Dòng 41: public sealed record PlanningInput(int WarehouseId, int BranchId, string WarehouseName, GeoPoint? Depot,
- Dòng 43: public sealed record UnplannedOrder(long OrderId, string TrackingNumber, string Reason);
- Dòng 44: public sealed record PlannedStop(long OrderId, string TrackingNumber, string ReceiverName, string Address, int Sequence,
- Dòng 49: public sealed record ProposedRoute(long ShipperId, string ShipperName, long VehicleId, string LicensePlate,
- Dòng 52: public sealed record Proposal(Guid Id, string Method, string RoadAlgorithm, string GraphVersion, DateTimeOffset ExpiresAt,

## backend/LastMile/LastMile.Api/Services/Routing/VrpPlanner.cs

Số dòng: 154
- Dòng 8: public sealed class VrpPlanner

## backend/LastMile/LastMile.Api/Services/SqlResult.cs

Số dòng: 118
- Dòng 8: public sealed class SqlResultContractException(string reason) : Exception(reason);
- Dòng 12: public static class SqlResult
- Dòng 43: public sealed class Row(DbDataReader reader)

## backend/LastMile/LastMile.Api/Services/VehicleTypeCatalog.cs

Số dòng: 31
- Dòng 3: public sealed class VehicleTypeDefinition
- Dòng 15: public sealed class VehicleTypeCatalog(IConfiguration configuration)

## backend/LastMile/LastMile.Api/Services/VersionSchemaDiagnostics.cs

Số dòng: 198
- Dòng 13: public static class VersionSchemaDiagnostics

## backend/LastMile/LastMile.Api/Services/VietnamDate.cs

Số dòng: 24
- Dòng 6: public static class VietnamDate

## backend/LastMile/LastMile.Calendar.Tests/FleetVersionChecks.cs

Số dòng: 174
- Dòng 16: internal static class FleetVersionChecks

## backend/LastMile/LastMile.Calendar.Tests/LastMile.Calendar.Tests.csproj

Số dòng: 11

## backend/LastMile/LastMile.Calendar.Tests/Program.cs

Số dòng: 75

## backend/LastMile/LastMile.Calendar.Tests/ShipperUpdateChecks.cs

Số dòng: 204
- Dòng 18: internal static class ShipperUpdateChecks

## backend/LastMile/LastMile.Calendar.Tests/VersionSchemaChecks.cs

Số dòng: 83
- Dòng 8: internal static class VersionSchemaChecks

## backend/LastMile/LastMile.DeliveryFailure.Tests/LastMile.DeliveryFailure.Tests.csproj

Số dòng: 11

## backend/LastMile/LastMile.DeliveryFailure.Tests/Program.cs

Số dòng: 475

## backend/LastMile/LastMile.Evidence.Tests/LastMile.Evidence.Tests.csproj

Số dòng: 11

## backend/LastMile/LastMile.Evidence.Tests/Program.cs

Số dòng: 168

## backend/LastMile/LastMile.Routing.Tests/LastMile.Routing.Tests.csproj

Số dòng: 10

## backend/LastMile/LastMile.Routing.Tests/Program.cs

Số dòng: 134

## backend/LastMile/LastMile.SqlResults.Tests/LastMile.SqlResults.Tests.csproj

Số dòng: 12

## backend/LastMile/LastMile.SqlResults.Tests/Program.cs

Số dòng: 266

## database/01_KhoiTao_CoSoDuLieu_Va_CauTruc.sql

Số dòng: 3506
- Dòng 119: CREATE TABLE dbo.VaiTro (
- Dòng 131: CREATE TABLE dbo.Quyen (
- Dòng 140: CREATE TABLE dbo.VaiTroQuyen (
- Dòng 156: CREATE TABLE dbo.KhuVuc (
- Dòng 171: CREATE TABLE dbo.BuuCuc (
- Dòng 196: CREATE TABLE dbo.KhuVucPhucVuBuuCuc (
- Dòng 213: CREATE TABLE dbo.TaiKhoan (
- Dòng 254: CREATE TABLE dbo.PhienDangNhap (
- Dòng 267: CREATE TABLE dbo.TokenLamMoi (
- Dòng 290: CREATE TABLE dbo.TokenKhoiPhucMatKhau (
- Dòng 304: CREATE TABLE dbo.Kho (
- Dòng 326: CREATE TABLE dbo.ViTriLuuKho (
- Dòng 345: CREATE TABLE dbo.KhachHang (
- Dòng 363: CREATE TABLE dbo.DiaChiKhachHang (
- Dòng 399: CREATE TABLE dbo.NhanVienGiaoHang (
- Dòng 432: CREATE TABLE dbo.PhuongTien (
- Dòng 450: CREATE TABLE dbo.PhanCongPhuongTien (
- Dòng 478: CREATE TABLE dbo.KhuVucNhanVienGiaoHang (
- Dòng 495: CREATE TABLE dbo.LichSuViTriNhanVienGiaoHang (
- Dòng 523: CREATE TABLE dbo.LoaiDichVu (
- Dòng 533: CREATE TABLE dbo.QuyTacTinhPhi (
- Dòng 570: CREATE TABLE dbo.TrangThaiDonHang (
- Dòng 581: CREATE TABLE dbo.ChuyenTrangThaiDonHang (
- Dòng 594: CREATE TABLE dbo.DonHang (
- Dòng 656: CREATE TABLE dbo.DiemGiaoNhan (
- Dòng 687: CREATE TABLE dbo.ChiTietDonHang (
- Dòng 713: CREATE TABLE dbo.KhoanPhiDonHang (
- Dòng 734: CREATE TABLE dbo.TonKhoDonHang (
- Dòng 760: CREATE TABLE dbo.GiaoDichKho (
- Dòng 779: CREATE TABLE dbo.ChiTietGiaoDichKho (
- Dòng 799: CREATE TABLE dbo.BanGiaoHang (
- Dòng 826: CREATE TABLE dbo.ChiTietBanGiaoHang (
- Dòng 844: CREATE TABLE dbo.ChuyenGiaoHang (
- Dòng 886: CREATE TABLE dbo.ChiTietChuyenGiao (
- Dòng 905: CREATE TABLE dbo.DiemDungTuyen (
- Dòng 942: CREATE TABLE dbo.PhanCongGiaoHang (
- Dòng 990: CREATE TABLE dbo.DispatchRoutePlan (
- Dòng 1007: CREATE TABLE dbo.TripRouteGeometry (
- Dòng 1029: CREATE TABLE dbo.LichSuTrangThaiDonHang (
- Dòng 1054: CREATE TABLE dbo.LyDoGiaoThatBai (
- Dòng 1064: CREATE TABLE dbo.LanGiaoHang (
- Dòng 1100: CREATE TABLE dbo.BangChungGiaoHang (
- Dòng 1133: CREATE TABLE dbo.YeuCauGiaoLaiHoacHoan (
- Dòng 1161: CREATE TABLE dbo.CanhBaoGiaoHang (
- Dòng 1190: CREATE TABLE dbo.ThuTienCOD (
- Dòng 1227: CREATE TABLE dbo.NopTienCOD (
- Dòng 1263: CREATE TABLE dbo.ChiTietNopTienCOD (
- Dòng 1276: CREATE TABLE dbo.DoiSoatCOD (
- Dòng 1317: CREATE TABLE dbo.ChiTietDoiSoatCOD (
- Dòng 1345: CREATE TABLE dbo.DanhGia (
- Dòng 1366: CREATE TABLE dbo.KhieuNai (
- Dòng 1398: CREATE TABLE dbo.LichSuKhieuNai (
- Dòng 1422: CREATE TABLE dbo.ThongBao (
- Dòng 1447: CREATE TABLE dbo.NhatKyHoatDong (
- Dòng 1661: CREATE OR ALTER TRIGGER dbo.TR_BuuCuc_DongBoToaDoDiaLy
- Dòng 1679: CREATE OR ALTER TRIGGER dbo.TR_DiaChiKhachHang_DongBoToaDoDiaLy
- Dòng 1697: CREATE OR ALTER TRIGGER dbo.TR_NhanVienGiaoHang_DongBoToaDoHienTai
- Dòng 1715: CREATE OR ALTER TRIGGER dbo.TR_DiemGiaoNhan_DongBoToaDoDiaLy
- Dòng 1733: CREATE OR ALTER TRIGGER dbo.TR_DiemDungTuyen_DongBoToaDoDiaLy
- Dòng 1762: CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraToanVenTrangThai
- Dòng 1942: CREATE OR ALTER TRIGGER dbo.TR_DanhGia_ChiDonDaHoanTat
- Dòng 1978: CREATE OR ALTER TRIGGER dbo.TR_ChiTietChuyenGiao_KiemTraTaiTrong
- Dòng 2045: CREATE OR ALTER TRIGGER dbo.TR_ChuyenGiaoHang_KiemTraTaiTrong
- Dòng 2116: CREATE OR ALTER TRIGGER dbo.TR_NhanVienGiaoHang_KiemTraVaiTro
- Dòng 2137: CREATE OR ALTER TRIGGER dbo.TR_ChiTietDonHang_DongBoTongKhoiLuong
- Dòng 2167: CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraTongKhoiLuong
- Dòng 2194: CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraTaiTrongSauCapNhatKhoiLuong
- Dòng 2266: CREATE OR ALTER TRIGGER dbo.TR_PhanCongGiaoHang_KiemTraChuyen
- Dòng 2292: CREATE OR ALTER TRIGGER dbo.TR_ChuyenGiaoHang_KiemTraPhanCong
- Dòng 2320: CREATE OR ALTER TRIGGER dbo.TR_ChiTietGiaoDichKho_KiemTraViTri
- Dòng 2347: CREATE OR ALTER TRIGGER dbo.TR_ChiTietBanGiaoHang_KiemTra
- Dòng 2378: CREATE OR ALTER TRIGGER dbo.TR_QuyTacTinhPhi_KhongChongLap
- Dòng 2409: CREATE OR ALTER TRIGGER dbo.TR_ChiTietDonHang_BaoVeDonDaXuLy
- Dòng 2430: CREATE OR ALTER TRIGGER dbo.TR_DiemGiaoNhan_BaoVeDonDaXuLy
- Dòng 2455: CREATE OR ALTER TRIGGER dbo.TR_ChiTietChuyenGiao_MotChuyenHoatDong
- Dòng 2488: CREATE OR ALTER TRIGGER dbo.TR_KhieuNai_KiemTraKhachHang
- Dòng 2511: CREATE OR ALTER VIEW dbo.vw_TongHopVanHanhDonHang
- Dòng 2550: CREATE OR ALTER VIEW dbo.vw_CongNoCODNhanVienGiaoHang
- Dòng 2677: CREATE OR ALTER PROCEDURE dbo.sp_ChuyenTrangThaiDonHang
- Dòng 2801: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanDonHang
- Dòng 2829: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanGiaoHangThanhCong
- Dòng 3003: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanGiaoHangThatBai
- Dòng 3156: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanNopTienCOD
- Dòng 3265: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanDoiSoatCOD
- Dòng 3431: CREATE OR ALTER PROCEDURE dbo.sp_DonDepLichSuViTriNhanVienGiaoHang

## database/02_Nap_DuLieu_ThucTe.sql

Số dòng: 3379

## database/configure_warehouse_depot.sql

Số dòng: 52

## database/diagnostics/verify_shipper_vehicle_versions.sql

Số dòng: 23

## database/DuLieuThucTe_QLGiaoHangChangCuoi_V5 .sql

Số dòng: 1422

## database/DuLieuThucTe.final.sql

Số dòng: 1678

## database/migrations/20261017_dispatch_planning.sql

Số dòng: 37
- Dòng 15: CREATE TABLE dbo.DispatchRoutePlan(
- Dòng 30: CREATE TABLE dbo.TripRouteGeometry(

## database/migrations/20261019_auth_sessions.sql

Số dòng: 35
- Dòng 9: CREATE TABLE dbo.PhienDangNhap (

## database/migrations/20261019_customer_versions.sql

Số dòng: 15

## database/migrations/20261019_shipper_vehicle_versions.sql

Số dòng: 51

## database/QLGiaoHangChangCuoi_SQLServer_V5 .sql

Số dòng: 3383
- Dòng 108: CREATE TABLE dbo.VaiTro (
- Dòng 120: CREATE TABLE dbo.Quyen (
- Dòng 129: CREATE TABLE dbo.VaiTroQuyen (
- Dòng 145: CREATE TABLE dbo.KhuVuc (
- Dòng 160: CREATE TABLE dbo.BuuCuc (
- Dòng 185: CREATE TABLE dbo.KhuVucPhucVuBuuCuc (
- Dòng 202: CREATE TABLE dbo.TaiKhoan (
- Dòng 240: CREATE TABLE dbo.TokenLamMoi (
- Dòng 257: CREATE TABLE dbo.Kho (
- Dòng 272: CREATE TABLE dbo.ViTriLuuKho (
- Dòng 291: CREATE TABLE dbo.KhachHang (
- Dòng 308: CREATE TABLE dbo.DiaChiKhachHang (
- Dòng 343: CREATE TABLE dbo.NhanVienGiaoHang (
- Dòng 375: CREATE TABLE dbo.PhuongTien (
- Dòng 392: CREATE TABLE dbo.PhanCongPhuongTien (
- Dòng 420: CREATE TABLE dbo.KhuVucNhanVienGiaoHang (
- Dòng 437: CREATE TABLE dbo.LichSuViTriNhanVienGiaoHang (
- Dòng 465: CREATE TABLE dbo.LoaiDichVu (
- Dòng 475: CREATE TABLE dbo.QuyTacTinhPhi (
- Dòng 512: CREATE TABLE dbo.TrangThaiDonHang (
- Dòng 523: CREATE TABLE dbo.ChuyenTrangThaiDonHang (
- Dòng 536: CREATE TABLE dbo.DonHang (
- Dòng 598: CREATE TABLE dbo.DiemGiaoNhan (
- Dòng 629: CREATE TABLE dbo.ChiTietDonHang (
- Dòng 655: CREATE TABLE dbo.KhoanPhiDonHang (
- Dòng 676: CREATE TABLE dbo.TonKhoDonHang (
- Dòng 702: CREATE TABLE dbo.GiaoDichKho (
- Dòng 721: CREATE TABLE dbo.ChiTietGiaoDichKho (
- Dòng 741: CREATE TABLE dbo.BanGiaoHang (
- Dòng 768: CREATE TABLE dbo.ChiTietBanGiaoHang (
- Dòng 786: CREATE TABLE dbo.ChuyenGiaoHang (
- Dòng 828: CREATE TABLE dbo.ChiTietChuyenGiao (
- Dòng 847: CREATE TABLE dbo.DiemDungTuyen (
- Dòng 884: CREATE TABLE dbo.PhanCongGiaoHang (
- Dòng 943: CREATE TABLE dbo.LichSuTrangThaiDonHang (
- Dòng 968: CREATE TABLE dbo.LyDoGiaoThatBai (
- Dòng 978: CREATE TABLE dbo.LanGiaoHang (
- Dòng 1014: CREATE TABLE dbo.BangChungGiaoHang (
- Dòng 1047: CREATE TABLE dbo.YeuCauGiaoLaiHoacHoan (
- Dòng 1075: CREATE TABLE dbo.CanhBaoGiaoHang (
- Dòng 1104: CREATE TABLE dbo.ThuTienCOD (
- Dòng 1141: CREATE TABLE dbo.NopTienCOD (
- Dòng 1177: CREATE TABLE dbo.ChiTietNopTienCOD (
- Dòng 1190: CREATE TABLE dbo.DoiSoatCOD (
- Dòng 1231: CREATE TABLE dbo.ChiTietDoiSoatCOD (
- Dòng 1259: CREATE TABLE dbo.DanhGia (
- Dòng 1280: CREATE TABLE dbo.KhieuNai (
- Dòng 1312: CREATE TABLE dbo.LichSuKhieuNai (
- Dòng 1336: CREATE TABLE dbo.ThongBao (
- Dòng 1361: CREATE TABLE dbo.NhatKyHoatDong (
- Dòng 1575: CREATE OR ALTER TRIGGER dbo.TR_BuuCuc_DongBoToaDoDiaLy
- Dòng 1593: CREATE OR ALTER TRIGGER dbo.TR_DiaChiKhachHang_DongBoToaDoDiaLy
- Dòng 1611: CREATE OR ALTER TRIGGER dbo.TR_NhanVienGiaoHang_DongBoToaDoHienTai
- Dòng 1629: CREATE OR ALTER TRIGGER dbo.TR_DiemGiaoNhan_DongBoToaDoDiaLy
- Dòng 1647: CREATE OR ALTER TRIGGER dbo.TR_DiemDungTuyen_DongBoToaDoDiaLy
- Dòng 1676: CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraToanVenTrangThai
- Dòng 1856: CREATE OR ALTER TRIGGER dbo.TR_DanhGia_ChiDonDaHoanTat
- Dòng 1892: CREATE OR ALTER TRIGGER dbo.TR_ChiTietChuyenGiao_KiemTraTaiTrong
- Dòng 1959: CREATE OR ALTER TRIGGER dbo.TR_ChuyenGiaoHang_KiemTraTaiTrong
- Dòng 2030: CREATE OR ALTER TRIGGER dbo.TR_NhanVienGiaoHang_KiemTraVaiTro
- Dòng 2051: CREATE OR ALTER TRIGGER dbo.TR_ChiTietDonHang_DongBoTongKhoiLuong
- Dòng 2081: CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraTongKhoiLuong
- Dòng 2108: CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraTaiTrongSauCapNhatKhoiLuong
- Dòng 2180: CREATE OR ALTER TRIGGER dbo.TR_PhanCongGiaoHang_KiemTraChuyen
- Dòng 2206: CREATE OR ALTER TRIGGER dbo.TR_ChuyenGiaoHang_KiemTraPhanCong
- Dòng 2234: CREATE OR ALTER TRIGGER dbo.TR_ChiTietGiaoDichKho_KiemTraViTri
- Dòng 2261: CREATE OR ALTER TRIGGER dbo.TR_ChiTietBanGiaoHang_KiemTra
- Dòng 2292: CREATE OR ALTER TRIGGER dbo.TR_QuyTacTinhPhi_KhongChongLap
- Dòng 2323: CREATE OR ALTER TRIGGER dbo.TR_ChiTietDonHang_BaoVeDonDaXuLy
- Dòng 2344: CREATE OR ALTER TRIGGER dbo.TR_DiemGiaoNhan_BaoVeDonDaXuLy
- Dòng 2369: CREATE OR ALTER TRIGGER dbo.TR_ChiTietChuyenGiao_MotChuyenHoatDong
- Dòng 2402: CREATE OR ALTER TRIGGER dbo.TR_KhieuNai_KiemTraKhachHang
- Dòng 2425: CREATE OR ALTER VIEW dbo.vw_TongHopVanHanhDonHang
- Dòng 2464: CREATE OR ALTER VIEW dbo.vw_CongNoCODNhanVienGiaoHang
- Dòng 2572: CREATE OR ALTER PROCEDURE dbo.sp_ChuyenTrangThaiDonHang
- Dòng 2678: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanDonHang
- Dòng 2706: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanGiaoHangThanhCong
- Dòng 2880: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanGiaoHangThatBai
- Dòng 3033: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanNopTienCOD
- Dòng 3142: CREATE OR ALTER PROCEDURE dbo.sp_XacNhanDoiSoatCOD
- Dòng 3308: CREATE OR ALTER PROCEDURE dbo.sp_DonDepLichSuViTriNhanVienGiaoHang

## database/SQLQuery1.sql

Số dòng: 29

## docs/accounts-implementation-verification.md

Số dòng: 54
- Dòng 1: # Trang Tài khoản — triển khai và kiểm chứng
- Dòng 5: ## File sửa/bổ sung
- Dòng 17: ## API sử dụng
- Dòng 35: ## Kiểm tra đã chạy
- Dòng 48: ## Giới hạn còn lại

## docs/admin-implementation-verification.md

Số dòng: 78
- Dòng 1: # Bốn trang quản trị — triển khai và kiểm chứng
- Dòng 5: ## Vai trò & quyền
- Dòng 21: ## Danh mục
- Dòng 35: ## Bảng giá
- Dòng 51: ## Nhật ký hệ thống
- Dòng 65: ## File dùng chung, kiểm tra và ảnh

## docs/auth-refresh-runtime-fix.md

Số dòng: 85
- Dòng 1: # Lỗi lookup refresh token ngày 19/10/2026
- Dòng 3: ## Nguyên nhân thực tế
- Dòng 28: ## Thay đổi và migration đã áp dụng
- Dòng 55: ## Kiểm tra
- Dòng 72: ## Chẩn đoán/chạy lại

## docs/auth-session-revocation.md

Số dòng: 97
- Dòng 1: # Thu hồi phiên đăng nhập
- Dòng 3: ## Cơ chế
- Dòng 33: ## Đồng thời
- Dòng 46: ## Áp dụng
- Dòng 61: ## Kiểm chứng

## docs/auth-session-verification.md

Số dòng: 64
- Dòng 1: # Xác thực và refresh — kiểm tra ngày 09/10/2026
- Dòng 3: ## Bằng chứng và nguyên nhân trong mã
- Dòng 21: ## Thay đổi
- Dòng 31: ## Kết quả
- Dòng 56: ## Giới hạn và lỗi độc lập

## docs/cod-implementation-verification.md

Số dòng: 125
- Dòng 1: # Thu hộ COD và Đối soát COD — 17/10/2026
- Dòng 5: ## Luồng tiền thực tế
- Dòng 18: ## Trang và quyền
- Dòng 20: ### Thu hộ COD
- Dòng 29: ### Đối soát COD
- Dòng 40: ## API sử dụng và phần bổ sung
- Dòng 59: ## Ngày, số tiền và phạm vi tổng hợp
- Dòng 69: ## An toàn thao tác và giao diện
- Dòng 79: ## Tệp đã sửa
- Dòng 86: ## Kết quả chạy thực tế
- Dòng 117: ## Phần chưa có trong nghiệp vụ hiện tại

## docs/cod-ui-refinement-verification.md

Số dòng: 34
- Dòng 1: # Tinh chỉnh giao diện COD — 17/10/2026
- Dòng 5: ## Các thay đổi
- Dòng 16: ## Tệp thay đổi
- Dòng 24: ## Kiểm chứng

## docs/customer-detail-sql-verification.md

Số dòng: 30
- Dòng 1: # CustomerDetailController — lỗi SQL ngày 09/10/2026

## docs/customer-versions.md

Số dòng: 105
- Dòng 1: # Phiên bản khách hàng và địa chỉ
- Dòng 3: ## Hành vi
- Dòng 40: ## Migration và triển khai
- Dòng 57: # Chỉ kiểm tra database/schema hiệu lực:
- Dòng 59: # Chỉ áp dụng khi đúng database đã kiểm tra:
- Dòng 68: ## Kết quả kiểm chứng
- Dòng 93: ## File thay đổi

## docs/customers-implementation-verification.md

Số dòng: 73
- Dòng 1: # Triển khai trang Khách hàng — 10/10/2026
- Dòng 5: ## File sản phẩm
- Dòng 17: ## API sử dụng
- Dòng 39: ## Kiểm tra đã chạy
- Dòng 58: ## Giới hạn còn lại
- Dòng 67: # Từ backend/LastMile/LastMile.Api
- Dòng 69: # Từ thư mục last-mile-logistics

## docs/dashboard-implementation.md

Số dòng: 41
- Dòng 1: # Tổng quan TVD Logistics — bố cục thẻ chỉ số
- Dòng 5: ## Giao diện hiện tại
- Dòng 14: ## Số liệu và API
- Dòng 29: ## File khôi phục và kiểm tra

## docs/delivery-failure-commit.md

Số dòng: 53
- Dòng 1: # Ảnh giao thất bại và kết quả commit
- Dòng 13: ## Transaction lồng nhau
- Dòng 23: ## Kiểm tra ảnh
- Dòng 31: ## Kiểm tra đã chạy
- Dòng 49: ## Chưa kiểm tra

## docs/dispatch-implementation.md

Số dòng: 152
- Dòng 1: # Điều phối TVĐ Logistics — 17/10/2026
- Dòng 3: ## Kết quả triển khai
- Dòng 13: ## Những phần đã kiểm tra trước khi thay đổi
- Dòng 20: ## Thuật toán và nguồn mạng đường
- Dòng 42: # Hoặc cùng định dạng dữ liệu được cung cấp độc lập:
- Dòng 56: ## Ràng buộc và xác nhận
- Dòng 66: ## API
- Dòng 92: ## Cài đặt trên database hiện có
- Dòng 118: # Terminal khác:
- Dòng 126: ## Tệp thay đổi
- Dòng 134: ## Kiểm tra và bằng chứng
- Dòng 144: # Một lần ở môi trường chưa restore project test (không thêm package ngoài):

## docs/dispatch-queue-verification.md

Số dòng: 58
- Dòng 1: # Kiểm tra sửa Hàng chờ điều phối — 17/10/2026
- Dòng 3: ## Lỗi gốc và thay đổi
- Dòng 14: ## Nút và thao tác đã kiểm tra
- Dòng 34: ## Môi trường và bằng chứng
- Dòng 44: ## File sửa
- Dòng 54: ## Còn bị chặn trong dữ liệu vận hành

## docs/evidence-image-validation.md

Số dòng: 51
- Dòng 1: # Kiểm tra ảnh bằng chứng giao hàng
- Dòng 5: ## Thay đổi
- Dòng 23: ## File đã thay đổi
- Dòng 33: ## Lệnh kiểm tra

## docs/fleet-profile-versions.md

Số dòng: 53
- Dòng 1: # Phiên bản hồ sơ shipper và phương tiện
- Dòng 5: ## Migration bắt buộc trước khi triển khai
- Dòng 11: ## Hợp đồng API
- Dòng 23: ## Form và xử lý xung đột
- Dòng 29: ## Kiểm tra đã chạy
- Dòng 48: ## File thay đổi

## docs/hash-routing-verification.md

Số dòng: 87
- Dòng 1: # Hash routing — kiểm tra ngày 09/10/2026
- Dòng 3: ## Hướng dẫn và phạm vi
- Dòng 13: ## Danh sách màn hình
- Dòng 50: ## Query và lịch sử
- Dòng 62: ## Kiểm thử
- Dòng 81: ## Giới hạn

## docs/inbound-ui-verification.md

Số dòng: 60
- Dòng 1: # Nhập kho — kiểm tra ngày 09/10/2026
- Dòng 3: ## Đối chiếu và thay đổi
- Dòng 13: ## Bảng kiểm tra
- Dòng 35: ## Môi trường và bằng chứng
- Dòng 51: ## Phần chưa kiểm thử thực tế

## docs/inventory-ui-verification.md

Số dòng: 41
- Dòng 1: # Tồn kho — kiểm tra ngày 08/10/2026
- Dòng 3: ## Thay đổi
- Dòng 13: ## Môi trường và kết quả
- Dòng 39: ## Giới hạn

## docs/license-vietnam-date.md

Số dòng: 82
- Dòng 1: # Hạn bằng lái theo ngày Việt Nam
- Dòng 5: ## Quy tắc và triển khai
- Dòng 19: ## File đã sửa
- Dòng 47: ## Kết quả kiểm chứng thực tế
- Dòng 80: ## Giới hạn

## docs/locations-ui-verification.md

Số dòng: 58
- Dòng 1: # Vị trí lưu kho — cập nhật 09/10/2026
- Dòng 3: ## File thay đổi
- Dòng 13: ## API sử dụng/bổ sung
- Dòng 34: ## Quyền và nghiệp vụ
- Dòng 40: ## Kiểm tra đã chạy
- Dòng 54: ## Giới hạn và nạp thay đổi

## docs/login-lockout.md

Số dòng: 105
- Dòng 1: # Chống đăng nhập sai liên tục
- Dòng 3: ## Cấu hình
- Dòng 26: ## Luồng xử lý
- Dòng 64: ## Kiểm chứng thực tế ngày 19/10/2026
- Dòng 87: ## Kiểm tra trên giao diện

## docs/nuget-pkcs-update.md

Số dòng: 71
- Dòng 1: # Vá dependency Pkcs — 19/10/2026
- Dòng 3: ## Truy vết và quyết định
- Dòng 22: ## Advisory đã đọc
- Dòng 36: ## Kiểm chứng thực tế
- Dòng 47: ## Evidence.Tests được điều tra riêng
- Dòng 67: ## Áp dụng và giới hạn

## docs/order-detail-ui-verification.md

Số dòng: 72
- Dòng 1: # Chi tiết đơn và layout dùng chung — 09/10/2026
- Dòng 3: ## Phạm vi và nguyên nhân xác minh
- Dòng 17: ## Thay đổi
- Dòng 29: ## Kiểm tra đã chạy
- Dòng 51: ## Dữ liệu và giới hạn kiểm thử
- Dòng 66: ## File thay đổi

## docs/order-edit-ui-verification.md

Số dòng: 38
- Dòng 1: # Cập nhật API sửa từ chi tiết đơn — 09/10/2026
- Dòng 3: ## Contract hiện tại
- Dòng 9: ## File sửa
- Dòng 18: ## Kiểm tra
- Dòng 30: ## Đối chiếu ảnh lỗi của đơn 16

## docs/order-unsaved.md

Số dòng: 41
- Dòng 1: # Cảnh báo nội dung đơn hàng chưa lưu
- Dòng 5: ## Hành vi
- Dòng 17: ## Kiểm tra đã chạy ngày 19/10/2026
- Dòng 31: ## Cách kiểm tra bằng giao diện
- Dòng 39: ## Giới hạn kiểm chứng

## docs/orders-api-gaps.md

Số dòng: 55
- Dòng 1: # Quản lý đơn hàng — thiếu sót API và kiểm thử (07/10/2026)
- Dòng 7: ## Chi tiết thiếu version và ID phục vụ sửa
- Dòng 27: ## Quyền đọc form không khớp quyền sửa
- Dòng 33: ## API quyền hiện hành còn thiếu
- Dòng 41: ## Khung đăng nhập và CORS
- Dòng 45: ## Kiểm thử và giới hạn

## docs/outbound-ui-verification.md

Số dòng: 36
- Dòng 1: # Xuất kho / bàn giao — kiểm tra ngày 09/10/2026
- Dòng 3: ## Thay đổi
- Dòng 13: ## Lỗi đã xác minh trước sửa
- Dòng 17: ## Kết quả kiểm tra
- Dòng 29: ## Chưa kiểm thử thực tế

## docs/reports-implementation-verification.md

Số dòng: 114
- Dòng 1: # Trang Báo cáo — 17/10/2026
- Dòng 7: ## Tệp triển khai
- Dòng 18: ## API
- Dòng 37: ## Định nghĩa chỉ số
- Dòng 39: ### Đơn hàng
- Dòng 55: ### Hiệu suất giao hàng
- Dòng 67: ### Cước phí và COD
- Dòng 84: ## CSV và trạng thái giao diện
- Dòng 92: ## Kiểm tra đã chạy
- Dòng 108: ## Giới hạn còn lại

## docs/reports-ui-refinement-verification.md

Số dòng: 68
- Dòng 1: # Giao diện Báo cáo thu gọn — 17/10/2026
- Dòng 5: ## Tệp đã sửa
- Dòng 21: ## Thay đổi người dùng nhìn thấy
- Dòng 36: ## Kiểm tra thực tế
- Dòng 50: ## Bằng chứng

## docs/return-ui-verification.md

Số dòng: 44
- Dòng 1: # Nhập hàng hoàn — cập nhật ngày 09/10/2026
- Dòng 3: ## File đã sửa
- Dòng 11: ## API và điều kiện
- Dòng 32: ## Kết quả
- Dòng 42: ## Giới hạn kiểm thử

## docs/shipper-deactivation-license.md

Số dòng: 33
- Dòng 1: # Ngừng hoạt động shipper và bằng lái lịch sử
- Dòng 18: ## Kiểm tra

## docs/shippers-implementation-verification.md

Số dòng: 84
- Dòng 1: # Trang Nhân viên giao hàng — 10/10/2026
- Dòng 5: ## File sản phẩm sửa/bổ sung
- Dòng 21: ## API dùng
- Dòng 49: ## Kiểm tra đã chạy
- Dòng 67: ## Phần chưa thực hiện/kiểm tra
- Dòng 73: ## Chạy lại
- Dòng 76: # Từ backend/LastMile/LastMile.Api
- Dòng 78: # Từ thư mục last-mile-logistics
- Dòng 80: # Từ frontend

## docs/sql-results.md

Số dòng: 78
- Dòng 1: # Kiểm tra contract kết quả SQL của đơn hàng và kho
- Dòng 5: ## Contract đã đối chiếu
- Dòng 22: ## Xử lý mới
- Dòng 44: ## File thay đổi
- Dòng 53: ## Kiểm tra thực tế
- Dòng 76: ## Giới hạn kiểm chứng

## docs/tracking-implementation-verification.md

Số dòng: 66
- Dòng 1: # Theo dõi giao hàng — 17/10/2026
- Dòng 5: ## API và phạm vi quyền
- Dòng 28: ## Giao diện và cập nhật
- Dòng 37: ## Bản đồ
- Dòng 45: ## Tệp thay đổi
- Dòng 54: ## Kiểm tra
- Dòng 64: ## Giới hạn hiện có

## docs/tracking-ui-refinement.md

Số dòng: 40
- Dòng 1: # Cập nhật giao diện Theo dõi giao hàng — 17/10/2026
- Dòng 3: ## Thay đổi
- Dòng 16: ## Kiểm tra thực tế

## docs/transactions-ui-verification.md

Số dòng: 48
- Dòng 1: # Lịch sử giao dịch kho — cập nhật 09/10/2026
- Dòng 3: ## File đã sửa
- Dòng 12: ## API
- Dòng 27: ## Thời gian
- Dòng 33: ## Kiểm tra đã chạy
- Dòng 44: ## Giới hạn

## docs/unknown-write-outcomes.md

Số dòng: 38
- Dòng 1: # Kết quả ghi chưa xác định
- Dòng 25: ## Phần backend còn thiếu
- Dòng 36: ## Kiểm tra

## docs/vehicle-capacity-configuration.md

Số dòng: 48
- Dòng 1: # Thông số phương tiện tự hiển thị theo loại — 10/10/2026
- Dòng 15: ## Form thêm/sửa
- Dòng 22: ## API
- Dòng 31: ## Kết quả thực chạy
- Dòng 40: ## File sửa trong lượt này

## docs/vehicle-picker.md

Số dòng: 66
- Dòng 1: # Chọn phương tiện để gán/đổi xe cho shipper
- Dòng 5: ## Hành vi mới
- Dòng 15: ## API và phạm vi bưu cục
- Dòng 28: ## Nguyên nhân thực tế của danh sách rỗng
- Dòng 34: ## File đã sửa
- Dòng 44: ## Kiểm tra thực tế ngày 19/10/2026

## docs/vehicles-implementation-verification.md

Số dòng: 94
- Dòng 1: # Trang Phương tiện — 10/10/2026
- Dòng 5: ## File sản phẩm
- Dòng 19: ## API sử dụng
- Dòng 39: ## DTO, trạng thái và quyền
- Dòng 55: ## Kiểm tra đã chạy
- Dòng 74: ## Giới hạn còn lại
- Dòng 80: ## Chạy lại
- Dòng 83: # Từ backend/LastMile/LastMile.Api, khi backend đang chạy giữ khóa bin
- Dòng 85: # Từ thư mục last-mile-logistics
- Dòng 90: # Từ frontend

## docs/version-schema-runtime.md

Số dòng: 92
- Dòng 1: # Chẩn đoán runtime: Invalid column name 'PhienBan'
- Dòng 3: ## Nguyên nhân đã xác nhận bằng SQL Server
- Dòng 22: ## Controller và câu SQL lỗi
- Dòng 35: ### Kiểm tra riêng bảng tạm và CTE
- Dòng 56: ## Bước người vận hành cần thực hiện
- Dòng 74: ## Công cụ và kết quả kiểm tra

## docs/vrp-delivery-windows.md

Số dòng: 72
- Dòng 1: # Khung giờ bắt đầu giao trong VRP — 19/10/2026
- Dòng 5: ## Quy tắc đã triển khai
- Dòng 23: ## Dữ liệu, snapshot và tương thích
- Dòng 35: ## File thay đổi
- Dòng 49: ## Kiểm tra đã chạy
- Dòng 70: ## Phần chưa kiểm chứng

## docs/warehouse-api-gaps.md

Số dòng: 103
- Dòng 1: # Quản lý kho — contract, thiếu sót và kiểm tra (cập nhật 08/10/2026)
- Dòng 5: ## Contract đã đối chiếu controller
- Dòng 66: ## 1. ready-for-dispatch đã nối ngày 08/10/2026
- Dòng 72: ## 2. Danh sách yêu cầu hoàn đã bổ sung
- Dòng 80: ## 3. API quyền cá nhân đã bổ sung ngày 08/10/2026
- Dòng 88: ## 4. Điều kiện outbound và kích thước hàng
- Dòng 94: ## Lịch sử kiểm tra trước cập nhật 08/10/2026

## docs/warehouse-depot.md

Số dòng: 103
- Dòng 1: # Đọc tọa độ xuất phát theo kho được chọn
- Dòng 3: ## Dữ liệu đã đối chiếu (19/10/2026)
- Dòng 33: ## Luồng sau sửa
- Dòng 55: ## File sửa trong lần này
- Dòng 82: ## Kiểm chứng

## docs/warehouse-list-response-fix.md

Số dòng: 67
- Dòng 1: # Sửa response danh sách Kho — 07/10/2026
- Dòng 3: ## Nguyên nhân đã tái hiện
- Dòng 29: ## Nhập hoàn
- Dòng 41: ## ready-for-dispatch
- Dòng 45: ## Kiểm tra đã thực hiện

## frontend/assets/css/dashboard.css

Số dòng: 76

## frontend/assets/css/dispatch.css

Số dòng: 137

## frontend/assets/css/styles.css

Số dòng: 967

## frontend/assets/css/tracking.css

Số dòng: 140

## frontend/assets/vendor/leaflet/leaflet.css

Số dòng: 661

## frontend/assets/vendor/leaflet/leaflet.js

Số dòng: 6

## frontend/dev-server.cjs

Số dòng: 145

## frontend/index.html

Số dòng: 188

## frontend/js/accounts.js

Số dòng: 310
- Dòng 9: const can = (s, code) => s.permissions?.known && s.permissions.codes.has(code);
- Dòng 11: const read = (s, path, signal = s.abort.signal) => window.ApiClient.request(path, {signal});
- Dòng 14: function actions(...nodes) { const n = el("div", "account-actions"); n.append(...nodes); return n; }
- Dòng 15: function link(label, href) { const n = el("a", "btn btn-outline-orange btn-sm", label); n.href = href; return n; }
- Dòng 16: function alert(box, message, tone = "danger") {
- Dòng 20: function failure(s, box, error, retry) {
- Dòng 25: function status(c) {
- Dòng 31: function select(items, value) {
- Dòng 36: function field(form, fields, key, label, value, config = {}) {
- Dòng 57: function invalid(fields, key, message) {
- Dòng 61: function clearErrors(fields) {
- Dòng 64: function validate(fields) {
- Dòng 79: function serverErrors(fields, error) {
- Dòng 85: function dialog(s, title) {
- Dòng 103: function save(s, d, form, fields, path, method, build, reload, label = "Lưu") {
- Dòng 132: async function lookups(s, signal) {
- Dòng 137: async function editor(s, id) {
- Dòng 140: async function load() {
- Dòng 163: function rules() {
- Dòng 188: async function accountAction(s, id, action) {
- Dòng 191: async function load() {
- Dòng 205: async function resetPassword(s, id) {
- Dòng 208: async function load() {
- Dòng 224: function rowActions(s, c, detail = false) {
- Dòng 237: async function list(s) {
- Dòng 256: async function mountList(s) {
- Dòng 275: async function loadOptions() {
- Dòng 284: async function detail(s) {
- Dòng 297: function refresh(s) { return s.route.mode === "detail" ? detail(s) : list(s); }
- Dòng 298: function destroy() {
- Dòng 301: function mount(container, user, route, context) {

## frontend/js/admin-ui.js

Số dòng: 53
- Dòng 6: function actions(...nodes) { const n=el("div","admin-actions");n.append(...nodes);return n; }
- Dòng 7: function link(label,href) { const n=el("a","btn btn-outline-orange btn-sm",label);n.href=href;return n; }
- Dòng 8: function notice(box,message,tone="danger") { box.replaceChildren();if(message){const n=el("div","alert alert-"+tone,message);n.setAttribute("role",tone==="success"?"status":"alert");box.append(n);} }
- Dòng 9: function failure(s,box,error,retry) { if(!s.alive()||error.name==="AbortError"||error.sessionExpired)return;notice(box,(error.status===403?"Không có quyền. ":"")+error.message);if(retry&&![403,404].includes(error.status)
- Dòng 10: function state(container,user,route,context) {
- Dòng 21: function select(items,value) { const n=el("select","form-select");for(const [v,label,disabled] of items){const o=el("option","",label);o.value=v;o.disabled=!!disabled;n.append(o);}n.value=value??"";return n; }
- Dòng 22: function field(form,fields,key,label,value,config={}) {
- Dòng 31: function invalid(fields,key,message) {const f=fields[key];if(f){f.control.classList.add("is-invalid");f.control.setAttribute("aria-invalid","true");f.error.textContent=message;}}
- Dòng 32: function validate(fields) {for(const [key,f] of Object.entries(fields)){f.control.classList.remove("is-invalid");f.control.removeAttribute("aria-invalid");f.error.textContent="";if(f.control.disabled)continue;if(f.contro
- Dòng 33: function dialog(s,title) {
- Dòng 40: function save(s,d,form,fields,path,method,build,done,label="Lưu") {
- Dòng 49: function request(s) {s.pending?.abort();s.pending=new AbortController();return {epoch:++s.epoch,signal:AbortSignal.any([s.abort.signal,s.pending.signal])};}
- Dòng 50: function badge(active){return el("span","badge "+(active?"text-bg-success":"text-bg-secondary"),active?"Đang sử dụng":"Ngừng sử dụng");}
- Dòng 51: function pager(box,data,change) {const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize)),prev=button("‹ Trước",()=>change({page:data.page-1})),next=button("Sau ›",()=>change({page:data.page+1}));prev.disabled=da

## frontend/js/api.js

Số dòng: 276
- Dòng 11: function tokenText(value, access) {
- Dòng 18: function jwtExpiry(token) {
- Dòng 25: function getSession() {
- Dòng 46: function getAccessToken() { return getSession()?.accessToken || null; }
- Dòng 47: function getRefreshToken() { return getSession()?.refreshToken || null; }
- Dòng 49: function saveSession(tokens) {
- Dòng 66: function storeTokens(tokens) {
- Dòng 71: function clearTokens() {
- Dòng 78: async function readResponse(response) {
- Dòng 84: async function sendRequest(url, settings, headers) {
- Dòng 96: const cancel = () => abort("cancel");
- Dòng 146: async function request(path, options, allowRefresh) {
- Dòng 217: function validatePage(data, path, idFields) {
- Dòng 232: async function refreshTokens() {

## frontend/js/app.js

Số dòng: 240
- Dòng 12: function icon(name) { const node = UI.el("i", "bi " + name); node.setAttribute("aria-hidden", "true"); return node; }
- Dòng 13: function appendLink(container, page, nested) {
- Dòng 18: function buildNavigation(permissions) {
- Dòng 32: function updateNavigation(route) {
- Dòng 42: function setupUser(user) {
- Dòng 55: function forgetUser() {
- Dòng 64: function closeSidebar() {
- Dòng 85: function leavePage() { window.DashboardPage.destroy(); window.DispatchPage.destroy(); window.TrackingPage.destroy(); window.CodPage.destroy(); window.ReportsPage.destroy(); window.AuditPage.destroy(); window.PricingPage.
- Dòng 86: function showLogin() {
- Dòng 90: function showShell(route) {
- Dòng 120: function showError(route, title, message, retry = false) {
- Dòng 127: function showLoading(route) { showShell(route); pageContent.replaceChildren(UI.el("p", "orders-empty", "Đang mở trang…")); }
- Dòng 128: function renderRoute(route, context) {
- Dòng 161: function setLoading(value) {
- Dòng 165: async function acceptUser(user) {
- Dòng 204: async function signOut() {
- Dòng 219: async function restoreUser() {

## frontend/js/audit.js

Số dòng: 11
- Dòng 4: function formatData(value,invalid=false){if(invalid)return "Dữ liệu JSON không hợp lệ; backend không trả nội dung gốc.";if(value==null)return "Không có dữ liệu.";try{return JSON.stringify(typeof value==="string"?JSON.par
- Dòng 5: function destroy(){active?.destroy();active=null;}
- Dòng 6: async function detail(s,id){const d=U.dialog(s,"Chi tiết nhật ký #"+id);if(!d)return;const close=d.close;d.close=()=>{close();if(s.alive()&&!s.destroying&&s.route.mode==="detail")R.navigate(R.href("audit-logs",{},s.filte
- Dòng 7: async function list(s){const pending=U.request(s);R.updateQuery(s.filters,s.route);s.route=R.current()||s.route;s.root.replaceChildren(U.el("p","admin-empty","Đang tải nhật ký…"));try{const path="/api/v1/audit-logs?"+U.q
- Dòng 9: function mount(container,user,route,context){destroy();active=U.state(container,user,route,context);active.filters={page:route.query.page||1,pageSize:route.query.pageSize||10,...Object.fromEntries(["from","to","accountId

## frontend/js/auth.js

Số dòng: 62
- Dòng 6: async function login(username, password) {
- Dòng 16: async function getCurrentUser() {
- Dòng 20: async function getPermissions(user, signal) {
- Dòng 27: async function logout() {
- Dòng 42: function rememberedUsername() {
- Dòng 46: function rememberUsername(username, remember) {

## frontend/js/catalogs.js

Số dòng: 26
- Dòng 4: function destroy(){if(active?.locationChild)window.LocationsPage.destroy();active?.destroy();active=null;}
- Dòng 5: const name=(rows,id)=>id==null?"—":rows.find(r=>r.id===id)?.name||"#"+id;
- Dòng 6: function editable(s,type){return s.can(type==="SERVICES"?"BANGGIA_QUANLY":"BUUCUC_QUANLY");}
- Dòng 7: async function editor(s,type,id){if(!editable(s,type))return;const d=U.dialog(s,(id?"Sửa ":"Thêm ")+types[type].toLocaleLowerCase("vi"));if(!d)return;
- Dòng 8: async function load(){try{const data=await s.read("/api/v1/catalogs",d.signal),c=id?data[type.toLowerCase()].find(r=>r.id===id):null;if(id&&!c)throw Error("Danh mục không còn tồn tại. Hãy tải lại.");if(!s.alive()||d.clos
- Dòng 9: function relationship(key,label,rows,current,required=false,disabled=false){return U.field(form,f,key,label,current,{required,disabled,items:[["",required?"Chọn "+label.toLowerCase():"Không có"],...rows.filter(r=>r.id!==
- Dòng 17: async function toggle(s,type,c){const d=U.dialog(s,c.isActive?"Ngừng sử dụng":"Kích hoạt lại");if(!d)return;try{const data=await s.read("/api/v1/catalogs?type="+type,d.signal),current=data[type.toLowerCase()].find(r=>r.i
- Dòng 18: async function render(s){const pending=U.request(s),q=s.route.query,type=q.type||"AREAS",tabs=U.actions(...Object.entries(types).map(([id,label])=>{const n=U.link(label,R.href("catalogs",{},{type:id}));n.classList.toggle
- Dòng 24: function mount(container,user,route,context){destroy();active=U.state(container,user,route,context);render(active);}

## frontend/js/cod.js

Số dòng: 124
- Dòng 8: const today=()=>new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Ho_Chi_Minh",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
- Dòng 10: function dateRange(from,to){
- Dòng 15: function cents(value){const text=String(value).trim().replace(",",".");if(!/^\d{1,16}(?:\.\d{1,2})?$/.test(text))throw Error("Số tiền phải là số không âm, tối đa 2 chữ số thập phân.");const [a,b=""]=text.split(".");retur
- Dòng 17: function depositJson(payload){return JSON.stringify({...payload,items:undefined}).slice(0,-1)+',"items":['+payload.items.map(x=>JSON.stringify({orderId:x.orderId}).slice(0,-1)+',"amount":'+amountText(cents(x.amount))+'}'
- Dòng 18: function badge(status){const n=el("span","cod-badge cod-"+status,labels[status]||status||"—");return n;}
- Dòng 19: function info(pairs){const dl=el("dl","cod-summary");for(const[label,value]of pairs){const item=el("div",typeof value==="string"&&value.endsWith(" ₫")?"cod-money-pair":""),dd=el("dd");dd.append(value instanceof Node?valu
- Dòng 20: function section(title,...nodes){const n=el("section","cod-detail-section");n.append(el("h3","",title),...nodes);return n;}
- Dòng 21: function table(headers,rows,numeric=[],variant=""){const wrap=el("div","cod-table-wrap"),t=el("table","table cod-table align-middle"+(variant?" cod-list-table cod-table-"+variant:"")),h=el("thead"),tr=el("tr"),b=el("tbod
- Dòng 22: async function copyText(text){
- Dòng 26: function orderCell(s,row){const n=el("div","cod-order"),track=el("div","cod-tracking"),code=el("span","",row.trackingNumber||"—");code.title=row.trackingNumber||"";track.append(code);if(row.trackingNumber){const copy=but
- Dòng 27: function periodCell(row){const n=el("div","cod-period-cell");n.title="Giờ Việt Nam. Mốc đến "+date(row.periodTo)+" không thuộc kỳ đối soát.";n.append(el("span","","Từ "+date(row.periodFrom).split(",")[0]),el("span","","Đ
- Dòng 28: function sessionMoney(row){const n=el("div","cod-session-money");for(const [label,value]of [["Đã thu",row.totalCollected],["Đã nộp",row.totalDeposited]]){const line=el("div");line.append(el("span","",label),el("strong","
- Dòng 29: function controls(...nodes){const n=el("div","cod-actions");n.append(...nodes);return n;}
- Dòng 30: function pager(data,change){const p=el("div","cod-pager"),actions=controls(),pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize)),first=data.totalItems?(data.page-1)*data.pageSize+1:0;p.append(el("span","text-secon
- Dòng 31: function kind(s){return s.route.pageId==="cod-reconciliation"?"reconciliations":s.filters.tab||"collections";}
- Dòng 32: function listName(s){return s.route.pageId==="cod-reconciliation"?"cod-reconciliation":"cod-collections";}
- Dòng 33: function detailName(type){return {collections:"cod-collection-detail",deposits:"cod-deposit-detail",reconciliations:"cod-reconciliation-detail"}[type];}
- Dòng 34: function linkOrder(s,row){if(!s.can("DONHANG_XEM"))return row.orderCode;const a=el("a","cod-order-link",row.orderCode);a.href=R.href("order-detail",{id:row.orderId},{returnTo:R.href(listName(s),{},s.confirmed||s.filters)
- Dòng 35: function rowLink(s,type,id){return U.link("Chi tiết",R.href(detailName(type),{id},{...(s.confirmed||s.filters),...(type==="deposits"?{tab:"deposits"}:{})}));}
- Dòng 36: function path(s,exporting=false){return "/api/v1/cod/"+kind(s)+"?"+U.query({...dateRange(s.filters.from,s.filters.to),branchId:s.filters.branchId,shipperId:s.filters.shipperId,status:s.filters.status,keyword:s.filters.ke
- Dòng 37: function method(s){const k=kind(s);return k==="collections"?"Lọc theo ngày thu (giờ Việt Nam). Tiền nộp/xác nhận là phân bổ hiện tại của chính các khoản thu đang lọc, kể cả phiếu nộp ở kỳ khác. Còn phải nộp = thực thu − 
- Dòng 40: function formField(form,fields,key,label,value,config={}){return U.field(form,fields,key,label,value,config);}
- Dòng 41: function shipperItems(s,branchId,operating=false){return [["","Tất cả shipper"],...s.options.shippers.filter(n=>(!branchId||String(n.branchId)===String(branchId)||!operating)&&(!operating||n.canOperate)).map(n=>[n.id,n.n
- Dòng 42: function shell(s){
- Dòng 52: const mark=()=>{updateCount();s.draft++;s.exportButton&&(s.exportButton.disabled=true);s.feedback.replaceChildren(el("p","cod-draft","Bộ lọc đã thay đổi. Chọn Áp dụng để xem kết quả mới."));};f.addEventListener("input",m
- Dòng 58: function draftChanged(s){return ["from","to","branchId","shipperId","status","keyword"].some(k=>String(s.fields[k].control.value)!==String((s.confirmed||s.filters)[k]||""));}
- Dòng 59: function summary(s,data){
- Dòng 76: async function csv(s){const snapshot={...s.confirmed},epoch=s.epoch,draft=s.draft;s.exportButton.disabled=true;try{s.exportAbort?.abort();s.exportAbort=new AbortController();const data=window.ApiClient.validatePage(await
- Dòng 82: function render(s,data){
- Dòng 92: async function load(s){const req=U.request(s),filters={...s.filters},draft=s.draft;s.exportAbort?.abort();s.results.setAttribute("aria-busy","true");s.results.replaceChildren(el("p","cod-empty","Đang tải giao dịch COD…")
- Dòng 93: function dialog(s,title){const d=U.dialog(s,title);if(d){d.node.classList.add("cod-modal");}return d;}
- Dòng 94: function errorBox(s,d,box,error,reload){U.failure(s,box,error);if(error.status===409&&reload)box.append(button("Tải lại dữ liệu",reload,"btn btn-outline-orange btn-sm"));}
- Dòng 95: async function submit(s,d,box,path,body,done,reload){if(d.busy||d.writeUnknown)return;const states=[...d.body.querySelectorAll("input,select,textarea,button")].map(n=>[n,n.disabled]);states.forEach(([n])=>n.disabled=true
- Dòng 96: async function detail(s,id,k){const d=dialog(s,k==="collections"?"Chi tiết khoản thu":k==="deposits"?"Chi tiết phiếu nộp tiền":"Chi tiết phiên đối soát");if(!d)return;const close=d.close;d.close=()=>{close();if(s.alive()
- Dòng 110: function editorFields(s,d){const f=el("form","cod-editor"),fields={};formField(f,fields,"branchId","Bưu cục",s.confirmed?.branchId||s.options.branches[0]?.id,{items:s.options.branches.filter(b=>b.isActive).map(b=>[b.id,b
- Dòng 111: function createRecon(s){const d=dialog(s,"Tạo phiên đối soát với shipper");if(!d)return;const{form,fields}=editorFields(s,d),notes=el("textarea","form-control"),out=el("div","cod-preview"),box=el("div"),footer=el("div","
- Dòng 112: async function read(page){if(!filter)return;abort?.abort();abort=new AbortController();const current=++epoch;out.replaceChildren(el("p","cod-muted","Đang kiểm tra toàn bộ khoản thu trong kỳ…"));save.disabled=true;agree.c
- Dòng 114: function createDeposit(s){const d=dialog(s,"Lập phiếu nộp COD");if(!d)return;const{form,fields}=editorFields(s,d),out=el("div","cod-preview"),box=el("div"),picked=new Map(),review=el("div","cod-review"),foot=el("div","co
- Dòng 115: function selectedTotal(){try{return[...picked.values()].reduce((a,r)=>a+cents(r.amount),0n);}catch{return null;}}
- Dòng 116: function update(){const n=selectedTotal();total.textContent="Đã chọn "+picked.size+" khoản qua các trang · Tổng "+(n===null?"chưa hợp lệ":money(Number(amountText(n))))+". Chỉ các khoản đã tích chọn được đưa vào phiếu.";n
- Dòng 117: function payload(){try{if(!picked.size||picked.size>100)throw Error("Chọn từ 1 đến 100 khoản cho một phiếu.");const items=[...picked.values()].map(r=>{const n=cents(r.amount);if(n<=0n||n>cents(r.availableForDeposit))thro
- Dòng 118: function showReview(){if(d.writeUnknown||!payload())return;U.notice(box,"");const shipper=s.options.shippers.find(n=>String(n.id)===filter.shipperId),branch=s.options.branches.find(b=>String(b.id)===filter.branchId),agre
- Dòng 119: async function read(page,reset=false){if(!filter)return;if(reset){picked.clear();update();}abort?.abort();abort=new AbortController();const current=++epoch;out.replaceChildren(el("p","cod-muted","Đang tải khoản thu…"));t
- Dòng 121: function destroy(){active?.headingActions?.remove();active?.destroy();active=null;}
- Dòng 122: async function mount(container,user,route,context){destroy();const s=active=U.state(container,user,route,context);const cleanup=s.destroy;s.destroy=()=>{s.headingActions?.remove();cleanup();};s.root.className="cod-page";

## frontend/js/config.js

Số dòng: 5

## frontend/js/customers.js

Số dòng: 293
- Dòng 8: const can = (s, code) => s.permissions?.known === true && s.permissions.codes.has(code);
- Dòng 9: const read = (s, path, signal) => window.ApiClient.request(path, { signal: signal || s.abort.signal });
- Dòng 10: function alert(box, message, tone = "danger") {
- Dòng 14: function status(value) { return el("span", "badge " + (value ? "text-bg-success" : "text-bg-secondary"), value ? "Đang sử dụng" : "Ngừng sử dụng"); }
- Dòng 15: function select(items, value) {
- Dòng 20: function link(label, href) { const node = el("a", "btn btn-outline-orange btn-sm", label); node.href = href; return node; }
- Dòng 21: function actions(...nodes) { const box = el("div", "customer-actions"); box.append(...nodes); return box; }
- Dòng 22: function failure(s, box, error, retry) {
- Dòng 28: function customerPayload(c) { return { fullName: c.fullName, phone: c.phone, email: c.email || null, type: c.type, isActive: c.isActive }; }
- Dòng 29: function addressPayload(a) {
- Dòng 33: function dialog(s, title) {
- Dòng 38: const abort = () => controller.abort(); s.abort.signal.addEventListener("abort", abort, { once: true });
- Dòng 51: function formField(form, fields, key, label, value, config = {}) {
- Dòng 67: function fieldError(fields, key, message) {
- Dòng 71: function clearErrors(fields) { for (const f of Object.values(fields)) { f.control.classList.remove("is-invalid"); f.control.removeAttribute("aria-invalid"); f.error.textContent = ""; } }
- Dòng 72: function values(fields) { return Object.fromEntries(Object.entries(fields).map(([key, {control}]) => [key, control.type === "checkbox" ? control.checked : control.value.trim()])); }
- Dòng 73: function validate(fields, isAddress) {
- Dòng 91: function serverErrors(fields, error) {
- Dòng 101: function saveForm(s, d, form, fields, isAddress, path, method, makePayload, reload) {
- Dòng 141: async function customerEditor(s, id, toggle = false) {
- Dòng 145: async function load(preserveForm = false) {
- Dòng 165: async function addressEditor(s, customerId, addressId, overrides = {}) {
- Dòng 169: async function load(preserveForm = false) {
- Dòng 207: function mountList(s) {
- Dòng 222: async function loadList(s) {
- Dòng 247: async function loadDetail(s) {
- Dòng 264: function showTab(isOrders) {addresses.hidden = isOrders; orders.hidden = !isOrders; aTab.classList.toggle("active", !isOrders); oTab.classList.toggle("active", isOrders); aTab.setAttribute("aria-selected", String(!isOrde
- Dòng 283: function refresh(s) { if (!alive(s)) return; return s.route.mode === "detail" ? loadDetail(s) : loadList(s); }
- Dòng 284: function destroy() { if (!active) return; active.dialog?.close(); active.abort.abort(); active.listAbort?.abort(); active = null; }
- Dòng 285: function mount(container, user, route, context) {

## frontend/js/dashboard.js

Số dòng: 112
- Dòng 15: function info(text){const n=el("span","dashboard-info","ⓘ");n.tabIndex=0;n.title=text;n.setAttribute("aria-label",text);return n;}
- Dòng 16: function link(label,href,cls="btn btn-outline-orange btn-sm"){const n=el("a",cls,label);n.href=href;return n;}
- Dòng 17: function destroy(){active?.destroy();active=null;}
- Dòng 18: function busy(box,text){box.setAttribute("aria-busy","true");box.replaceChildren(el("p","dashboard-message",text));}
- Dòng 19: function failed(s,box,error,retry){box.setAttribute("aria-busy","false");U.failure(s,box,error,retry);}
- Dòng 20: function today(utc){return new Date(Date.parse(utc)+7*3600000).toISOString().slice(0,10);}
- Dòng 21: function codeDialog(s,code){
- Dòng 25: function renderMetrics(s,data){
- Dòng 39: function renderTasks(s){
- Dòng 56: function renderDelivery(s,data){
- Dòng 67: function updateTime(s){const pending=Object.values(s.partStatus).some(v=>v==="loading"),errors=Object.values(s.partStatus).some(v=>v==="error");s.updated.textContent=(s.lastUpdated?"Cập nhật: "+timestamp(s.lastUpdated):"
- Dòng 68: async function loadPart(s,key,epoch){
- Dòng 83: async function load(s){
- Dòng 99: async function mount(container,user,route,context){
- Dòng 103: const change=()=>{s.query={branchId:s.selector.value};R.updateQuery(s.query,s.route);s.route=R.current();load(s);};s.selector.addEventListener("change",change);

## frontend/js/dispatch.js

Số dòng: 472
- Dòng 15: function link(label,href,cls="btn btn-outline-orange btn-sm"){const n=el("a",cls,label);n.href=href;return n;}
- Dòng 16: function badge(value,kind="trip"){return el("span","dispatch-badge",(kind==="trip"?tripLabels:assignmentLabels)[value]||UI.statuses?.[value]||value);}
- Dòng 17: function disable(node,condition,reason){node.disabled=!!condition;node.title=condition?reason:"";return node;}
- Dòng 18: function readDraft(){try{const value=JSON.parse(sessionStorage.getItem(storageKey));return value&&typeof value==="object"&&!Array.isArray(value)?value:{};}catch{return {};}}
- Dòng 19: function persist(s){checkInputs(s);try{sessionStorage.setItem(storageKey,JSON.stringify({...s.draft,ids:[...s.selected.keys()],planId:s.proposal?.id||s.draft.planId,proposalBinding:s.proposalBinding||null}));}catch{U.not
- Dòng 21: function planningKey(s){try{const r=requestFor(s);return JSON.stringify({...r,orderIds:r.orderIds.map(Number).sort((a,b)=>a-b),shipperIds:r.shipperIds.map(Number).sort((a,b)=>a-b)});}catch{return null;}}
- Dòng 22: function invalidateProposal(s){
- Dòng 27: function checkInputs(s){
- Dòng 34: function proposalIsCurrent(s){return !!s.proposal&&!!s.proposalBinding&&s.proposalBinding.id===s.proposal.id&&s.proposalBinding.key!==null&&s.proposalBinding.key===planningKey(s);}
- Dòng 35: function restoreProposal(s,p){
- Dòng 53: function freeMap(s){s.mapObserver?.disconnect();cancelAnimationFrame(s.mapFrame);s.map?.remove();s.map=null;}
- Dòng 54: function destroy(){active?.destroy();active=null;}
- Dòng 55: function sync(s,extra={}){s.query={...s.query,...extra};R.updateQuery(s.query,s.route);s.route=R.current()||s.route;}
- Dòng 56: function field(form,fields,key,label,value,config={}){U.field(form,fields,key,label,value,config);return fields[key].control;}
- Dòng 57: function rowCode(row){const n=el("div","dispatch-code");n.append(el("strong","",row.trackingNumber||row.tripCode),el("small","",row.orderCode||row.branchName||""));return n;}
- Dòng 58: function orderDetails(s,row){
- Dòng 74: function queueCode(s,row){const n=el("div","dispatch-code"),open=button(row.trackingNumber||row.orderCode,()=>orderDetails(s,row),"dispatch-code-button");open.title="Xem đầy đủ và sao chép: "+row.trackingNumber;open.setA
- Dòng 75: function deadlineCell(value){
- Dòng 81: function routeName(route,index){return "Tuyến "+letters[index]+" · "+route.shipperName;}
- Dòng 82: async function write(s,path,body,signal=s.abort.signal,timeoutMs){window.WriteOutcome.assertCanSend(s.dialog?.signal===signal?s.dialog:s,{path,payload:body});return window.ApiClient.request(path,{method:"POST",body:JSON.
- Dòng 83: function pager(s,host,data,load){host.replaceChildren();if(data.totalItems<=data.pageSize)return;const total=Math.ceil(data.totalItems/data.pageSize);host.append(disable(button("Trước",()=>{sync(s,{page:data.page-1});loa
- Dòng 84: function filters(s,host,kind,load){
- Dòng 95: function queueFilters(s,host,load){
- Dòng 105: const setWarehouses=(items,value)=>{const allowed=items.filter(n=>!branch.value||n.branchId===Number(branch.value));warehouse.replaceChildren(...U.select([["","Tất cả kho"],...allowed.map(n=>[n.id,n.name])],"").children)
- Dòng 106: function restoreFilters(){s.filterAbort?.abort();submit.disabled=false;warehouse.disabled=false;for(const [key,f]of Object.entries(fields))f.control.value=s.query[key]??"";setWarehouses(s.options.warehouses,s.query.wareh
- Dòng 117: function queryFor(s,keys){return Object.fromEntries(keys.filter(k=>s.query[k]!==undefined&&s.query[k]!=="").map(k=>[k,s.query[k]]));}
- Dòng 118: async function hydrate(s){
- Dòng 125: function selectionBar(s){
- Dòng 140: async function queue(s,host){
- Dòng 166: const select=(row,chosen)=>{
- Dòng 205: async function assignmentDialog(s,row,reassign=false){
- Dòng 217: function vehicles(previous){if(d.writeUnknown)return;const items=data.items.filter(n=>n.id===Number(driver.value));vehicle.replaceChildren(...U.select(items.map(n=>[n.vehicleId,n.licensePlate+" · Tải "+number(n.maxWeight
- Dòng 218: function candidates(){const previous=driver.value,items=[...new Map(data.items.map(n=>[n.id,n])).values()];driver.replaceChildren(...U.select([["","Chọn shipper"],...items.map(n=>[n.id,n.fullName])],"").children);driver.
- Dòng 231: function reasonDialog(s,title,path,payload={}){
- Dòng 235: function startListRequest(s,body,pages,message){
- Dòng 241: const current=()=>s.alive()&&!signal.aborted&&sequence===s.listSequence&&s.listAbort===controller;
- Dòng 245: async function assignments(s){
- Dòng 260: async function createTrip(s){
- Dòng 268: async function trips(s){
- Dòng 282: async function tripDetail(s,id){
- Dòng 298: function editTrip(s,trip){
- Dòng 304: function render(){list.replaceChildren(...ids.map((id,index)=>{const row=trip.orders.find(o=>o.orderId===id),item=el("li");item.append(el("span","",row.trackingNumber),disable(button("↑",()=>{[ids[index-1],ids[index]]=[i
- Dòng 309: function localValue(value){const d=new Date(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)?value:value+"Z");return new Date(d.getTime()+7*3600000).toISOString().slice(0,16);}
- Dòng 310: function localFuture(){return localValue(new Date(Date.now()+30*60000).toISOString());}
- Dòng 311: function steps(s,step){const nav=el("ol","dispatch-steps");for(const [n,label]of [[1,"Chọn đơn & kho"],[2,"Shipper & xuất phát"],[3,"Xem đề xuất"]]){const item=el("li",n===step?"is-current":""),b=button(n+". "+label,()=>
- Dòng 312: function depotIssue(w){
- Dòng 319: function capturePlanning(s){
- Dòng 323: async function loadDepot(s,warehouse,status,calculate){
- Dòng 326: const current=()=>s.alive()&&!controller.signal.aborted&&sequence===s.depotSequence&&status.isConnected&&Number(s.draft.warehouseId)===warehouse.id;
- Dòng 335: const disconnected=(detail.connectivity||[]).filter(n=>n.state==='DISCONNECTED');
- Dòng 342: async function wizard(s,step){
- Dòng 379: function howItWorks(){const detail=el("details","dispatch-how");detail.append(el("summary","","Cách tính"),el("p","","Dijkstra tìm đường ngắn nhất trên snapshot OpenStreetMap có hướng theo loại xe. Phương án nhiều xe dùn
- Dòng 380: function requestFor(s){return {warehouseId:Number(s.draft.warehouseId),orderIds:[...s.selected.keys()],shipperIds:[...(s.draft.shipperIds||[])],departureAt:new Date(s.draft.departure+"+07:00").toISOString(),serviceMinute
- Dòng 381: async function calculatePlan(s,control,manual=false){
- Dòng 391: function result(s){
- Dòng 420: function resultRefresh(s){freeMap(s);s.content.replaceChildren(steps(s,3));result(s);}
- Dòng 421: function editRoute(s,shipper,id,direction,target){
- Dòng 426: async function confirmPlan(s,control){
- Dòng 435: function drawMap(s,host,routes,depot,selected){
- Dòng 458: async function mount(container,user,route,context){

## frontend/js/inbound.js

Số dòng: 343
- Dòng 13: async function read(s, path, signal) {
- Dòng 16: function message(error) {
- Dòng 25: function validateLocations(rows, warehouseId) {
- Dòng 30: function syncRoute(s) {
- Dòng 34: function updateControls(s) {
- Dòng 50: function showPermission(s) {
- Dòng 53: function destroy() {
- Dòng 60: function mount(container, user, route, context) {
- Dòng 103: function applyFilters(s, resetPage) {
- Dòng 111: function emptyScope(s) {
- Dòng 116: async function loadCatalog(s, initial = false) {
- Dòng 142: async function chooseWarehouse(s, value, options = {}) {
- Dòng 155: async function loadLocations(s, scope = s.scope, wantedId = selectedLocation(s)?.id) {
- Dòng 173: async function loadOrders(s) {
- Dòng 203: function renderTable(s) {
- Dòng 215: async function openImport(s, row) {
- Dòng 248: function renderImport(s, view, context, scope) {
- Dòng 261: function payload() {
- Dòng 268: function resetReview() { if (s.pending) return; notes.setCustomValidity(""); location.setCustomValidity(""); reviewed = null; confirmation.classList.add("d-none"); review.classList.remove("d-none"); }
- Dòng 318: function renderUncertain(s) {
- Dòng 325: async function verifyAttempt(s, attempt) {

## frontend/js/locations.js

Số dòng: 259
- Dòng 10: function message(error) {
- Dòng 15: async function request(s, url, signal, options = {}) {
- Dòng 18: function validateRows(rows, warehouseId) {
- Dòng 23: function destroy() {
- Dòng 28: function update(s) {
- Dòng 36: function syncRoute(s) {
- Dòng 39: function mount(container, user, route, context) {
- Dòng 63: async function loadWarehouses(s, restore = false) {
- Dòng 83: async function chooseWarehouse(s, id, restore = false) {
- Dòng 93: async function reload(s) {
- Dòng 116: async function fresh(s, row, view, warehouse) {
- Dòng 122: async function locationRows(s, warehouseId, filters, signal) {
- Dòng 127: function payload(row, warehouseId, isActive) {
- Dòng 130: function fieldError(control, feedback, value) {
- Dòng 133: async function openEdit(s, row) {
- Dòng 153: function errorsFromBackend(error) {
- Dòng 197: async function openToggle(s, row) {
- Dòng 231: function openStock(s, row) {
- Dòng 238: async function load() {

## frontend/js/orders.js

Số dòng: 3254
- Dòng 67: function text(value) {
- Dòng 73: function money(value) {
- Dòng 79: function weight(value) {
- Dòng 85: function parseApiDate(value) {
- Dòng 98: function date(value) {
- Dòng 103: function toVietnamInput(value) {
- Dòng 116: function vietnamInputToIso(value) {
- Dòng 144: function sameSecond(left, right) {
- Dòng 155: function el(tag, className, value) {
- Dòng 164: function button(label, callback, className) {
- Dòng 178: function input(type, value, limits) {
- Dòng 188: function option(selectNode, value, label) {
- Dòng 194: function select(items, label, selected) {
- Dòng 208: function field(label, control, className) {
- Dòng 226: function notice(container, message, type) {
- Dòng 236: function badge(code, label) {
- Dòng 252: function table(headers, rows) {
- Dòng 300: function summary(pairs) {
- Dòng 312: function section(title, ...children) {
- Dòng 318: function pagination(container, page, pageSize, totalItems, onPage, noun) {
- Dòng 347: function permitted(s, action) {
- Dòng 359: function inScope(s, order) {
- Dòng 376: function missingEditFields(order) {
- Dòng 404: function needsAddressSelection(order) {
- Dòng 413: function missingEditMessage(missing) {
- Dòng 431: async function read(s, path, signal) {
- Dòng 439: function dialog(s, title, wide) {
- Dòng 457: function dispose() {
- Dòng 470: function closeDialog() {
- Dòng 511: function closeDialogs(s) {
- Dòng 518: function routeView(s, title, backHash) {
- Dòng 560: function navigateDetail(id, message, query = {}, replace = false) {
- Dòng 569: function orderQuery(s) {
- Dòng 575: function destroy() {
- Dòng 589: function mount(container, user, route, context) {
- Dòng 790: async function loadList(s) {
- Dòng 935: async function openDetail(s, id, message) {
- Dòng 940: async function reload() {
- Dòng 1001: function renderDetail(s, view, order, reload, message) {
- Dòng 1018: const actionButton = (label, callback, style) =>
- Dòng 1310: function customerPicker(
- Dòng 1382: function fillCustomers(items) {
- Dòng 1407: async function loadCustomers() {
- Dòng 1477: function showAddress() {
- Dòng 1489: async function loadAddresses(id, addressId, requireSelection = false) {
- Dòng 1659: async function openEditRoute(s, id) {
- Dòng 1705: async function openForm(s, existing) {
- Dòng 1874: function resetTimeValidity() {
- Dòng 1884: function deliveryTimeValues() {
- Dòng 1986: function clearQuote() {
- Dòng 1993: function totalWeight() {
- Dòng 2001: function updateWeight() {
- Dòng 2037: function addItem(item) {
- Dòng 2160: function renumber() {
- Dòng 2166: function payload() {
- Dòng 2227: function quotePayload() {
- Dòng 2406: function formSnapshot() {
- Dòng 2415: function hasUnsavedChanges() {
- Dòng 2418: function installFormGuard() {
- Dòng 2419: const leave = () => {
- Dòng 2535: function quoteSummary(result) {
- Dòng 2573: async function openQuote(s, order) {
- Dòng 2737: function openDeliverySchedule(s, order) {
- Dòng 2753: function reloadDetail() {
- Dòng 2970: function openAction(s, detailView, order, action) {
- Dòng 3203: function appendReloadButton() {

## frontend/js/pricing.js

Số dòng: 29
- Dòng 5: const range=(from,to,unit)=>(from??0)+" – "+(to??"không giới hạn")+" "+unit;
- Dòng 6: function localTime(value){const raw=value||new Date().toISOString(),utc=/(?:Z|[+-]\d{2}:\d{2})$/i.test(raw)?raw:raw+"Z";const parts=new Intl.DateTimeFormat("sv-SE",{timeZone:"Asia/Ho_Chi_Minh",year:"numeric",month:"2-dig
- Dòng 7: function destroy(){active?.destroy();active=null;}
- Dòng 8: async function lookups(s,signal){const [services,areas,branches]=await Promise.all([s.read("/api/v1/catalogs?type=SERVICES",signal),s.read("/api/v1/catalogs?type=AREAS",signal),s.read("/api/v1/catalogs?type=BRANCHES",sig
- Dòng 9: function numeric(form,f,key,label,value,required=false,max="99999999.99"){return U.field(form,f,key,label,value,{required,type:"number",min:0,max,step:"0.01"});}
- Dòng 10: function fee(form,f,key,label,value){const n=U.field(form,f,key,label,value,{required:true,maxLength:19,pattern:"[0-9]+(?:\\.[0-9]{1,2})?"});n.inputMode="decimal";return n;}
- Dòng 11: async function editor(s,id,toggle=false){const d=U.dialog(s,toggle?"Thay đổi trạng thái quy tắc":id?"Sửa quy tắc cước":"Thêm quy tắc cước");if(!d)return;async function load(){try{const [c,data]=await Promise.all([id?s.re
- Dòng 21: function quote(s,data){const panel=U.el("section","pricing-quote"),form=U.el("form","row g-3"),f={},box=U.el("div","col-12"),submit=U.button("Thử tính phí",null,"btn btn-orange");submit.type="submit";
- Dòng 26: async function list(s){const pending=U.request(s);R.updateQuery(s.filters,s.route);s.route=R.current()||s.route;s.root.replaceChildren(U.el("p","admin-empty","Đang tải bảng giá…"));try{const path="/api/v1/shipping-fees/r
- Dòng 27: function mount(container,user,route,context){destroy();active=U.state(container,user,route,context);active.filters={page:route.query.page||1,pageSize:route.query.pageSize||10,serviceId:route.query.serviceId||"",areaId:ro

## frontend/js/reports.js

Số dòng: 291
- Dòng 24: function todayVN() { return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Ho_Chi_Minh", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()); }
- Dòng 25: function shiftDay(day, delta) { const date = new Date(day + "T00:00:00Z"); date.setUTCDate(date.getUTCDate() + delta); return date.toISOString().slice(0, 10); }
- Dòng 26: function validateDates(from, to) {
- Dòng 36: function csvCell(value) {
- Dòng 41: function csvRows(rows) { return "\uFEFF" + rows.map(row => row.map(csvCell).join(",")).join("\r\n") + "\r\n"; }
- Dòng 42: function definition(tab, to) {
- Dòng 47: function validateReport(data, tab) {
- Dòng 59: function cell(key, value, tab) { return key === "successRatePercent" ? rate(value) : /Name$/.test(key) ? value : tab === "finance" ? money(value) : number(value); }
- Dòng 60: function dataTable(headers, rows, caption, keys = [], tooltips = {}) {
- Dòng 80: function card(title, content) {
- Dòng 83: function chart(s, rows) {
- Dòng 89: function draw(width) {
- Dòng 95: const add = (type, attrs, text) => { const n = document.createElementNS(svg.namespaceURI, type); for (const [key, value] of Object.entries(attrs)) n.setAttribute(key, value); if (text != null) n.textContent = text; svg.a
- Dòng 111: function destroy() { active?.destroy(); active = null; }
- Dòng 112: function path(filters, exporting = false) { return "/api/v1/reports/dashboard?" + U.query({ from: filters.from, to: filters.to, branchId: filters.branchId, report: filters.tab, page: filters.page, pageSize: filters.pageS
- Dòng 113: function updateURL(s) { R.updateQuery(s.filters, s.route); s.route = R.current() || s.route; }
- Dòng 114: function hasDraft(s) {
- Dòng 118: function updateQuick(s) {
- Dòng 125: function draftNotice(s) {
- Dòng 129: function switchTab(s, tab) {
- Dòng 132: function apply(s, tab = s.filters.tab, reset = false) {
- Dòng 140: function shell(s) {
- Dòng 169: function markDraft() { s.draftVersion++; if (s.exportButton) s.exportButton.disabled = hasDraft(s) || s.exporting; draftNotice(s); updateQuick(s); }
- Dòng 173: function totals(s, data) {
- Dòng 188: async function exportCSV(s) {
- Dòng 205: function dateRange(from, to) {
- Dòng 208: function explanation(tab, to) {
- Dòng 218: function statusList(data) {
- Dòng 228: function pager(s, data) {
- Dòng 242: function render(s, data) {
- Dòng 266: async function load(s) {
- Dòng 283: function mount(container, user, route, context) {

## frontend/js/roles.js

Số dòng: 25
- Dòng 4: function destroy(){active?.destroy();active=null;}
- Dòng 5: const same=(a,b)=>a.size===b.size&&[...a].every(id=>b.has(id));
- Dòng 6: function group(code){if(code.startsWith("DONHANG_"))return "Đơn hàng";if(code.startsWith("KHO_"))return "Kho";if(code.startsWith("DIEUPHOI_"))return "Điều phối";if(/^(NHIEMVU|BANGCHUNG)_/.test(code))return "Giao hàng";if
- Dòng 7: async function editor(s,id){if(s.dirty){s.dirtyBox.textContent="Hãy lưu hoặc hủy thay đổi quyền trước khi sửa vai trò.";return;}const d=U.dialog(s,id?"Sửa vai trò":"Thêm vai trò");if(!d)return;
- Dòng 8: async function load(){try{const c=id?await s.read("/api/v1/roles?id="+id,d.signal):null;if(!s.alive()||d.closed)return;const form=U.el("form","row g-3"),f={};U.field(form,f,"code","Mã vai trò *",c?.code,{required:true,ma
- Dòng 9: async function render(s){if(s.route.mode==="detail")return detail(s);return list(s);}
- Dòng 10: async function list(s){const pending=U.request(s);s.root.replaceChildren(U.el("p","admin-empty","Đang tải vai trò…"));try{const q=s.route.query,data=await s.read("/api/v1/roles?"+U.query({keyword:q.keyword,activeOnly:q.i
- Dòng 11: async function detail(s){const pending=U.request(s);s.root.replaceChildren(U.el("p","admin-empty","Đang tải tập quyền đầy đủ…"));try{const c=await s.read("/api/v1/roles?id="+s.route.params.id,pending.signal);if(!s.alive(
- Dòng 17: function dirty(){s.dirty=!same(s.selected,s.original);save.disabled=!s.dirty;s.dirtyBox.textContent=s.dirty?"Có thay đổi chưa lưu":"Quyền đã khớp dữ liệu backend";for(const [all,ps]of groupChecks){const count=ps.filter(p
- Dòng 23: function mount(container,user,route,context){destroy();active=U.state(container,user,route,context);if(!active.can("PHANQUYEN_QUANLY")){U.notice(active.root,"Bạn không có quyền quản lý phân quyền.");return;}render(active

## frontend/js/router.js

Số dòng: 375
- Dòng 97: function entryPosition() {
- Dòng 101: function stampHistory(position, hash = window.location.hash) {
- Dòng 104: function setLeaveGuard(guard) {
- Dòng 111: function internalHash(value) {
- Dòng 121: function positive(value, max = Number.MAX_SAFE_INTEGER) {
- Dòng 124: function parse(hash) {
- Dòng 248: function href(name, params = {}, query = {}) {
- Dòng 262: function visibleMenus(user, permissions) {
- Dòng 273: function roleAccess(route, user) {
- Dòng 280: function allowed(route, user, permissions) {
- Dòng 285: function remember(hash) {
- Dòng 289: function navigate(target, options = {}) {
- Dòng 300: function updateQuery(query, expected = current) {
- Dòng 306: async function transition(force = false) {
- Dòng 350: function completeLogin() {
- Dòng 355: function goLogin(preserve = false) {
- Dòng 362: function start(settings) {
- Dòng 368: function transitionEvent() { transition(); }
- Dòng 369: function stop() {

## frontend/js/shippers.js

Số dòng: 329
- Dòng 12: const can = (s, code) => s.permissions?.known === true && s.permissions.codes.has(code);
- Dòng 14: const read = (s, path, signal) => window.ApiClient.request(path, {signal: signal || s.abort.signal});
- Dòng 15: function query(values) {return new URLSearchParams(Object.entries(values).filter(([,v]) => v !== "" && v != null)).toString();}
- Dòng 16: function select(items, value) {const n=el("select","form-select"); for(const [v,label] of items){const o=el("option","",label);o.value=v;n.append(o);}n.value=value??"";return n;}
- Dòng 17: function actions(...nodes){const n=el("div","shipper-actions");n.append(...nodes);return n;}
- Dòng 18: function link(label,href){const n=el("a","btn btn-outline-orange btn-sm",label);n.href=href;return n;}
- Dòng 19: function alert(box,message,tone="danger"){box.replaceChildren();if(message){const n=el("div","alert alert-"+tone,message);n.setAttribute("role",tone==="success"?"status":"alert");box.append(n);}}
- Dòng 20: function failure(s,box,error,retry){if(!alive(s)||error.name==="AbortError"||error.sessionExpired)return;alert(box,(error.status===403?"Không có quyền. ":error.status===404?"Không tìm thấy nhân viên trong phạm vi được ph
- Dòng 21: function badge(value,label){return el("span","badge "+(value?"text-bg-success":"text-bg-secondary"),label);}
- Dòng 22: function working(code){return badge(code==="AVAILABLE",availability[code]||code);}
- Dòng 23: function vehicleText(v){return v?v.licensePlate+" · "+v.code:"Chưa có phương tiện";}
- Dòng 24: function field(form,fields,key,label,value,config={}){
- Dòng 32: function invalid(fields,key,message){const f=fields[key];if(!f)return;f.control.classList.add("is-invalid");f.control.setAttribute("aria-invalid","true");f.error.textContent=message;}
- Dòng 33: function clearErrors(fields){for(const f of Object.values(fields)){f.control.classList.remove("is-invalid");f.control.removeAttribute("aria-invalid");f.error.textContent="";}}
- Dòng 34: function invalidLicenseUpdate(record,licenseNumber,licenseExpiresAt,isActive){
- Dòng 42: function serverErrors(fields,error){
- Dòng 50: function dialog(s,title){
- Dòng 58: function save(s,d,form,fields,path,method,build,label="Lưu"){
- Dòng 70: function showVersionConflict(s,d,box,id){
- Dòng 84: function areasForm(form,fields,areas,existing){
- Dòng 87: function addRow(a){if(rows.children.length>=100)return;const row=el("div","shipper-area-row"),area=select([["","Chọn khu vực"],...areas.map(k=>[k.id,k.name])],a.id);
- Dòng 95: async function catalog(s,type,signal){const data=await read(s,"/api/v1/catalogs?"+query({type,activeOnly:type==="AREAS"?"true":"false"}),signal);const key=type.toLowerCase();if(!Array.isArray(data[key]))throw new Error("
- Dòng 96: function picker(s,d,form,fields,key,title,path,base,branches,preferred){
- Dòng 107: async function load(){pending?.abort();pending=new AbortController();const seq=++epoch,signal=AbortSignal.any([d.signal,pending.signal]);list.disabled=true;list.replaceChildren();const loading=el("option","","Đang tải…")
- Dòng 113: async function editor(s,id){
- Dòng 115: async function load(){try{
- Dòng 138: async function toggle(s,id){
- Dòng 140: async function load(){try{
- Dòng 156: async function vehicleEditor(s,id,preferredVehicle){
- Dòng 159: async function load(){try{const [c,typeCatalog]=await Promise.all([read(s,"/api/v1/shippers?id="+id,d.signal),read(s,"/api/v1/vehicles/types",d.signal)]);if(!alive(s)||d.closed)return;
- Dòng 170: function vehiclePicker(s,d,form,fields,shipper,types,preferred){
- Dòng 191: function setSelected(row){
- Dòng 205: function applyFilters(){
- Dòng 212: function checkScope(data){
- Dòng 218: async function requestPage(params,signal){
- Dòng 224: async function load(){
- Dòng 264: async function initialize(){
- Dòng 283: function pagination(box,data,previous,next){const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize));const prev=button("‹ Trước",previous),nxt=button("Sau ›",next);prev.disabled=data.page<=1;nxt.disabled=data.pag
- Dòng 284: function rowActions(s,c){const n=actions(link("Xem chi tiết",Router.href("shipper-detail",{id:c.id},s.filters||s.route.query)));if(can(s,"TAIKHOAN_QUANLY"))n.append(button("Sửa",()=>editor(s,c.id)),button(c.isActive?"Ngừ
- Dòng 285: async function list(s){
- Dòng 293: async function mountList(s){
- Dòng 301: async function loadBranches(){try{const branches=await catalog(s,"BRANCHES");if(!alive(s))return;const n=select([["","Tất cả bưu cục trong phạm vi"],...branches.map(b=>[b.id,b.name+(b.isActive?"":" (ngừng hoạt động)")])]
- Dòng 303: function related(s,c,kind){
- Dòng 308: async function load(){pending?.abort();pending=new AbortController();const signal=AbortSignal.any([s.abort.signal,pending.signal]);body.replaceChildren(el("p","text-secondary","Đang tải…"));pager.replaceChildren();
- Dòng 314: async function detail(s){
- Dòng 322: function refresh(s){if(!alive(s))return;if(s.externalRefresh)return s.externalRefresh();return s.route.mode==="detail"?detail(s):list(s);}
- Dòng 323: function destroy(){if(!active)return;active.dialog?.close();active.abort.abort();active.listAbort?.abort();active=null;}
- Dòng 324: function mount(container,user,route,context){destroy();const root=el("div","shippers-page");container.replaceChildren(root);const s={root,user,route,permissions:context.permissions,abort:new AbortController(),detailEpoch

## frontend/js/tracking.js

Số dòng: 185
- Dòng 6: function utc(value){return value?new Date(String(value)+(/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)?"":"Z")):null;}
- Dòng 7: function date(value){const d=utc(value);return !d||Number.isNaN(d.getTime())?"—":new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Ho_Chi_Minh",day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit",h
- Dòng 8: function coordinates(point){return point&&typeof point.latitude==="number"&&typeof point.longitude==="number"&&Number.isFinite(point.latitude)&&Number.isFinite(point.longitude)&&Math.abs(point.latitude)<=90&&Math.abs(poi
- Dòng 9: function locationState(point,now=Date.now()){if(!coordinates(point))return "missing";const time=utc(point.locationUpdatedAt)?.getTime();return !Number.isFinite(time)?"undated":now-time>staleAfter?"stale":time>now+60000?"
- Dòng 10: function label(s,status){return s.options.statuses.find(n=>n.code===status)?.name||status||"Chưa rõ trạng thái";}
- Dòng 11: function badge(s,status){const tone=["FAILED","RETRY_WAITING","RETURNING"].includes(status)?"attention":["DELIVERED","COMPLETED","RETURNED"].includes(status)?"success":"neutral";return el("span","tracking-badge tracking-
- Dòng 12: function query(s){return {...s.filters,statusGroup:s.filters.statusGroup||"ALL",orderId:s.selected||"",view:s.view,auto:String(s.auto)};}
- Dòng 13: function sync(s){R.updateQuery(query(s),s.route);s.route=R.current()||s.route;}
- Dòng 14: function requestPath(s){return "/api/v1/orders?"+U.query(s.filters);}
- Dòng 15: function releaseMap(s){s.mapResize?.disconnect();cancelAnimationFrame(s.resizeFrame);s.map?.remove();s.map=null;s.markers=null;s.mapFitted=false;s.tileFailed=false;}
- Dòng 16: const compact=()=>window.matchMedia("(max-width:1099.98px)").matches;
- Dòng 18: function icon(name){const n=el("i","bi bi-"+name);n.setAttribute("aria-hidden","true");return n;}
- Dòng 19: function resizeMap(s){cancelAnimationFrame(s.resizeFrame);s.resizeFrame=requestAnimationFrame(()=>{if(!s.alive()||!s.map||!s.mapHost.getClientRects().length)return;const size=s.map.getSize();if(size.x!==s.mapHost.clientW
- Dòng 20: function fitPoints(s){if(s.map&&s.points?.length)s.map.fitBounds(s.points.map(p=>[p.latitude,p.longitude]),{padding:[52,52],maxZoom:15,animate:false});}
- Dòng 21: function releaseEvidence(s){s.evidenceAbort?.abort();for(const url of s.fileUrls||[])URL.revokeObjectURL(url);s.fileUrls=[];}
- Dòng 22: function destroy(){active?.destroy();active=null;}
- Dòng 23: function schedule(s){clearTimeout(s.timer);if(s.alive()&&s.refreshButton&&s.auto&&!document.hidden&&!s.busy)s.timer=setTimeout(()=>refresh(s),interval);}
- Dòng 24: function toggleAuto(s){s.auto=s.autoControl.checked;sync(s);s.updateTime();schedule(s);}
- Dòng 25: function resetSelection(s){s.detailAbort?.abort();releaseEvidence(s);releaseMap(s);s.selected=null;s.data=null;s.detail.replaceChildren(el("p","tracking-empty","Chọn một đơn để xem tiến độ giao hàng."));s.root.classList.
- Dòng 26: function shell(s){
- Dòng 31: const shippers=()=>[["","Tất cả shipper"],...s.options.shippers.filter(n=>!fields.branchId.control.value||String(n.branchId)===fields.branchId.control.value).map(n=>[n.id,n.name])];
- Dòng 43: const draft=()=>{s.draft.textContent="Bộ lọc đã đổi. Chọn Tìm kiếm để áp dụng.";caption.textContent="Bộ lọc thêm"+((fields.fromDate.control.value||fields.toDate.control.value)?" · Có ngày lọc":"");};
- Dòng 61: function renderList(s,data){
- Dòng 76: async function refresh(s){
- Dòng 92: async function select(s,id,open){
- Dòng 99: function buildDetail(s){
- Dòng 113: function showTab(s){for(const key of ["map","history"]){const selected=s.view===key;s.tabButtons[key].setAttribute("aria-selected",String(selected));s.tabButtons[key].tabIndex=selected?0:-1;}s.mapPane.hidden=s.view!=="ma
- Dòng 114: async function readDetail(s,id,refreshing){
- Dòng 121: function renderDetail(s){
- Dòng 137: function updateMap(s){
- Dòng 167: async function loadEvidence(s,page){
- Dòng 174: async function mount(container,user,route,context){

## frontend/js/transactions.js

Số dòng: 157
- Dòng 13: function message(error) {
- Dòng 19: function typeBadge(value) { return el("span", "transaction-type transaction-type-" + (types[value] ? value.toLowerCase() : "unknown"), types[value] || text(value)); }
- Dòng 20: function code(value) { const node = el("span", "transaction-code", text(value)); node.title = text(value); node.tabIndex = 0; return node; }
- Dòng 21: async function read(s, url, signal) { return window.ApiClient.request(url, { signal: signal ? AbortSignal.any([s.abort.signal, signal]) : s.abort.signal }); }
- Dòng 22: function destroy() {
- Dòng 26: function mount(container, user, route, context) {
- Dòng 61: function collect(s) {
- Dòng 71: function apply(s) {
- Dòng 77: async function loadWarehouses(s) {
- Dòng 92: function renderPager(s, totalItems) {
- Dòng 99: async function reload(s) {
- Dòng 123: function openDetail(s, id) {
- Dòng 127: async function load() {

## frontend/js/vehicles.js

Số dòng: 165
- Dòng 9: const can=(s,code)=>s.permissions?.known===true&&s.permissions.codes.has(code);
- Dòng 11: const read=(s,path,signal)=>window.ApiClient.request(path,{signal:signal||s.abort.signal});
- Dòng 13: function actions(...nodes){const n=el("div","vehicle-actions");n.append(...nodes);return n;}
- Dòng 14: function select(items,value){const n=el("select","form-select");for(const [id,label]of items){const o=el("option","",label);o.value=id;n.append(o);}n.value=value??"";return n;}
- Dòng 15: function link(label,href){const n=el("a","btn btn-outline-orange btn-sm",label);n.href=href;return n;}
- Dòng 16: function employeeLink(label,id){const n=el("a","vehicle-employee-link",label);n.href=Router.href("shipper-detail",{id});return n;}
- Dòng 17: function alert(box,message,tone="danger"){box.replaceChildren();if(message){const n=el("div","alert alert-"+tone,message);n.setAttribute("role",tone==="success"?"status":"alert");box.append(n);}}
- Dòng 18: function failure(s,box,error,retry){if(!alive(s)||error.name==="AbortError"||error.sessionExpired)return;alert(box,(error.status===403?"Không có quyền. ":error.status===404?"Không tìm thấy phương tiện trong phạm vi được 
- Dòng 19: function badge(code){return el("span","badge "+(code==="AVAILABLE"?"text-bg-success":code==="INACTIVE"?"text-bg-secondary":code==="MAINTENANCE"?"text-bg-warning":"text-bg-primary"),states[code]||code);}
- Dòng 20: function amount(value,unit){return value==null?"—":number.format(value)+" "+unit;}
- Dòng 21: function field(form,fields,key,label,value,config={}){
- Dòng 27: function invalid(fields,key,message){const f=fields[key];if(!f)return;f.control.classList.add("is-invalid");f.control.setAttribute("aria-invalid","true");f.error.textContent=message;}
- Dòng 28: function clear(fields){for(const f of Object.values(fields)){f.control.classList.remove("is-invalid");f.control.removeAttribute("aria-invalid");f.error.textContent="";}}
- Dòng 29: function serverErrors(fields,error){for(const [key,messages]of Object.entries(error.data?.errors||{})){const actual=Object.keys(fields).find(f=>f.toLowerCase()===key.split(".").at(-1).toLowerCase());if(actual)invalid(fie
- Dòng 33: function showVersionConflict(s,d,box,id){
- Dòng 47: function dialog(s,title){if(s.dialog)return null;const node=el("dialog","vehicle-modal"),heading=el("h2","h5 mb-0",title),header=el("div","vehicle-modal-header"),body=el("div","vehicle-modal-body");heading.id="vehicle-di
- Dòng 50: async function editor(s,id,statusOnly=false){if(!write(s))return;const d=dialog(s,id?(statusOnly?"Đổi trạng thái phương tiện":"Sửa phương tiện"):"Thêm phương tiện");if(!d)return;
- Dòng 51: async function load(){try{const [c,catalog]=await Promise.all([id?read(s,"/api/v1/vehicles?id="+id,d.signal):null,read(s,"/api/v1/vehicles/types",d.signal)]);if(!alive(s)||d.closed)return;
- Dòng 65: const definition=()=>types.find(t=>t.code===type.value);
- Dòng 67: function capacityRules(submit=false){const t=definition(),preserve=c&&!useTypeCapacity&&type.value===c.vehicleType;
- Dòng 81: const important=()=>c?status.value!==c.status:status.value!=="AVAILABLE";
- Dòng 82: function updateConfirmation(){confirm.checked=false;fields.confirmStatus.box.hidden=!important();fields.confirmStatus.caption.textContent="Tôi xác nhận "+(c?"đổi xe "+c.code+" · "+c.licensePlate+" từ "+states[c.status]+"
- Dòng 100: function pagination(box,data,prev,next){const pages=Math.max(1,Math.ceil(data.totalItems/data.pageSize)),previous=button("‹ Trước",prev),following=button("Sau ›",next);previous.disabled=data.page<=1;following.disabled=da
- Dòng 101: async function linkEmployee(s,id){if(!window.VehicleLink.permitted(s))return;const d=dialog(s,"Liên kết nhân viên giao hàng");if(!d)return;
- Dòng 102: async function load(){try{const v=await read(s,"/api/v1/vehicles?id="+id,d.signal);if(!alive(s)||d.closed)return;
- Dòng 110: async function listEmployees(){pending?.abort();pending=new AbortController();const signal=AbortSignal.any([d.signal,pending.signal]);picker.disabled=true;next.disabled=true;alert(feedback,"");pager.replaceChildren();
- Dòng 116: function rowActions(s,v){const n=actions(link("Xem chi tiết",Router.href("vehicle-detail",{id:v.id},s.filters||s.route.query)));if(write(s))n.append(button("Sửa",()=>editor(s,v.id)),button("Đổi trạng thái",()=>editor(s,v
- Dòng 117: async function list(s){s.listAbort?.abort();s.listAbort=new AbortController();const signal=AbortSignal.any([s.abort.signal,s.listAbort.signal]);Router.updateQuery(s.filters,s.route);s.route=Router.current()||s.route;s.re
- Dòng 126: function mountList(s){const q=s.route.query;s.filters={page:q.page||1,pageSize:q.pageSize||10,keyword:q.keyword||"",vehicleType:q.vehicleType||"",branchId:q.branchId||"",status:q.status||""};
- Dòng 131: function related(s,v,isTrips){const panel=el("section","vehicle-related");panel.append(el("h3","h6",isTrips?"Chuyến giao sử dụng xe":"Phân công đang sử dụng xe"));const body=el("div"),pager=el("div","vehicle-pagination")
- Dòng 133: async function load(){pending?.abort();pending=new AbortController();const signal=AbortSignal.any([s.abort.signal,pending.signal]);body.replaceChildren(el("p","text-secondary","Đang tải…"));pager.replaceChildren();try{co
- Dòng 137: function capacityCheck(s,v){const panel=el("section","vehicle-related vehicle-capacity"),body=el("div"),result=el("div","mt-2"),pager=el("div","vehicle-pagination");let page=1,request;
- Dòng 139: async function load(){request?.abort();request=new AbortController();const signal=AbortSignal.any([s.abort.signal,request.signal]);body.replaceChildren(el("p","text-secondary","Đang tải đơn chờ điều phối…"));result.repla
- Dòng 153: async function detail(s){const epoch=++s.detailEpoch;s.root.replaceChildren(el("p","vehicle-empty","Đang tải phương tiện…"));const back=link("‹ Quay về danh sách",Router.href("vehicles",{},s.route.query));
- Dòng 161: function refresh(s){if(!alive(s))return;return s.route.mode==="detail"?detail(s):list(s);}
- Dòng 162: function destroy(){if(!active)return;active.dialog?.close();active.abort.abort();active.listAbort?.abort();active=null;}
- Dòng 163: function mount(container,user,route,context){destroy();const root=el("div","vehicles-page");container.replaceChildren(root);const s={root,user,route,permissions:context.permissions,abort:new AbortController(),detailEpoch

## frontend/js/vietnam-date.js

Số dòng: 23
- Dòng 10: function today(instant = new Date()) {
- Dòng 18: function isLicenseExpired(expiresAt, instant = new Date()) {

## frontend/js/warehouse.js

Số dòng: 2020
- Dòng 80: function destroy() {
- Dòng 92: function reset() {
- Dòng 96: function can(s, code) {
- Dòng 102: function locationName(location) {
- Dòng 112: function valid(s, epoch) {
- Dòng 115: async function read(s, path, signal) {
- Dòng 120: function stockBadge(code) {
- Dòng 123: function errorMessage(error) {
- Dòng 149: function updateActions(s) {
- Dòng 160: function writeButton(s, label, callback, eligible = true) {
- Dòng 167: function orderCell(s, row) {
- Dòng 212: function orderLink(s, row) {
- Dòng 219: function loading(node, message) {
- Dòng 226: function mount(container, user, mode, route, routeContext) {
- Dòng 358: async function loadPermissions(s) {
- Dòng 386: async function loadWarehouses(s, restore = false) {
- Dòng 448: function clearScope(s) {
- Dòng 468: async function chooseWarehouse(s, id, restore = false) {
- Dòng 554: function showContext(s) {
- Dòng 570: function showLocations(s) {
- Dòng 590: function refresh(s) {
- Dòng 594: function showWarehouseActionResult(s, context, result) {
- Dòng 675: function createList(s, config) {
- Dòng 777: function commit() {
- Dòng 807: function clear() {
- Dòng 834: async function reload() {
- Dòng 955: function buildContent(s) {
- Dòng 995: function inventoryList(s) {
- Dòng 1081: function returnRequestList(s) {
- Dòng 1128: const code = (value) => {
- Dòng 1151: function returnReason(s, row) {
- Dòng 1167: function handoverList(s) {
- Dòng 1251: function handoverReason(row) {
- Dòng 1266: function historyList(s, order) {
- Dòng 1349: function openHistory(s, row) {
- Dòng 1360: function openReady(s, row) {
- Dòng 1438: async function findInventory(s, row) {
- Dòng 1462: async function findHandover(s, row) {
- Dòng 1488: function locationControl(s, locations, selected) {
- Dòng 1495: async function actionView(s, title, permission, prepare) {
- Dòng 1532: function openMove(s, row) {
- Dòng 1589: function openReturn(s, row) {
- Dòng 1700: function openOutbound(s, row) {
- Dòng 1748: function renderAction(s, view, context, epoch, permission) {
- Dòng 1805: function buildPayload() {
- Dòng 1933: async function openTransaction(s, id) {
- Dòng 1940: async function reload() {

## frontend/js/write-outcome.js

Số dòng: 67
- Dòng 7: function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==="object")return Object.fromEntries(Object.keys(value).sort().map(k=>[k,/password|token|secret|authorization/i.test(k)
- Dòng 8: function assertCanSend(owner,{path,payload,body,method="POST"}){
- Dòng 19: function reviewPaths(path,p={}) {
- Dòng 35: function show(host,data,el,depth=0){
- Dòng 41: function freeze(scope){
- Dòng 48: function restore(states,owner){for(const [n,disabled]of states)n.disabled=disabled;if(owner.writeUnknown)freeze(owner.writeScope||owner.body);}
- Dòng 49: function lock(owner,box,error,{path,payload={},scope=owner.body,signal=owner.signal}={}){

## frontend/README.md

Số dòng: 156
- Dòng 1: # TVĐ Logistics frontend
- Dòng 9: ## Điều hướng hash
- Dòng 21: ## Chạy local
- Dòng 45: ## Chức năng và API
- Dòng 104: ## Quản lý kho
- Dòng 106: ### Nhập kho

## frontend/tests/accounts-browser.cjs

Số dòng: 107

## frontend/tests/accounts-fixture.ps1

Số dòng: 55

## frontend/tests/admin-audit.cjs

Số dòng: 10

## frontend/tests/admin-browser.cjs

Số dòng: 25

## frontend/tests/admin-catalogs.cjs

Số dòng: 22

## frontend/tests/admin-fixture.ps1

Số dòng: 54

## frontend/tests/admin-pricing.cjs

Số dòng: 18

## frontend/tests/admin-regression.cjs

Số dòng: 28

## frontend/tests/admin-roles.cjs

Số dòng: 28

## frontend/tests/api.test.cjs

Số dòng: 336

## frontend/tests/auth-login-fixture.ps1

Số dòng: 61

## frontend/tests/auth-login.cjs

Số dòng: 199

## frontend/tests/auth-sessions-fixture.ps1

Số dòng: 81

## frontend/tests/auth-sessions.cjs

Số dòng: 247

## frontend/tests/auth.test.cjs

Số dòng: 221

## frontend/tests/cod-browser.cjs

Số dòng: 34

## frontend/tests/cod-checks.cjs

Số dòng: 92

## frontend/tests/cod-fixture.ps1

Số dòng: 39

## frontend/tests/cod.test.cjs

Số dòng: 5

## frontend/tests/customer-detail-sql.ps1

Số dòng: 73

## frontend/tests/customer-version-browser.cjs

Số dòng: 82

## frontend/tests/customer-version-checks.cjs

Số dòng: 79

## frontend/tests/customers-browser.cjs

Số dòng: 108

## frontend/tests/customers-fixture.ps1

Số dòng: 52

## frontend/tests/dashboard-browser.cjs

Số dòng: 36

## frontend/tests/dashboard-checks.cjs

Số dòng: 60

## frontend/tests/dashboard-fixture.ps1

Số dòng: 36

## frontend/tests/dashboard-fixture.sql

Số dòng: 55

## frontend/tests/dashboard-large-fixture.sql

Số dòng: 18

## frontend/tests/dispatch-browser.cjs

Số dòng: 35

## frontend/tests/dispatch-checks.cjs

Số dòng: 94

## frontend/tests/dispatch-depot-checks.cjs

Số dòng: 63

## frontend/tests/dispatch-depot.test.cjs

Số dòng: 18

## frontend/tests/dispatch-fixture.ps1

Số dòng: 130

## frontend/tests/dispatch-lists.test.cjs

Số dòng: 115

## frontend/tests/dispatch-validity.test.cjs

Số dòng: 247

## frontend/tests/dispatch-window-checks.cjs

Số dòng: 87

## frontend/tests/evidence-fixture.ps1

Số dòng: 59

## frontend/tests/evidence-upload.cjs

Số dòng: 108

## frontend/tests/fleet-version.test.cjs

Số dòng: 105

## frontend/tests/location-catalog-sql.ps1

Số dòng: 68

## frontend/tests/locations-browser.cjs

Số dòng: 96

## frontend/tests/order-detail-browser.cjs

Số dòng: 148

## frontend/tests/order-edit-browser.cjs

Số dòng: 84

## frontend/tests/order-unsaved-browser.cjs

Số dòng: 165

## frontend/tests/outbound-browser.cjs

Số dòng: 140

## frontend/tests/proxy.test.cjs

Số dòng: 364

## frontend/tests/read-location-data.ps1

Số dòng: 48

## frontend/tests/read-order-detail.ps1

Số dòng: 39

## frontend/tests/read-outbound-data.ps1

Số dòng: 70

## frontend/tests/read-return-data.ps1

Số dòng: 51

## frontend/tests/read-transaction-data.ps1

Số dòng: 60

## frontend/tests/README.md

Số dòng: 61
- Dòng 1: # Mã kiểm tra và dữ liệu tạm
- Dòng 33: ## Dọn thư mục kiểm tra ngày 10/10/2026
- Dòng 51: ## Dọn bảy thư mục còn lại

## frontend/tests/reports-browser.cjs

Số dòng: 33

## frontend/tests/reports-checks.cjs

Số dòng: 77

## frontend/tests/reports-fixture.ps1

Số dòng: 49

## frontend/tests/reports-fixture.sql

Số dòng: 44

## frontend/tests/reports-ui-checks.cjs

Số dòng: 53

## frontend/tests/reports.test.cjs

Số dòng: 17

## frontend/tests/return-browser.cjs

Số dòng: 103

## frontend/tests/router.test.cjs

Số dòng: 301

## frontend/tests/shipper-license-browser.cjs

Số dòng: 33

## frontend/tests/shipper-license-update.test.cjs

Số dòng: 95

## frontend/tests/shippers-browser.cjs

Số dòng: 82

## frontend/tests/shippers-fixture.ps1

Số dòng: 51

## frontend/tests/tracking-browser.cjs

Số dòng: 34

## frontend/tests/tracking-checks.cjs

Số dòng: 68

## frontend/tests/tracking-fixture.ps1

Số dòng: 37

## frontend/tests/tracking.test.cjs

Số dòng: 19

## frontend/tests/transactions-browser.cjs

Số dòng: 87

## frontend/tests/vehicle-picker-browser.cjs

Số dòng: 189

## frontend/tests/vehicles-browser.cjs

Số dòng: 99

## frontend/tests/vehicles-fixture.ps1

Số dòng: 73

## frontend/tests/vietnam-date.test.cjs

Số dòng: 48

## frontend/tests/write-outcome.test.cjs

Số dòng: 131

## sp_ChuyenTrangThaiDonHang.sql

Số dòng: 134

## tools/apply_customer_version_migration.ps1

Số dòng: 75

## tools/apply_dispatch_migration.ps1

Số dòng: 114

## tools/AuthSessionDiagnostics/AuthSessionDiagnostics.csproj

Số dòng: 12

## tools/AuthSessionDiagnostics/Program.cs

Số dòng: 97

## tools/DepotDiagnostics/DepotDiagnostics.csproj

Số dòng: 4

## tools/DepotDiagnostics/Program.cs

Số dòng: 81

## tools/InspectSqlResultContracts.ps1

Số dòng: 53

## tools/prepare_roads.py

Số dòng: 49

## tools/VehicleSelectionDiagnostics/Program.cs

Số dòng: 81

## tools/VehicleSelectionDiagnostics/VehicleSelectionDiagnostics.csproj

Số dòng: 7
