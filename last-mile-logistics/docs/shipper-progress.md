# Tiến độ triển khai app tài xế

Cập nhật 30/10/2026. Tài liệu ghi lại các bước đã triển khai trong cuộc trao đổi.

**Danh sách chính là [bảng gốc 40 chức năng](shipper-functions-40.md).** Số bước trong bảng dưới là các chặng đã triển khai, không phải STT bảng 40. Bảng 11 mục bổ sung là bảng phụ, không thay thế danh sách chính.

| Bước | Phần đã hoàn thành | Hướng dẫn |
| --- | --- | --- |
| 1 | Đăng nhập, kiểm tra phiên, làm mới token, đăng xuất | [Xác thực](shipper-auth.md) |
| 2 | Đổi mật khẩu, khôi phục qua email | [Mật khẩu](shipper-password.md) |
| 3 | Hồ sơ tài xế theo dữ liệu admin | [Hồ sơ](shipper-profile.md) |
| 4 | Đăng ký, gửi ảnh và admin xét duyệt | [Đăng ký](shipper-registration.md) |
| 5 | Sẵn sàng/Ngoại tuyến, Đang giao do hệ thống cập nhật; không có Tạm nghỉ | [Trạng thái làm việc](shipper-availability.md) |
| 6 | Xem, nhận/từ chối nhiệm vụ; mở bản đồ đến kho sau khi nhận | [Phản hồi phân công](shipper-task-offers.md) |
| 7 | Danh sách nhiệm vụ theo nhóm, tìm kiếm và tải từng trang; Hoàn tất gồm kiện đã nhập hoàn | [Danh sách nhiệm vụ](shipper-task-list.md) |
| 8 | Chi tiết kiện/nhiệm vụ, mốc nhận thực tế, lần giao, ảnh bằng chứng và lịch sử giao lại/hoàn | [Chi tiết nhiệm vụ](shipper-task-detail.md) |
| 9 | Kiểm tra nhãn/đủ kiện, ghi chú nhận, báo sự cố và xác nhận nhận kiện an toàn khi mất kết nối | [Nhận kiện tại kho](shipper-pickup-receipt.md) |
| 10 | Lộ trình cùng chuyến, chọn điểm xem, giữ thứ tự admin và dừng tuyến/GPS cũ khi dữ liệu thay đổi | [Lộ trình điều phối](shipper-itinerary.md) |
| 11 | Xác nhận người nhận thực tế/COD, chụp hoặc chọn ảnh bằng chứng, biên nhận và chống ghi trùng khi mất phản hồi | [Giao thành công](shipper-delivery-success.md) |

Phần [thời gian nhiệm vụ và hạn đến kho](shipper-task-timing.md) đã bổ sung tương ứng **STT 9** của bảng 40. Hạn do điều phối đặt riêng; chưa đặt không báo trễ. Phần giao thành công/bằng chứng tương ứng **STT 22–23**, được gọi là chặng triển khai 11 trong tài liệu trước. Kết quả mới nhất: 196/196 Flutter, 36 nhóm tích hợp, 81 kiểm tra web và 319 kiểm tra lỗi ảnh/giao dịch. Mục hạn đến kho cần migration bổ sung một cột nullable; giao thành công/ảnh riêng không cần migration.

Đối chiếu các chặng: 1→STT 1; 2→STT 2; 3→STT 3; 4→STT 4; 5→STT 5; 6→STT 7–8; 7–8→STT 10 và một phần 38; 9→STT 12 và một phần 13/15; 10→STT 11/16/17; 11→STT 22–23. Đã hoàn thiện phần tình trạng/vị trí/ảnh nhận kiện **STT 13** (mục 2 bảng bổ sung): xem [biên nhận nhận kiện](shipper-pickup-condition.md). Đã triển khai tiếp **STT 14: Quét mã kiện**, **STT 15: Báo sự cố lấy hàng** và **STT 16: Chuyến giao, thứ tự giao**; đã bổ sung **STT 17: Bản đồ, chỉ đường trong app**. Mục kế tiếp hiện là **STT 18: Theo dõi vị trí tài xế**, mỗi lần một chức năng.

