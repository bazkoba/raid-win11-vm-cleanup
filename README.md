# Dọn Windows 11 cho máy ảo treo RAID

Hướng dẫn dành cho Tuấn dùng máy ảo Windows 11 chạy **RAID: Shadow Legends qua Plarium Play**.

## Trước khi chạy

- Thực hiện **bên trong máy ảo**, mở Windows PowerShell bằng **Run as administrator**.
- Tạo snapshot khi máy ảo đã tắt để có thể quay lại trạng thái trước khi dọn. Gỡ app có thể xóa dữ liệu của app đó; các file CSV trong nhật ký không phải bản sao lưu phục hồi.
- Đóng các app sắp gỡ, hoàn tất cập nhật đang chờ rồi khởi động lại nếu Windows yêu cầu.
- Script có chặn tên máy thật đã biết trong lần thiết lập này. Đây không phải cơ chế nhận diện mọi máy thật; vẫn phải kiểm tra đang thao tác trong máy ảo.

## 1. Tải script trong máy ảo

1. Mở Chrome hoặc Edge **trong máy ảo** và truy cập repo này. Repo riêng tư nên cần đăng nhập tài khoản GitHub có quyền truy cập.
2. Bấm **Code → Download ZIP**.
3. Giải nén ZIP bằng **Extract All / Giải nén tất cả**.
4. Chép riêng file `Debloat-Win11-RAID.ps1` từ thư mục đã giải nén ra **Desktop của máy ảo**.

Không chạy trực tiếp file đang nằm trong ZIP. Không cần cài Git hay GitHub Desktop.

## 2. Mở PowerShell quản trị

Trong máy ảo, mở Start, tìm **Windows PowerShell**, bấm chuột phải → **Run as administrator**. Đồng ý hộp thoại UAC trong máy ảo.

### Xem trước, chưa gỡ gì

Chép nguyên dòng dưới đây vào PowerShell rồi Enter:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\Debloat-Win11-RAID.ps1" -Preview
```

### Gỡ các app đã chọn

Sau khi xem danh sách, chạy dòng này:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\Debloat-Win11-RAID.ps1"
```

Chờ hiện `Cleanup finished` và đường dẫn `Logs:`. Script không tự khởi động lại; sau khi chạy xong, khởi động lại máy ảo rồi mở Plarium Play và kiểm tra RAID.

`-ExecutionPolicy Bypass` ở đây chỉ áp dụng cho tiến trình PowerShell được mở bởi câu lệnh, không thay đổi chính sách lâu dài và không tắt Defender.

## Script gỡ những gì?

Script dùng danh sách tên gói cụ thể để gỡ các app tiêu dùng cài sẵn: Copilot, Teams, Outlook mới, Office Hub, Xbox/Gaming Services, Microsoft Store, Clipchamp, Photos, Paint, Notepad, Calculator, Camera, Maps, Weather, News, Phone Link và các app khác được liệt kê trong file `.ps1`.

Script cũng gỡ các gói dự phòng tương ứng cho tài khoản Windows tạo sau này và thử gỡ OneDrive bằng bộ gỡ có chữ ký Microsoft. Script không chủ động xóa thư mục dữ liệu OneDrive.

**Giữ lại:** RAID, Plarium Play, Steam nếu có, driver, Guest Additions phục vụ chuột/copy-paste, DirectX, .NET, Visual C++, WebView2, App Installer, codec, Defender, Windows Update và thành phần lõi Windows. Edge và các gói Windows được bảo vệ không bị ép gỡ.

Đây là bản dọn mạnh cho RAID qua Plarium Play. Sau khi gỡ Store và Xbox, không dùng bản này cho máy ảo cần Xbox/Game Pass hoặc cài game qua Microsoft Store. Bản thân Windows là phần mềm Microsoft nên không thể xóa toàn bộ thành phần Microsoft mà vẫn giữ Windows hoạt động.

## Dùng cho những máy ảo sau này

- **Chạy một lần sau khi cài Windows và Guest Additions trên mỗi máy ảo mới.** Không cần chạy lại mỗi lần bật máy, không cần đưa vào Startup.
- Có thể tạo một máy ảo mẫu đã dọn xong rồi clone để dùng lại. Cần kiểm tra cài đặt và giấy phép của Windows/game khi clone.
- Sau một bản cập nhật Windows lớn, nếu app xuất hiện lại thì chạy `-Preview` để kiểm tra trước khi dọn lại. Script không bảo đảm app sẽ không được Windows cài lại về sau.
- Dọn app không bảo đảm tăng FPS hay giảm RAM đáng kể; hiệu quả tùy những app trước đó có thực sự chạy nền hay không.

## Nếu gặp lỗi

| Thông báo / tình huống | Cách xử lý |
| --- | --- |
| `requires elevation` / cần quyền quản trị | Đóng cửa sổ rồi mở **Windows PowerShell → Run as administrator** trong máy ảo. |
| Không tìm thấy file `.ps1` | Kiểm tra đã giải nén và chép đúng file ra Desktop của máy ảo; bật hiển thị phần mở rộng để tránh tên `.ps1.txt`. |
| `This is the real host PC` | Script nhận ra tên máy thật đã được chặn. Chuyển file vào máy ảo; không xóa chặn để chạy trên máy thật. |
| Một vài app không gỡ được | Có thể app đang mở hoặc Windows bảo vệ gói đó. Xem nhật ký; không cần ép xóa thư mục hệ thống. |
| RAID/Plarium gặp lỗi sau khi dọn | Quay lại snapshot để đối chiếu; nhật ký CSV không tự khôi phục được app và dữ liệu. |

Nhật ký được lưu trong `C:\ProgramData\RaidVM-Cleanup\<ngày-giờ>`, gồm danh sách trước khi dọn, kết quả từng bước và các app mục tiêu còn lại. Không tải nhật ký lên repo vì có thể chứa thông tin cài đặt riêng của máy ảo.

## Trạng thái kiểm tra và tài liệu

Script đã được phân tích cú pháp bằng Windows PowerShell; chưa chạy gỡ app thực tế trên một máy ảo kiểm thử. Không có cam kết mọi phiên bản Windows hoặc launcher sẽ hoạt động giống nhau.

- [Microsoft: Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage)
- [Microsoft: Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)

Script chỉ thực thi nội dung có trong file, không tải và chạy thêm công cụ dọn hệ thống từ Internet.
