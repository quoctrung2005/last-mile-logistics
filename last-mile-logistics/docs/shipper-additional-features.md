# Theo dõi bảng chức năng bổ sung

Đây là bảng phụ gom 11 nhu cầu bổ sung. **Danh sách chính để tiếp tục triển khai là [bảng gốc 40 chức năng](shipper-functions-40.md)**. STT trong bảng phụ không thay thế STT bảng 40: mục 1 dưới đây tương ứng STT 9; mục 2 tương ứng STT 13; giao thành công và bằng chứng vừa hoàn thiện thuộc STT 22–23.

| Mục | Chức năng | Trạng thái hiện tại |
| --- | --- | --- |
| 1 | Thời gian nhận nhiệm vụ, hạn đến kho | Đã bổ sung: điều phối đặt/sửa/bỏ hạn riêng, chưa đặt không báo trễ, phân biệt nhận nhiệm vụ và nhận kiện. Xem [chi tiết](shipper-task-timing.md). |
| 2 | Thời gian nhận kiện, vị trí/tình trạng lúc nhận | Đã hoàn thiện STT 13: giờ nhận máy chủ, tình trạng, GPS nếu có, ảnh và biên nhận riêng; app/admin/kho xem theo quyền. Xem [nhận kiện](shipper-pickup-condition.md). |
| 3 | Thời gian giao, hạn và từng lần giao | Đã có hạn giao, lịch sử từng lần và biên nhận bước 11; còn phần xử lý/chính sách thời gian bổ sung. |
| 4 | Hạn trả hàng về kho | Chưa thêm hạn trả có cấu hình/gia hạn. Đã có cơ chế giữ hàng hoàn để trả cuối ca, không chặn chuyến mới. |
| 5 | Quy định hoàn trả hàng | Đã có chuyển hoàn và kho nhập nhận thực tế; còn hoàn thiện hướng dẫn/chính sách và minh chứng khi trả. |
| 6 | Bằng chứng giao thất bại và kho xử lý | Đã có lý do/ghi chú/ảnh và chia sẻ admin; chưa có đầy đủ các bước yêu cầu bổ sung/xử lý hồ sơ bằng chứng riêng. |
| 7 | Báo hư hại/mất hàng | Đã có hồ sơ sự cố lúc lấy hàng (STT 15), ảnh và phản hồi kho; báo mất/hư trong quá trình vận chuyển và xác định trách nhiệm vẫn cần bổ sung. |
| 8 | Xử lý đền bù và giải trình | Chưa triển khai. Không tự trừ COD/thu nhập khi vừa báo sự cố. |
| 9 | Tiền công theo đơn | Chưa có cấu hình, mức chốt theo phân công hoặc ghi nhận tiền công. Không lấy phí vận chuyển làm tiền công. |
| 10 | Tiền công giao lại/hoàn hàng | Chưa có chính sách và dữ liệu chi trả riêng. |
| 11 | Ví thu nhập tài xế | Chưa có sổ thu nhập/duyệt/thanh toán. Ví COD hiện tại chỉ là thu hộ, tách khỏi mục này. |

Các phần ghi Đã có nền chưa được tuyên bố đã hoàn tất toàn bộ chức năng bổ sung. Những mục tiếp theo triển khai theo thứ tự người dùng yêu cầu.
