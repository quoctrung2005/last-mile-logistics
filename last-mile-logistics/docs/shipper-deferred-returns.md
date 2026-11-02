# Hàng hoàn chờ trả kho cuối ca, tiếp tục nhận chuyến mới

Cập nhật 30/10/2026 theo xác nhận của người dùng: tài xế có thể giữ các kiện đã chốt hoàn, tiếp tục giao chuyến khác trong ngày và trả kho sau khi hết ca. Không bắt tài xế quay về kho giữa từng chuyến chỉ vì còn một kiện hoàn.

## Quy tắc đã thực hiện

| Trường hợp | Nhận chuyến mới | Trách nhiệm hàng |
| --- | --- | --- |
| Đơn giao thất bại, chưa chốt giao lại hay hoàn | Phải xử lý hướng đi của đơn trước khi kết thúc chuyến | Giữ nguyên nhiệm vụ đang mở |
| Đã duyệt hoàn và tài xế xác nhận chuyển sang chờ trả kho | Được nhận chuyến mới khi công việc giao của chuyến trước đã xong, giấy phép/xe/khu vực/tải phù hợp | Kiện vẫn thuộc tài xế, tiếp tục xuất hiện trong mục hàng chờ trả kho |
| Chuyến vẫn còn đơn đang giao/chờ nhận, hoặc giao lại chưa xong | Chuyến chưa được tự kết thúc để xếp chuyến mới | Xử lý các đơn còn lại theo điều phối |
| Đủ số kiện trên xe nhưng tổng tải hàng mới + hàng hoàn vượt tải hoặc thể tích | Chặn phương án/phân công vượt tải | Không coi hàng hoàn là đã rời xe |
| Kho nhận hàng cuối ca | Kiện hoàn được giải phóng khỏi phần tải đang giữ sau khi kho nhập thực tế | RETURNED và yêu cầu COMPLETED do kho xác nhận |

RETURNING hiện được hiển thị **Chờ trả kho cuối ca**. Đây vẫn là kiện tài xế giữ, không phải kho đã nhận. Không thêm trạng thái database mới hoặc tự chuyển hàng thành RETURNED khi kết thúc chuyến giao. Không đặt một giờ cứng như 17:00, không tự hủy/chốt hoàn theo đồng hồ.

Chuyến giao được hoàn tất trong cùng giao dịch khi đơn cuối giao thành công hoặc chuyển sang chờ trả kho, nếu không còn phân công mở/đơn chưa xử lý/yêu cầu giao lại chưa kết thúc. Trách nhiệm trả kho giữ riêng. Chuyến cũ còn IN_PROGRESS nhưng thực tế chỉ còn những kiện hoàn hợp lệ cũng không chặn xếp chuyến mới; thao tác hoàn tất chuyến hiện có cho phép kết thúc phần giao mà không đóng yêu cầu hoàn.

Nếu chỉ còn hàng chờ trả kho, Sẵn sàng được mở; không còn dùng RETURNING để chặn nút này. Vẫn giữ quy tắc đã có: chưa nhập trả đủ hàng thì chưa chuyển Ngoại tuyến để kết thúc ca.

## Đồng bộ và tính tải

- API trạng thái phân biệt hasDeliveryWork với pendingReturnCount. Hàng hoàn còn giữ vẫn làm hasActiveWork=true, nhưng riêng nó không làm hasDeliveryWork=true.
- Khi hoàn tất công việc giao và không còn việc/chuyến mở khác, trạng thái DELIVERING được đưa về AVAILABLE. Bản ghi cũ còn DELIVERING nhưng không còn việc giao được phép bật Sẵn sàng; điều phối vẫn đánh giá đúng kiện hoàn và chuyến đã xử lý xong.
- Danh sách tài xế lập tuyến hiển thị số kiện hoàn và khối lượng đang giữ. Danh sách chọn xe/phân công đơn lẻ tính cả hàng hoàn vào tải đã chiếm.
- Lập tuyến tự động/thủ công giữ nguyên tải trọng tối đa thật, cộng hàng hoàn vào kiểm tra kg/m³. Phương án trả riêng carriedReturnCount/carriedReturnKg/carriedReturnM3 để không nhầm với tổng hàng mới.
- Phân công từng đơn, đổi người giao và gán đơn vào chuyến thủ công cũng tính kiện hoàn chưa nhập kho. Kiểm tra lại trong giao dịch ghi; thay đổi tải hàng hoàn sau lúc xem phương án làm xác nhận cũ bị từ chối để tính lại.
- Không bỏ hàng hoàn khỏi danh sách, không chuyển trách nhiệm sang kho trước khi kho nhập thực tế, không đưa kiện hoàn vào các điểm giao khách của chuyến mới.

## Kiểm chứng

- Backend build: 0 lỗi, 0 cảnh báo; Flutter analyze không có vấn đề.
- **177/177 Flutter**: gồm trường hợp chỉ còn kiện hoàn vẫn bật Sẵn sàng, Ngoại tuyến bị khóa và dữ liệu số kiện sai không mở thao tác.
- **50/50 định tuyến/lập kế hoạch**: thêm kiểm tra hàng hoàn chiếm tải kg/m³, tự động và thủ công cùng chặn vượt tải, kích thước không biết không trở thành chỗ trống.
- **33 nhóm HTTP/SQL/SignalR** trên database GUID thử: chuyến cũ giao thất bại → duyệt hoàn → chờ trả kho → chuyến cũ kết thúc; xe 12 kg giữ kiện hoàn 8 kg vẫn nhận/giao chuyến mới 3 kg trước khi kho nhận hoàn. Đơn mới 5 kg bị chặn, thiếu kích thước kiện hoàn bị chặn, tải thay đổi sau preview làm confirm cũ bị từ chối. Kiểm tra thêm chuyến cũ còn IN_PROGRESS và nút hoàn tất chuyến; chuyến mới thực sự chưa xong vẫn bận.
- Sau chuyến mới, kiện hoàn vẫn ở ISSUES, trạng thái AVAILABLE, pendingReturnCount=1; không thể Ngoại tuyến. Kho nhập hoàn thì đơn sang DONE, phần tải hoàn được giải phóng.
- API/database thử được dọn; không sửa dữ liệu vận hành, không khởi chạy app hoặc máy ảo của người dùng.

## Áp dụng

Stop và chạy lại backend trong Visual Studio với profile **http**, rồi chạy lại Flutter và làm mới trang admin. Không cần migration hoặc nạp lại dữ liệu mẫu. Với đơn đã RETURNING trên dữ liệu hiện tại, làm mới trạng thái/danh sách điều phối để áp dụng điều kiện mới; không cần giả lập kho đã nhận để mở chuyến tiếp theo.