Luồng đã chốt: nhận nhiệm vụ → bản đồ đến kho → tài xế kiểm tra và xác nhận nhận kiện → hệ thống xuất kho và chuyển Đi giao → giữ thứ tự admin. Không thêm yêu cầu kho xác nhận bàn giao trước luồng nhận kiện trực tiếp.

Các báo cáo kiểm thử trong từng hướng dẫn là kết quả tại thời điểm thực hiện. Với phần bổ sung ở bước 10, đã chạy lại toàn bộ Flutter 174/174 và bộ tích hợp HTTP/SQL/SignalR 30 nhóm; chưa vận hành app trên thiết bị thật trong lần sửa.

Bổ sung sửa bản đồ đi vòng sau bước 10: giữ đường khi có cấm rẽ, ghép GPS vào đoạn đường, xem tuyến từ vị trí hiện tại và bỏ hình học lưu khác phiên bản. Kết quả mới: 48/48 định tuyến, 175/175 Flutter, 31 nhóm tích hợp. Xem [nguyên nhân, cách áp dụng và giới hạn](routing-detour-fix.md).

Bổ sung theo xác nhận về cuối ca: kiện hoàn không khóa chuyến mới sau khi phần giao đã xử lý xong; vẫn giữ trách nhiệm trả kho và tính tải hàng hoàn. Kết quả mới: 50/50 lập kế hoạch/định tuyến, 177/177 Flutter, 33 nhóm tích hợp. Xem [hàng chờ trả kho cuối ca](shipper-deferred-returns.md).

Bổ sung **STT 13 — tình trạng/GPS/ảnh nhận kiện** ngày 30/10/2026: có biên nhận theo phân công, ảnh riêng theo quyền và admin/kho xem lại; hư hại sẵn cần ảnh + mô tả, GPS không lấy được giữ null. Kết quả: **205/205 Flutter**, analyze không lỗi; **39 nhóm HTTP/SQL/SignalR**, **213/213 web unit**, **319 kiểm tra lỗi giao dịch/ảnh nhận kiện**; build API 0 cảnh báo/lỗi. Chỉ kiểm thử database GUID, chưa chạy migration vận hành hoặc thiết bị. Cần áp dụng `20261030_shipper_pickup_receipts.sql`; hướng dẫn tại [nhận kiện có tình trạng](shipper-pickup-condition.md). STT 14 đã được bổ sung trong lần triển khai kế tiếp, xem bên dưới.

Bổ sung **STT 14 — Quét mã kiện** ngày 30/10/2026: camera đối chiếu nguyên mã với nhiệm vụ, xử lý nhiều mã/thiếu quyền/nhập tay; dừng camera khi chuyển nền, khớp mã hoặc rời màn. Tải lại nhiệm vụ trước/sau quét; vẫn xác nhận nhãn/đủ kiện rồi mới xuất kho. **224/224 Flutter**, analyze không lỗi; **40 nhóm tích hợp**; build Android debug x86_64 đạt. Không cài/chạy thiết bị, chưa thử camera thật/iOS/web trực tiếp. Đã sửa và kiểm tra migration chỉ mục biên nhận chạy lại an toàn, chưa áp dụng vận hành. Xem [mục 14](shipper-parcel-scanning.md). STT 15 đã triển khai trong lần kế tiếp, xem bên dưới.

Bổ sung **STT 15 — Báo sự cố lấy hàng** ngày 30/10/2026: hồ sơ theo phân công, loại sự cố/mô tả/ảnh riêng, kho yêu cầu bổ sung hoặc đóng hồ sơ có hướng xử lý; hồ sơ mở chặn nhận/xuất đúng đơn, kể cả khi đổi tài xế. Có UUID chống trùng, lịch sử nguyên vẹn, phiên bản khi phản hồi và phục hồi biên nhận khi mất kết nối. **239/239 Flutter**, analyze không lỗi; **43 nhóm API/SQL/SignalR**, **223/223 web**, **332 kiểm tra lỗi giao dịch/ảnh**; build API 0 cảnh báo/lỗi, APK Android debug x86_64 đạt. Chỉ dùng database GUID, không chạy SQL vận hành hoặc thiết bị thật. Cần migration `20261030_shipper_pickup_issues.sql`. Xem [mục 15](shipper-pickup-issues.md). STT 16 đã triển khai trong lần kế tiếp, xem bên dưới.

