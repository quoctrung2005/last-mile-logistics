# Bảng gốc 40 chức năng app shipper

Đây là danh sách tổng hợp 40 chức năng đã đưa ra trong cuộc trao đổi, là **danh sách chính để theo dõi triển khai**. Bảng 11 chức năng bổ sung là bảng phụ, không thay thế hoặc đánh lại STT của bảng này.

## Đối chiếu phần vừa triển khai

| STT bảng 40 | Chức năng | Kết quả đang có |
| --- | --- | --- |
| 9 | Thời gian nhận nhiệm vụ | Đã bổ sung hạn đến kho do điều phối đặt/sửa/bỏ; chưa đặt không báo trễ. Cần migration hạn lấy hàng khi áp dụng vào database đang dùng. |
| 10 | Danh sách, chi tiết nhiệm vụ | Đã làm các chặng danh sách và chi tiết; có mốc thời gian, lịch sử và xem bằng chứng theo quyền. |
| 11 | Đến kho lấy hàng | Đã có mở bản đồ trong app đến kho của nhiệm vụ. Đây là mục 11 gốc, không phải giao thành công. |
| 12 | Xác nhận nhận kiện | Đã có kiểm tra nhãn/đủ kiện, xác nhận nhận thực tế, xuất kho và chuyển đi giao. |
| 13 | Thời gian, tình trạng lúc nhận kiện | Đã bổ sung tình trạng có cấu trúc, GPS tùy khả năng lấy vị trí, ảnh lúc nhận và biên nhận riêng; app/admin/kho xem theo quyền. Hư hại sẵn cần ảnh + mô tả. Cần migration biên nhận nhận kiện. Xem [chi tiết](shipper-pickup-condition.md). |
| 14 | Quét mã kiện | Đã có camera quét/đối chiếu mã đơn hoặc vận đơn, phát hiện nhiều mã, đèn và nhập tay; tải lại nhiệm vụ trước/sau quét, chưa tự xuất kho. Xem [chi tiết](shipper-parcel-scanning.md). |
| 15 | Báo sự cố lấy hàng | Đã có loại sự cố, ảnh/lịch sử, kho yêu cầu bổ sung/phản hồi, chặn nhận/xuất khi hồ sơ mở và chống gửi trùng. Cần migration hồ sơ sự cố. Xem [chi tiết](shipper-pickup-issues.md). |
| 16 | Chuyến giao, thứ tự giao | Đã có danh sách chuyến đang làm/lịch sử, tiến độ và toàn bộ điểm theo thứ tự admin; tách giao thành công với hàng chờ trả kho, mở đúng chuyến và ẩn dữ liệu khi thu hồi. Không cần SQL mới. Xem [chi tiết](shipper-trip-overview.md). |
| 17 | Bản đồ, chỉ đường trong app | Đã bổ sung hướng rẽ ước lượng, khoảng cách tới hướng rẽ, bảng chỉ đường riêng; kiểm tra GPS cũ/đến muộn, ghép đường song song, xử lý tính lại lỗi và hủy phản hồi sau dừng. Giữ thứ tự admin; chưa có giọng nói/giao thông trực tiếp. Không cần SQL mới. Xem [chi tiết](shipper-navigation.md). |
| 20 | Hạn giao và thời gian từng lần | Có hạn giao, lịch sử lần giao và các mốc thực tế; còn phần đánh giá/thao tác thời gian bổ sung. |
| 22–23 | Giao thành công và bằng chứng | Đã hoàn thiện người nhận, COD thực thu, ảnh, biên nhận và chống ghi trùng. |
| 27, 29 | Chuyển hoàn và kho nhận hoàn | Đã sửa để kiện chờ trả cuối ca không chặn chuyến mới; vẫn tính tải và chỉ hoàn tất khi kho nhận. Chính sách/hạn trả và ảnh trả kiện còn thiếu. |
| 40 | Mất mạng và chống trùng | Đã bổ sung kiểm tra lại biên nhận nhận kiện/giao thành công; chưa hoàn thiện lưu nháp/hàng đợi ngoại tuyến cho mọi nghiệp vụ. |

Các dòng trên là đối chiếu các phần có tài liệu và kiểm chứng gần đây, không phải kết luận đã kiểm thử lại toàn bộ 40 mục trong lần đọc bảng này. Xem [tiến độ triển khai và tài liệu kiểm chứng](shipper-progress.md).

## Nguyên bản bảng đã chốt

**Cột “Hiện trạng” trong nguyên bản dưới đây là đánh giá tại lúc lập bảng, trước các lần sửa tiếp theo.** Dùng STT/tên chức năng làm danh sách chính; dùng đối chiếu ở trên và tài liệu tiến độ cho phần đã thay đổi.

