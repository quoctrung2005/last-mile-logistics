# Direct shipper pickup — 2026-10-29

Update 2026-10-30: the receipt workflow has been completed in [feature 9](shipper-pickup-receipt.md). The current isolated SQL/API/SignalR suite passes 29 groups and Flutter passes 160 tests. The LocalDB startup blockers described below were historical results from 2026-10-29; they no longer describe the current verification state.

## Workflow
Accept assignment → focus the pickup/delivery screen → directions to assigned warehouse → compare parcel label and confirm the full order received → atomic stock export and IN_DELIVERY → directions to recipient. No separate warehouse approval or start-delivery button for the new flow.

POST /api/v1/my/tasks/{assignmentId}/pickup with trackingNumber (tracking number or order code printed on label) and optional notes. Only the current active shipper owning the assignment can perform pickup. One request receives one complete order; it does not export other orders in the trip or support partial quantities inside one order.

The transaction validates active account/branch, accepted current assignment, warehouse/location/stock, vehicle allocation/capacity and driver availability/licence. It creates one completed outbound stock movement and a confirmed receipt, clears the storage location/current warehouse, records intermediate HANDED_OVER → PICKED_UP → IN_DELIVERY history, updates driver/vehicle, and starts the matching trip on the first received order (at or after planned departure). A cancelled/reassigned trip cannot be revived. Other orders remain unchanged. Replays for the same active received assignment return success without creating additional exports.

Historical receipt records are retained for audit; they do not require a warehouse operator action. The older outbound/confirm/start endpoints are retained to finish existing pending handovers. Admin's Xuất kho page now tracks orders waiting for driver receipt and reported pickup issues; completed exports are in warehouse transaction history.

POST /api/v1/my/tasks/{assignmentId}/pickup-issue records a reason in the audit log without changing stock/order status. It is visible beside the waiting order on admin's Xuất kho page. This is a report, not a push notification to a dispatcher. Receipt currently uses label entry and a checklist; barcode camera scanning and pickup image attachments are not included.

## Route display — updated in-app navigation
The pickup action opens a full-screen Flutter map immediately, with a draggable order sheet. It does not open Google Maps. The app requests its current position and draws a road polyline from the backend's existing local OSM graph. Missing location/coordinates, unsupported coverage and unreachable routes are explicit; the app does not invent roads or replace GPS with the warehouse coordinate.

GET /api/v1/my/tasks/{assignmentId}/route?latitude=...&longitude=... is read-only and checks that the current task belongs to the active authenticated shipper. For delivery, the saved admin route leg is preferred verbatim when both order ID and stop sequence match (source ADMIN_PLAN). Other valid routes use the existing road graph and vehicle profile (source ROAD_GRAPH), never a new trip optimization. No admin trip order is written or changed.

Both the delivery tab and route list sort received tasks within each trip by ChiTietChuyenGiao.ThuTuDuKien; pending offers, unreceived orders and returns do not appear in the delivery tab. Cards show the actual admin stop number. Tasks without a trip have stable assignment order, not a claimed optimized order.

On successful pickup the route screen returns DriverRouteResult.received. All entry points (tasks, home popup and route tab) open the delivery tab and reload its server data. Failed pickup remains on the pickup screen; a timeout reconciles current status before offering another receipt.

Map tiles: OpenStreetMap with attribution. The app shows routing and estimated distance/time. Foreground GPS navigation is described below; voice turn instructions and live traffic are not included.

## Validation
Backend build: passed. Frontend router/dispatch list tests: 49 passed. Flutter tests: 27 passed (including receipt checklist/label submission and real navigation return to the delivery tab). Local road/route tests: 37 passed, including saved admin geometry/sequence selection and routing on the downloaded HCMC OSM graph. Flutter analysis: no issues after final formatting.

Integration test frontend/tests/shipper-sync-api.cjs now covers direct pickup, role/ownership/wrong-code/early pickup, stock release, concurrent retries, issue visibility, and existing legacy handover/success/COD/return scenarios. Current run blocked BEFORE database creation: LocalDB MSSQLLocalDB failed to start (SQL Network Interfaces error 50). No live database writes or app/emulator launches were performed. Full database-backed behavior is not yet verified on this machine. The integration suite also checks that the shipper route returns the saved admin leg and another shipper cannot read it; that DB-backed scenario remains pending because of LocalDB startup failure.

Restart the API from Visual Studio and fully stop/run the Flutter app manually after updating dependencies. Refresh admin browser with Ctrl+F5.

## Foreground GPS navigation — 2026-10-29

Tap **Bắt đầu chỉ đường** on the selected order to request a live route from current GPS to that same destination. The query `navigation=true` opts into live navigation. It keeps the dispatcher stop sequence and does not update any trip or saved geometry. The default overview still returns saved admin geometry when valid.

Live/pickup routing minimizes the sum of estimated road travel seconds with Dijkstra; dispatch planning continues to use distance, preserving existing planning behavior. Directions follow the configured vehicle profile, directed edges and existing conservative road restrictions. This is optimal only within the imported graph and its configured/tagged speeds, not a claim of Google Maps parity or traffic-aware travel time. The HUIT coordinate 10.80692,106.62868 to the sample depot 10.8105,106.6048 remains 3997.79 meters and 588.56 estimated seconds under both distance and time objectives in the current OSM snapshot.

During navigation, the position stream follows GPS while this screen is in the foreground. The camera follows unless the user pans; **Theo vị trí của tôi** restores following. Remaining distance is projected along the actual road polyline, and remaining time is an estimate proportional to that geometry. Arrival checks the actual destination, never only a snapped node, and never auto-confirms pickup or delivery.

Rerouting requires two reliable off-route fixes beyond max(45m, 2×accuracy), movement of at least 30m from the last route origin, and a 15-second minimum request gap. Fixes older than 2 minutes or with accuracy worse than 50m are ignored. Failures remain visible without drawing an invented replacement route. Tracking stops on Stop, screen disposal, app pause, or revoked/changed task. No background location permission or background tracking service was added.

Navigation test coverage includes segment projection, remaining geometry, arrival vs collapsed road nodes, GPS noise, reroute cooldowns, stationary fixes, real position-stream updates in a widget test, and subscription cancellation on Stop/pause. Map images in the widget test are in-memory; no emulator/GPS controls were operated.

To try movement manually in Android Emulator use Extended controls → Location → Routes and play a route; setting a single fixed point does not move the driver. Restart the API in Visual Studio and stop/run Flutter after these code changes. SQL-backed integration scenarios remain pending the previously reported LocalDB startup problem; no live database writes were performed by this change.
