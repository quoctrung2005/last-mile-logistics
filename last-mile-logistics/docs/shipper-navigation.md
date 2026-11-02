# Mục 17 — Bản đồ, chỉ đường trong app

Bổ sung khôi phục GPS ngày 31/10/2026: [luồng xin quyền, lấy lại vị trí và tải lại tuyến](shipper-gps-recovery.md), kèm kết quả kiểm chứng mới nhất.

Bổ sung 31/10/2026: [sửa vùng dữ liệu và lỗi GPS trung tâm](routing-city-coverage-fix.md), gồm kết quả kiểm tra mới và các lỗi kiểm thử chung còn tồn tại.

Cập nhật 30/10/2026, tiếp nối [mục 16 — Chuyến giao](shipper-trip-overview.md) của bảng chính 40 chức năng. Tiếp tục dùng bản đồ/mạng đường hiện có theo phương án người dùng đã chọn; không thêm Navigation SDK hoặc yêu cầu API key.

## Sử dụng

1. Mở **Lộ trình**, hoặc mở bản đồ từ nhiệm vụ/chuyến. Chọn điểm cần xem; thứ tự và số điểm vẫn lấy từ admin.
2. Bấm **Bắt đầu chỉ đường**, cấp quyền vị trí. Bảng hướng dẫn nằm phía trên bản đồ, tách khỏi danh sách kéo lên/xuống nên không che nút dừng.
3. Xem hướng rẽ trái/phải, đổi hướng hoặc đi tiếp đến điểm đến; khoảng cách đến hướng rẽ và quãng đường/thời gian còn lại cập nhật theo GPS.
4. Khi lệch tuyến, app chờ hai vị trí tin cậy rồi yêu cầu tính lại đường từ vị trí hiện tại, có khoảng nghỉ 15 giây giữa các yêu cầu tự động. Có thể chọn **Thử lại tuyến từ vị trí hiện tại** nếu mất mạng hoặc chưa tính được đường.
5. Bấm **Dừng chỉ đường** để trở về xem tuyến. Đến gần đích chỉ nhắc kiểm tra và cập nhật nhận/giao; không tự xác nhận nghiệp vụ.

**Hướng rẽ là ước lượng theo hình tuyến**, chưa có tên đường, chỉ dẫn làn xe, giọng nói hoặc giao thông trực tiếp. Nhãn này được hiển thị ngay khi chỉ đường. Bản đồ hiện tại chưa tương đương Google Navigation; không suy diễn biển báo/luật rẽ từ một góc cong.

## Các lỗi đã xử lý

| Trường hợp | Hành vi sau sửa |
| --- | --- |
| Chỉ hiện “đi theo tuyến màu cam” | Có hướng rẽ và khoảng cách ước lượng; các đỉnh gần nhau thuộc cùng một khúc cong không lặp hướng dẫn. |
| Danh sách điểm che bảng chỉ đường | Bảng chỉ đường nằm riêng phía trên vùng bản đồ, nút dừng vẫn bấm được khi kéo danh sách lên. |
| Thu phóng toàn bộ chuyến dù đang xem một chặng | Khi có tuyến, khung xem ưu tiên hình tuyến, vị trí và điểm đang chọn; các điểm khác vẫn có trên bản đồ. |
| GPS cũ, sai tọa độ hoặc kém chính xác | Kiểm tra tọa độ hữu hạn/trong giới hạn, độ chính xác 0–50 m, tuổi vị trí tối đa 30 giây và không quá 5 giây trong tương lai. Không gửi tọa độ lỗi để tính đường. |
| GPS đến muộn hoặc lặp | Không ghi đè vị trí mới hơn. Có kiểm tra định kỳ khi stream không phát dữ liệu để cảnh báo vị trí đã cũ. |
| Nhiễu GPS gần đường song song/đoạn quay về | Khi đã có tiến độ, ghép đoạn đường xét thêm vị trí đã đi và quãng di chuyển giữa hai GPS; tránh nhảy thẳng tới đoạn cuối của vòng đường. Lần ghép đầu tiên vẫn phụ thuộc vị trí và mạng đường. |
| Lệch tuyến hoặc tính lại đường lỗi | Ngừng hiển thị hướng rẽ, quãng đường và thời gian còn lại của tuyến cũ. Hiển thị cảnh báo và nút thử lại; vị trí mới trong lúc chờ vẫn được giữ. |
| Dừng hoặc chuyển nền lúc tuyến đang tải | Vô hiệu phản hồi đang chờ; không tự vẽ tuyến đến muộn hoặc mở lại stream GPS. Dừng rồi bắt đầu lại khi yêu cầu cũ còn chờ cũng không mở trùng GPS. |
| Nhận kiện / báo sự cố / cập nhật kết quả | Dừng chỉ đường trước khi mở phiếu hoặc chuyển màn; lỗi làm mới nhiệm vụ tiếp tục khóa thao tác từ dữ liệu cũ. |
| Tuyến trả sai bước lấy/giao | App đối chiếu bước với nhiệm vụ hiện tại; yêu cầu dẫn đường trực tiếp không chấp nhận hình tuyến kế hoạch như thể là tuyến từ GPS. |