| STT | Chức năng | Trên app shipper | Trên admin/kho và quy tắc đồng bộ | Hiện trạng |
|---|---|---|---|---|
| 1 | **Đăng nhập, đăng xuất** | Đăng nhập tài khoản tài xế, duy trì phiên và đăng xuất. | Kiểm tra tài khoản đang hoạt động; tài xế chỉ được xử lý nhiệm vụ của mình. | **Đã có** |
| 2 | **Đổi/khôi phục mật khẩu** | Đổi mật khẩu, gửi yêu cầu khôi phục. | Xác thực và cập nhật tài khoản; xử lý phiên đăng nhập theo chính sách. | **Cần thêm giao diện** |
| 3 | **Hồ sơ tài xế** | Xem thông tin cá nhân, bưu cục, giấy phép và phương tiện được phân công. | Quản lý hồ sơ, hiệu lực giấy phép và phương tiện của tài xế. | **Một phần** |
| 4 | **Đăng ký tài xế** | Nhập thông tin, giấy tờ và phương tiện nếu cho phép tự đăng ký. | Nhận hồ sơ, xét duyệt, yêu cầu bổ sung hoặc từ chối có lý do. | **Mới có giao diện** |
| 5 | **Trạng thái làm việc** | Bật/tắt nhận nhiệm vụ; xem trạng thái sẵn sàng hoặc đang giao. | Điều phối thấy trạng thái; kiểm tra công việc đang giữ trước khi cho đổi trạng thái. | **Đã có luồng chính** |
| 6 | **Trang chủ công việc** | Xem số đơn chờ nhận, lấy tại kho, đang giao, giao lại/hoàn và COD cần nộp. | Số liệu lấy từ phân công, đơn hàng và COD thực tế. | **Đã có** |
| 7 | **Thông báo phân công** | Nhận nhiệm vụ mới, xem thông tin trước khi phản hồi. | Gửi đúng tài xế được phân công; nhiệm vụ thu hồi phải cập nhật lại trên app. | **Có khi đang mở app** |
| 8 | **Chấp nhận/từ chối nhiệm vụ** | Nhận nhiệm vụ hoặc từ chối kèm lý do. | Ghi nhận phản hồi; điều phối xử lý lại đơn bị từ chối. Nhận nhiệm vụ chưa đồng nghĩa nhận kiện. | **Đã có** |
| 9 | **Thời gian nhận nhiệm vụ** | Xem lúc phân công, lúc chấp nhận và hạn đến lấy hàng. | Theo dõi thời gian phản hồi, đến lấy đúng giờ hay trễ; quy định hạn lấy hàng. | **Một phần; cần thêm hạn lấy và hiển thị đầy đủ** |
| 10 | **Danh sách, chi tiết nhiệm vụ** | Tìm mã đơn, người nhận, số điện thoại; xem địa chỉ, kiện hàng, COD và ghi chú. | Đồng bộ đúng dữ liệu đơn và phân công hiện hành. | **Đã có luồng chính** |
| 11 | **Đến kho lấy hàng** | Bấm **Đến kho nhận** mở bản đồ trong app đến đúng kho. | Cung cấp kho lấy, địa chỉ, tọa độ và các kiện được phép nhận. | **Đã có** |
| 12 | **Xác nhận nhận kiện** | Kiểm tra mã kiện, xác nhận **Đã nhận kiện hàng** rồi chuyển sang **Đi giao**. | Xuất kho đúng đơn, ghi người giữ kiện và lịch sử; không cần thêm bước kho duyệt bàn giao theo phương án đã chốt. | **Đã có** |
| 13 | **Thời gian, tình trạng lúc nhận kiện** | Xem thời điểm nhận; ghi tình trạng kiện, vị trí và ảnh khi có bất thường. | Máy chủ ghi thời gian xác nhận; lưu bằng chứng kiện hỏng sẵn để đối chiếu trách nhiệm. | **Một phần; cần bổ sung tình trạng, vị trí và ảnh nhận kiện** |
| 14 | **Quét mã kiện** | Quét mã vận đơn bằng camera và đối chiếu với nhiệm vụ. | Chặn nhận nhầm hoặc nhận kiện không thuộc phân công. | **Cần thêm; hiện nhập mã** |
| 15 | **Báo sự cố lấy hàng** | Báo thiếu kiện, sai kiện, kiện hỏng; gửi mô tả và minh chứng. | Kho/điều phối tiếp nhận, phản hồi; báo sự cố không tự xuất kho. | **Có báo lý do; cần thêm ảnh và quy trình phản hồi** |
| 16 | **Chuyến giao, thứ tự giao** | Xem chuyến, danh sách điểm giao và tiến độ; sắp theo thứ tự admin đã lập. | Quản lý chuyến và thứ tự điểm; thay đổi phân công/tuyến phải cập nhật về app. | **Có thứ tự giao; cần hoàn thiện tổng quan chuyến** |
| 17 | **Bản đồ, chỉ đường trong app** | Dẫn đến kho/khách, bám GPS, xem quãng đường còn lại và tính lại khi lệch tuyến. | Cung cấp tuyến đến điểm đang thực hiện, giữ thứ tự giao do điều phối phân công. | **Đã có bản cơ bản; chưa có giọng nói, kẹt xe** |
| 18 | **Theo dõi vị trí tài xế** | Gửi tọa độ, thời gian và độ chính xác trong quá trình làm nhiệm vụ. | Hiển thị vị trí gần nhất, cảnh báo dữ liệu cũ và phục vụ hỗ trợ sự cố. | **Cần bổ sung gửi vị trí liên tục** |
| 19 | **Liên hệ người nhận** | Gọi điện, mở nhắn tin với khách của đơn được giao. | Cung cấp thông tin liên hệ đúng đơn; ghi chú kết quả liên hệ khi cần. | **Đã có thao tác liên hệ** |
| 20 | **Hạn giao và thời gian từng lần giao** | Xem hạn giao, thời điểm thành công/thất bại và số lần giao. | Theo dõi đúng hạn, quá hạn, nguyên nhân chậm; thời gian xác nhận do máy chủ ghi. | **Một phần; cần hoàn thiện hiển thị** |
| 21 | **Xử lý quá hạn, hẹn lại** | Thấy cảnh báo, lịch mới và chỉ dẫn sau khi CSKH xác nhận với khách. | Khách còn nhận: ưu tiên hoặc hẹn lại; khách hủy: xử lý hàng theo nơi đang giữ. Không tự ẩn hoặc tự hoàn chỉ vì quá hạn. | **Cần hoàn thiện trên app** |
| 22 | **Giao thành công** | Nhập người nhận thực tế, COD đã thu và ghi chú; gửi xác nhận. | Cập nhật kết quả, lịch sử và khoản thu hộ; kiểm tra trạng thái hợp lệ trước khi ghi nhận. | **Đã có luồng chính** |
| 23 | **Bằng chứng giao thành công** | Chụp/chọn ảnh, xem trạng thái tải lên và gửi lại khi lỗi. | Lưu ảnh gắn đúng đơn, lần giao, thời gian và người thực hiện để tra cứu. | **Cần thêm trên app** |
| 24 | **Báo giao thất bại** | Chọn lý do, mô tả, gửi ảnh khi bắt buộc: không liên lạc được, khách vắng/từ chối, sai địa chỉ, không trả COD, không thể tiếp cận… | Ghi nhận lần giao thất bại; chuyển hồ sơ đến bộ phận xử lý, không tự coi là đã hoàn. | **Đã có luồng chính và gửi ảnh** |
| 25 | **Tiếp nhận, xét minh chứng thất bại** | Theo dõi **Đã gửi – Cần bổ sung – Đang xử lý – Đã có hướng xử lý**; bổ sung minh chứng theo yêu cầu. | Kho/điều phối xem hồ sơ, yêu cầu bổ sung, xác nhận giao lại hoặc đề xuất hoàn; lưu người xử lý và lý do. | **Cần thêm quy trình xét và phản hồi** |
| 26 | **Giao lại** | Xem lịch, hướng dẫn mới và bắt đầu giao lại khi được phép. | Quyết định giao lại, cập nhật lịch/phân công; lưu riêng từng lần giao để đối chiếu. | **Đã có luồng cơ bản** |
| 27 | **Yêu cầu chuyển hoàn** | Gửi lý do, theo dõi duyệt và bắt đầu hoàn khi được phép. | Xác minh, duyệt hoặc từ chối có lý do; chỉ định kho nhận hoàn. | **Đã có luồng cơ bản** |
| 28 | **Hạn trả hàng về kho** | Xem kho phải trả, địa chỉ, hạn trả và cảnh báo trễ. | Cấu hình thời hạn; theo dõi kiện chưa về, gia hạn có lý do và người duyệt. | **Cần thêm** |
| 29 | **Quy định hoàn trả** | Xem yêu cầu giữ nguyên kiện, phụ kiện, chứng từ; ghi tình trạng và ảnh lúc trả. | Kiểm tra số lượng, tình trạng, ghi sai lệch và xác nhận nhập thực tế. **Kho xác nhận nhận kiện mới hoàn tất hoàn hàng.** | **Một phần; cần thêm hướng dẫn và bằng chứng trả kiện** |
| 30 | **Báo hư hại hoặc mất hàng** | Báo mã kiện, thời điểm, vị trí, diễn biến và minh chứng; phân biệt hỏng, thiếu và mất. | Lập hồ sơ sự cố, đối chiếu quá trình giữ kiện, chỉ định bước xử lý; kiện mất không được ghi nhận đã nhập hoàn. | **Cần thêm hồ sơ sự cố chuyên biệt** |
| 31 | **Xử lý đền bù** | Xem kết luận, căn cứ, số tiền đề xuất/được duyệt và gửi giải trình. | Xác minh trách nhiệm, giá trị thiệt hại, phê duyệt và lưu lịch sử. **Không tự quy lỗi hoặc trừ tiền ngay khi tài xế báo sự cố.** | **Cần thêm** |
| 32 | **Sự cố tài xế/phương tiện** | Báo xe hỏng, tai nạn hoặc không thể tiếp tục giao; gửi vị trí và tình trạng kiện. | Hỗ trợ, điều phối người nhận tiếp; ghi rõ thời gian và người giữ kiện khi chuyển giao. | **Cần thêm** |
| 33 | **Ví COD** | Xem tiền thu hộ, còn phải nộp và đang chờ xác nhận. | Theo dõi khoản thu theo đơn và tài xế; đối chiếu chênh lệch. | **Đã có số liệu chính** |
| 34 | **Nộp và đối soát COD** | Tạo phiếu tiền mặt/chuyển khoản, nhập mã tham chiếu; xem kết quả, lý do từ chối. | Kế toán xác nhận hoặc từ chối; tạo phiếu chưa đồng nghĩa đã nộp xong. | **Có tạo phiếu; thiếu lịch sử chi tiết đầy đủ** |
| 35 | **Tiền công theo đơn** | Xem tiền công dự kiến trước khi nhận và tiền công ghi nhận sau giao thành công. | Cấu hình theo dịch vụ, tuyến/quãng đường, phụ cấp, thưởng; lưu mức áp dụng cho lần phân công, điều chỉnh có lý do. | **Cần thêm** |
| 36 | **Tiền công giao lại/hoàn hàng** | Xem khoản được hưởng cho từng công việc nếu chính sách có chi trả. | Cấu hình riêng mức phí và điều kiện hưởng; không mặc định thất bại là mất công hoặc giao lại luôn được cộng thêm. | **Cần thêm** |
| 37 | **Ví thu nhập tài xế** | Xem tiền công **dự kiến – chờ duyệt – được duyệt – đã thanh toán**, chi tiết từng đơn/kỳ. | Duyệt, thanh toán, ghi nhận điều chỉnh riêng. **Tách hoàn toàn tiền công khỏi COD thu hộ.** | **Cần thêm** |
| 38 | **Lịch sử, thống kê cá nhân** | Tra cứu theo ngày, đơn, lần giao, kết quả, bằng chứng, hoàn hàng và tiền công. | Đối chiếu với lịch sử đơn, kho, COD và thanh toán; tài xế chỉ xem dữ liệu của mình. | **Có nhóm đã xong; cần thêm tra cứu chi tiết** |
| 39 | **Trung tâm thông báo** | Xem phân công, đổi tuyến, lịch mới, duyệt hoàn, yêu cầu minh chứng và kết quả COD/thu nhập; đánh dấu đã đọc. | Gửi đúng đối tượng, liên kết thông báo đến đúng hồ sơ; hỗ trợ thông báo khi app chạy nền. | **Một phần; cần thêm trung tâm thông báo và thông báo nền** |
| 40 | **Mất mạng, gửi lại, chống thao tác trùng** | Hiển thị chưa gửi/đang gửi/đã xác nhận; lưu nháp và gửi lại khi có mạng. | Kiểm tra trạng thái hiện hành, chống ghi trùng nhận kiện, kết quả giao, phiếu tiền; không báo hoàn tất khi máy chủ chưa xác nhận. | **Một phần; cần hoàn thiện lưu nháp và gửi lại** |

Các mốc thời gian, minh chứng, tiền công và hồ sơ sự cố cần liên kết với **đúng đơn, lần phân công và lần giao**. Riêng **mức tiền công, hạn trả hàng và cách xác định đền bù** cần được cấu hình thành chính sách trước khi triển khai, vì hiện chưa có mức cụ thể được chốt.