Bổ sung **STT 16 — Chuyến giao, thứ tự giao** ngày 30/10/2026: danh sách chuyến đang làm/lịch sử, tìm kiếm/phân trang, tiến độ và toàn bộ điểm theo số thứ tự admin. Tách giao thành công với điểm đã xử lý và hàng chờ trả kho cuối ca; thu hồi điểm ẩn thông tin liên hệ và khóa tuyến. Mở bản đồ giữ đúng chuyến, nhận kiện vẫn đưa về Đi giao. **254/254 Flutter**, analyze không lỗi; **48 nhóm API/SQL/SignalR**, build API 0 cảnh báo/lỗi và APK Android debug x86_64 đạt. Không cần SQL mới, chỉ kiểm thử database GUID, không chạy thiết bị hoặc ghi database vận hành. Xem [mục 16](shipper-trip-overview.md). STT 17 đã triển khai trong lần kế tiếp, xem bên dưới.

Bổ sung **STT 17 — Bản đồ, chỉ đường trong app** ngày 30/10/2026: hướng rẽ ước lượng từ hình tuyến, khoảng cách tới hướng rẽ, bảng chỉ đường riêng phía trên bản đồ; kiểm tra GPS cũ/đến muộn, tránh nhảy đoạn đường song song, hủy phản hồi khi dừng/chuyển nền và thử lại khi tính đường lỗi. Giữ thứ tự admin, không tự xác nhận nhận/giao. **268/268 Flutter** (gồm **35/35 bản đồ/lộ trình**), analyze không lỗi, APK Android debug x86_64 đạt. Chỉ sửa Flutter; không có SQL mới, không thay backend hoặc database vận hành, không chạy thiết bị. Hướng rẽ chưa có tên đường/giọng nói/giao thông trực tiếp. Xem [mục 17](shipper-navigation.md). Mục tiếp theo khi người dùng nói “tiếp”: **STT 18 — Theo dõi vị trí tài xế**.

Sửa lỗi bản đồ theo ảnh và GPS `10.7769, 106.7009` ngày 31/10/2026: mở rộng snapshot tới kinh độ 106.75, sửa điều kiện theo loại xe/ngoài mùa, chọn đường kết nối khi GPS ngoài đường bị ghép vào nhánh cụt; lỗi tuyến dự kiến trả JSON thay vì ném ngoại lệ. **61/61 định tuyến**, **6/6 nhóm API tuyến**, **51/51 Flutter bản đồ/chuyến**, analyze và build API/APK đạt. Kiểm tra toàn app hiện 265 đạt/19 lỗi ở Trang chủ/Nhận kiện; tích hợp toàn bộ dừng ở giao thành công HTTP 500, chưa sửa các phần đó trong lượt này. Không có SQL mới, không ghi database vận hành, chưa chạy thiết bị. Xem [báo cáo đầy đủ](routing-city-coverage-fix.md). Mục kế tiếp của bảng 40 vẫn là **STT 18 — Theo dõi vị trí tài xế**.

Sửa luồng GPS theo ảnh ngày 31/10/2026: gom yêu cầu quyền/vị trí, bỏ đọc cache cũ cho dẫn đường, thử provider độ chính xác cao/LocationManager, thêm mở cài đặt và lấy lại GPS tự tải lại tuyến hiện tại. **65/65 kiểm thử GPS/bản đồ/chuyến**, analyze và APK Android đạt; kiểm thử toàn app hiện 280 đạt/22 chưa đạt ở các màn khác, xem [báo cáo GPS](shipper-gps-recovery.md). Không đổi backend/SQL và không chạy thiết bị.
