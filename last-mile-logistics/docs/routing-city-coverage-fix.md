# Sửa lỗi chỉ đường từ GPS 10.7769, 106.7009

Cập nhật 31/10/2026. Lỗi được tái hiện bằng GPS người dùng gửi và tọa độ kho/điểm giao hiện tại của `shipper.tuan`. Truy vấn dữ liệu vận hành chỉ đọc mã nhiệm vụ, trạng thái và tọa độ; không sửa đơn/kho/GPS vận hành.

## Nguyên nhân và thay đổi

| Nguyên nhân | Bản sửa |
| --- | --- |
| Snapshot cũ kết thúc ở kinh độ 106.69, không bao phủ GPS 106.7009. | Tải snapshot OSM thật mới, giữ vùng cũ và mở rộng tới kinh độ 106.75. Vùng truy vấn: 10.70–10.85, 106.56–106.75; 256.843 nút, 73.780 đường, 1.302 quan hệ. Đây vẫn không phải dữ liệu toàn TP.HCM. |
| Điều kiện riêng xe tải hoặc đỗ xe làm đường bị loại với cả xe máy. | Lọc theo loại xe; quy định áp dụng cho xe máy/xe cơ giới vẫn được giữ. Quy tắc chưa hiểu được vẫn chặn đối tượng liên quan. |
| Các lịch đóng tháng 4/tháng 9 bị coi như đóng quanh năm, cắt các lối ra khỏi khu trung tâm. | Chỉ bỏ điều kiện khi chứng minh được toàn bộ các mệnh đề tháng/ngày/giờ rõ ràng nằm ngoài cửa sổ lịch hiện tại và bảy ngày lập kế hoạch tới, có đệm cho qua đêm. Không diễn giải đầy đủ cú pháp giờ mở cửa; biểu thức hỗn hợp, không rõ hoặc có thể áp dụng vẫn bị chặn. |
| GPS ngoài đường bị ghép vào nhánh cụt gần hơn, thay vì đường có lối ra. | Chỉ khi điểm cách đường hơn 15 m và ghép gần nhất thất bại mới xét đường hiện có khác trong cùng giới hạn 200 m; ưu tiên tổng khoảng tiếp cận nhỏ nhất. Lọc các thành phần không nối nhau và giới hạn 32 lần thử. Không thêm đường nối giả, không đổi quy tắc một chiều/cấm rẽ; điểm đã ở sát đường không tự nhảy đường để thoát quy tắc. |
| Không tìm được tuyến là tình huống dự kiến nhưng API ném `DispatchProblem`, khiến Visual Studio dừng theo chế độ debugger. | Trả trực tiếp HTTP 409 JSON có `code`/`message`: `ORIGIN_REQUIRED`, `ORIGIN_NOT_CONNECTED`, `DESTINATION_NOT_CONNECTED`, `NO_DRIVABLE_ROUTE`… Nhiệm vụ không khả dụng trả 404 bình thường. Không tắt cảnh báo ngoại lệ toàn bộ Visual Studio. |
| GPS chưa nằm trên đường đầu tuyến. | API trả khoảng cách tiếp cận đầu/cuối. App đánh dấu đầu đường và báo **Đến điểm bắt đầu tuyến**, hiển thị khoảng cách thực; không vẽ đường thẳng qua khu vực không có dữ liệu hoặc báo tới nơi. Khi GPS vào tuyến, hướng dẫn rẽ tiếp tục. |

