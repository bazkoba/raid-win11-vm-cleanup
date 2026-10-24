# Đối chiếu và tối ưu dịch vụ cho RAID VM

Bản này dành cho máy ảo Windows 11 chạy RAID qua Plarium Play. Giữ nguyên giao diện sáng/tối, hình nền và màu sắc hiện tại; phần giao diện chỉ chỉnh taskbar và giảm hiệu ứng. Danh sách dịch vụ được viết riêng, không chạy hay nhúng mã từ các công cụ tham khảo.

## Nguồn đã đối chiếu

Kiểm tra mã nguồn ngày 24/10/2026, tại các commit cố định:

| Nguồn | Phiên bản đã đọc | Kết luận chính |
| --- | --- | --- |
| [optimizerDuck](https://github.com/itsfatduck/optimizerDuck/tree/3b5b568e71752a61409d6ff6cecfaaddb499d024) | `3b5b568e` — GPL v3 | Có ý tưởng tốt về ghi cấu hình gốc, phân biệt lỗi và xác minh khi hoàn tác. Danh sách 239 mục là cấu hình tổng quát, có cả dịch vụ tích hợp máy ảo; không đưa nguyên danh sách vào toolkit. |
| [zeemerry/windows11-service-optimizer](https://github.com/zeemerry/windows11-service-optimizer/tree/637e39402f4d4bc646fade9fc833a6aafa1e7cd7) | `637e3940` — MIT | Các script chức năng trùng từng byte với repo rezaworks bên dưới; không phải một engine độc lập thứ hai. |
| [rezaworks/windows11-service-optimizer](https://github.com/rezaworks/windows11-service-optimizer/tree/8117807b464f404bff8de8e2e664e66c6072bf6e) | `8117807b` — MIT | Script dùng danh sách 29 dịch vụ, ép dừng và ẩn lỗi; không có backup/restore cấu hình. Thông báo thành công không dựa trên việc đọc lại trạng thái. |

Một số liên kết “Releases/Issues” trong README zeemerry cùng trỏ tới ZIP. Không dùng ZIP đó làm dependency; chưa thực thi hoặc kiểm tra nội dung để kết luận về độ an toàn của nó. Toolkit chỉ tham khảo cách thiết kế, không sao chép mã GPL hay phát hành lại bộ cài của các repo này.

## Các nhóm trong toolkit

**Mặc định chỉ chọn `OptionalWindows` và `Xbox`.** Có thể bỏ chọn từng nhóm trước khi xem trước hoặc áp dụng.

| Nhóm | Dịch vụ có thể được xử lý nếu tồn tại | Chức năng có thể mất |
| --- | --- | --- |
| `OptionalWindows` — mặc định | Fax, MapsBroker, RetailDemo, RemoteRegistry, WMPNetworkSvc | Fax, bản đồ ngoại tuyến, demo cửa hàng, quản trị Registry từ xa, chia sẻ thư viện media. |
| `Xbox` — mặc định | XblAuthManager, XblGameSave, XboxGipSvc, XboxNetApiSvc | Đăng nhập/lưu game/kết nối Xbox và hỗ trợ phụ kiện Xbox. Bỏ chọn nếu dùng Game Pass, game Xbox hoặc phụ kiện cần các dịch vụ này. |
| `Printing` — tự chọn | Spooler, PrintNotify | In ấn, gồm các máy in ảo cần Print Spooler như Microsoft Print to PDF. |
| `Search` — tự chọn | WSearch | Lập chỉ mục và một số kết quả tìm kiếm nhanh. Ô Search trên taskbar được ẩn riêng, không cần tắt dịch vụ này để ẩn ô tìm kiếm. |
| `ConnectedDevices` — tự chọn | CDPSvc và các instance CDPUserSvc hiện có | Một số trải nghiệm kết nối/chia sẻ giữa thiết bị. Không sửa template dịch vụ theo người dùng; instance có thể thay đổi sau khi đăng nhập lại. |
| `Diagnostics` — tự chọn | DiagTrack, dmwappushservice | Một số chức năng chẩn đoán, gửi dữ liệu và quản lý thiết bị liên quan. |

Dịch vụ thiếu được bỏ qua; mục đã tắt và dừng không bị ghi lại. **Xem trước** đọc startup và trạng thái thật của từng dịch vụ, không đổi cấu hình. **Áp dụng** đặt Disabled và dừng các mục đủ điều kiện. Nếu dịch vụ khác còn phụ thuộc, toolkit giữ nguyên hoặc báo chưa hoàn tất, không ép dừng dây chuyền.

Danh sách cho phép không chứa Guest Additions/Vektor, VMware Tools, Hyper-V integration, mạng, âm thanh, input, driver, Defender/firewall, Windows Update/BITS, cài đặt phần mềm hoặc thành phần lõi Windows. Tùy chọn Windows Update của toolkit là chức năng riêng, không tự ghép vào tối ưu dịch vụ.

## Sao lưu và khôi phục

Backup dịch vụ nằm tại `C:\ProgramData\RaidVM-Toolkit\Services\before.json`, có định danh Windows và tên máy. Cấu hình gốc gồm kiểu khởi động, giá trị delayed start và trạng thái Running/Stopped. Engine lưu backup trước lần sửa đầu tiên, dùng file tạm và thay thế nguyên tử; khóa tác vụ giúp tránh hai lần Apply/Restore chạy đồng thời.

**Khôi phục dịch vụ** dùng cấu hình đã lưu của Windows đó, không dùng một danh sách “mặc định Windows” cố định. Mục lỗi giữ trạng thái chờ để thử lại. Không xóa file backup khi còn mục chưa khôi phục; không chép backup dịch vụ sang một bản Windows khác. Một dịch vụ bị gỡ hoặc một instance theo người dùng không còn tồn tại có thể tiếp tục báo cần xử lý, thay vì bị tự tạo lại.

Cờ delayed start được khôi phục theo dữ liệu đã lưu; việc khởi động trễ áp dụng ở lần bật Windows sau. Trạng thái đặc biệt “Disabled nhưng vẫn Running” được giữ nguyên khi xem trước/áp dụng, vì thao tác khởi chạy thông thường không thể tái tạo nó để khôi phục. [Microsoft: delayed auto-start](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/ns-winsvc-service_delayed_auto_start_info).

## Giới hạn thực tế

Tắt thêm nhiều dịch vụ không chứng minh máy nhanh hơn. Dịch vụ Manual/trigger-start đang dừng thường không dùng tài nguyên như một tiến trình đang chạy. Chưa có đo FPS, RAM hoặc độ trễ trước/sau trên máy ảo của người dùng; các bài kiểm tra mô phỏng chỉ xác minh luồng xử lý và backup/restore.

Nếu chuột phải mất 3–5 giây mới hiện, cần đo CPU, ổ đĩa, RAM của cả host và guest, tải của các VM khác và tình trạng Guest Additions. Giới hạn FPS trong RAID và phân bổ CPU/RAM phù hợp có thể quan trọng hơn số dịch vụ Disabled. [Microsoft: dịch vụ tự khởi động và delayed start](https://learn.microsoft.com/en-us/windows/win32/services/automatically-starting-services).