Hình tuyến cũ có thể còn trên bản đồ để tham khảo khi tính lại lỗi, nhưng không dùng làm hướng dẫn đang có hiệu lực. GPS đến nơi không đồng nghĩa đã nhận kiện/giao thành công. Số điểm và thứ tự admin không thay đổi khi tính lại chặng đường; không có yêu cầu tối ưu lại chuyến hoặc ghi kết quả tự động.

## Phạm vi và áp dụng

- Chỉ sửa Flutter; backend định tuyến, chính sách một chiều/cấm rẽ, dữ liệu OSM và các API ghi nhận/giao/COD giữ nguyên. Xem [bản sửa đi vòng trước đó](routing-detour-fix.md).
- Mạng đường hiện có vẫn có vùng phủ giới hạn và không có dữ liệu kẹt xe. Ngoài vùng phủ hoặc không tìm được đường hợp lệ, app hiển thị lỗi; không vẽ đường thẳng giả làm chỉ đường.
- GPS chỉ phục vụ bản đồ khi màn đang hoạt động, dừng khi app không còn ở foreground/rời màn. Gửi vị trí liên tục cho admin thuộc **mục 18** kế tiếp.
- **Không cần SQL/migration mới.** Stop và chạy lại Flutter để nhận thay đổi. Dùng backend chính đã có các phần trước, không chạy bản backend sao chép trong `app_shipper`.

## Kiểm chứng

- **268/268 Flutter**, thêm 14 kiểm thử về hướng rẽ, vị trí cũ/đến muộn, đường song song, lệch tuyến/mất mạng, phản hồi sau dừng/chuyển nền, nút dừng khi kéo danh sách và màn hẹp/chữ lớn.
- **35/35** kiểm thử trong nhóm bản đồ/lộ trình, đã nằm trong toàn bộ 268 kiểm thử trên; analyzer không có vấn đề.
- APK Android debug x86_64 biên dịch thành công. Không cài/chạy app trên máy ảo hoặc điện thoại; bản đồ/GPS trong kiểm thử dùng ảnh và stream giả lập.
- Không đổi database vận hành hoặc SQL, không chạy lại bộ tích hợp backend trong mục này vì backend không thay đổi. Kết quả API 48 nhóm là lần kiểm tra ở mục 16.

Kết quả máy tại `frontend/tests/.artifacts/navigation-step17/verification.json`, `flutter-tests.log`, `analyze.log`, `android-build.log`. Vẫn cần kiểm tra GPS/di chuyển ngoài thực tế khi người dùng chạy trên thiết bị.

Mục tiếp theo khi người dùng nói **“tiếp”**: **STT 18 — Theo dõi vị trí tài xế**.