Đối chiếu ngữ nghĩa khóa/điều kiện theo [OSM Conditional restrictions](https://wiki.openstreetmap.org/wiki/Conditional_restrictions). Bộ đọc ở đây chỉ hỗ trợ xác định ngoài mùa cho một tập cú pháp hẹp; không coi các điều kiện chưa đọc được là được phép đi.

Mạng đường tự nạp lại khi sang ngày Việt Nam. Phiên bản mạng bao gồm dữ liệu, chính sách và ngày đánh giá lịch; hình tuyến cũ khác phiên bản không được dùng như hình tuyến mới. Chuyến đang giao vẫn giữ số điểm/thứ tự admin, chỉ tính chặng mới từ GPS. Phương án chưa xác nhận dùng phiên bản cũ cần tính lại trước khi xác nhận.

## Kiểm tra đúng tọa độ được gửi

| Tuyến xe máy từ (10.7769, 106.7009) | Snapshot cũ | Bản sửa |
| --- | --- | --- |
| Tới kho đang lấy (10.8105, 106.6048) | Không có tuyến | 13.808,57 m; 580 điểm hình tuyến; khoảng 29,9 phút theo tốc độ mô hình. |
| Tới điểm giao đang có (10.7289, 106.6152) | Không có tuyến | 12.704,85 m; 410 điểm hình tuyến; khoảng 26,3 phút theo tốc độ mô hình. |

Điểm vào đường được chọn cách GPS khoảng **71,23 m**. Khoảng tiếp cận này không phải một đường lái xe đã được tính. Thời gian không có dữ liệu giao thông thực tế; chưa đối chiếu tuyến với Google Maps.

Kết quả gọi bộ máy sau khi nạp mạng: khoảng 1,27 giây cho tuyến tới kho, 0,86 giây tới điểm giao trong lượt kiểm tra được ghi lại. Không bảo đảm thời gian xử lý cố định trên mọi máy.

## Áp dụng

1. Ở Visual Studio đang dừng tại ngoại lệ: **Shift+F5** để Stop phiên cũ.
2. Chọn backend chính **LastMile.Api**, profile **http**, rồi **F5** để build/chạy lại và nạp snapshot mới. F5 tiếp tục phiên đang dừng sẽ chưa nạp bản sửa.
3. Stop và chạy lại Flutter để nhận thông báo/đánh dấu đầu tuyến mới.
4. Giữ GPS `10.7769, 106.7009`, làm mới Lộ trình và mở lại chỉ đường. GPS giả lập đứng yên sẽ không tự di chuyển; app chỉ cập nhật tiến độ khi thiết bị gửi vị trí mới.

**Không có SQL/migration mới.** Không chạy lại dữ liệu mẫu. Snapshot mới ở `backend/LastMile/LastMile.Api/Data/roads.osm.gz`, nguồn/hash trong `roads.osm.metadata.json`; file tải và bản cũ được giữ tại `frontend/tests/.artifacts/route-coverage` để đối chiếu. Không thay file trong bản backend sao chép dưới `app_shipper`.

## Kiểm chứng và giới hạn

- **61/61** kiểm tra định tuyến/lập kế hoạch: tái hiện trước/sau bằng GPS thật được gửi; đường một chiều, cấm rẽ, quyền xe, lịch chưa hiểu, lịch ngoài mùa, qua đêm, điều kiện tương lai, điểm ngoài vùng và nhánh cụt.
- **6/6 nhóm HTTP/SQL** riêng cho API tuyến trên database GUID tự xóa: đúng tài xế, lấy/giao đúng bước, GPS báo cáo, lỗi JSON, thu hồi quyền/bưu cục, giữ nguyên hình tuyến và thứ tự admin.
- **51/51 Flutter** trong nhóm bản đồ/chỉ đường/chuyến giao; analyzer không có vấn đề. API build 0 cảnh báo/lỗi; APK Android debug x86_64 build đạt.
- Kiểm thử rộng toàn app hiện **265 đạt / 19 chưa đạt**: màn Trang chủ bị tràn ngang và kiểm thử Nhận kiện/Quét mã không còn khớp giao diện hiện tại. Các file giao diện này đã được sửa riêng trước lượt sửa bản đồ; không ghi đè chúng trong bản sửa này.
- Bộ tích hợp toàn bộ dừng trước các kiểm tra tuyến vì `/delivery-success` trả 500 `DELIVERY_SUCCESS_NOT_COMMITTED` ở ca gửi đồng thời. Chưa kết luận hoặc sửa nguyên nhân lỗi giao thành công trong lượt sửa chỉ đường; bộ kiểm tra API tuyến riêng phía trên chạy đủ và đạt.
- Chưa điều khiển hoặc chạy app trên thiết bị/máy ảo trong lượt sửa. Không cập nhật database vận hành; dữ liệu API ghi chỉ trong database GUID thử và đã dọn.

Nhật ký và kết quả nằm tại `frontend/tests/.artifacts/route-coverage/verification.json`, `routing-tests.log`, `route-api.log`, `flutter-map-tests.log`, `flutter-tests.log`, `integration.log`, `api-build.log`, `android-build.log`.
