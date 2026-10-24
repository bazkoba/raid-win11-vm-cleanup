# Dọn Windows 11 cho máy ảo treo RAID

Hướng dẫn dành cho Tuấn dùng máy ảo Windows 11 chạy **RAID: Shadow Legends qua Plarium Play**.

## Trước khi chạy

- Thực hiện **bên trong máy ảo**, mở Windows PowerShell bằng **Run as administrator**.
- Tạo snapshot khi máy ảo đã tắt để có thể quay lại trạng thái trước khi dọn. Gỡ app có thể xóa dữ liệu của app đó; các file CSV trong nhật ký không phải bản sao lưu phục hồi.
- Đóng các app sắp gỡ, hoàn tất cập nhật đang chờ rồi khởi động lại nếu Windows yêu cầu.
- Script có chặn tên máy thật đã biết trong lần thiết lập này. Đây không phải cơ chế nhận diện mọi máy thật; vẫn phải kiểm tra đang thao tác trong máy ảo.

## Menu giao diện: chọn một lần để làm taskbar gọn hơn

Trong **máy ảo**, mở Windows PowerShell bằng tài khoản đang đăng nhập Desktop, rồi dán:

```powershell
irm 'https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup/51440316f462c9d752bb9c35c987afead536eed3/Optimize-RAID-UI.ps1' | iex
```

| Phím | Chức năng của menu giao diện |
| --- | --- |
| **4** | Áp dụng giao diện tối giản |
| **5** | Khôi phục giao diện đã lưu trước khi áp dụng |
| **6** | Mở công cụ MAS bằng lệnh `irm https://get.activated.win \| iex` do người dùng yêu cầu |
| **0** | Thoát |

**Phím 6** mở một cửa sổ PowerShell riêng và chạy đúng lệnh trên. Đây là công cụ bên thứ ba từ `get.activated.win`/Massgrave, có thể yêu cầu quyền administrator; script của repo chỉ mở công cụ, không tự chọn phương thức kích hoạt hay xác nhận kích hoạt thành công. **Phím 5 chỉ khôi phục giao diện, không hoàn tác các thay đổi do MAS thực hiện.** Mục 6 không chạy khi chọn 4 hoặc 5. Chưa chạy công cụ này trên máy thật hoặc máy ảo trong kiểm thử.

**Phím 4 áp dụng cùng lúc:**

- Đưa nút **Start và các icon taskbar về bên trái**, taskbar vẫn nằm dưới màn hình.
- Ẩn **Widgets/thời tiết**, ô **Search** và nút **Task View**.
- Tắt trong suốt, giảm animation và hiệu ứng bóng đổ mà Windows cho phép điều khiển.
- Đổi hình nền sang **màu tối trơn**.
- Giữ chữ dễ đọc, các app đang ghim trên taskbar, game và driver.

**Trước khi chọn 4 hoặc 5:** hoàn tất việc chép file. Script sẽ tải lại Explorer để taskbar nhận thiết lập ngay; các cửa sổ File Explorer có thể đóng. Game không bị script chủ động tắt, nhưng nên áp dụng lúc chưa chơi để tránh gián đoạn thao tác.

Thiết lập gốc được lưu tại `%LOCALAPPDATA%\RaidVM-UI\desktop-before.json`. Áp dụng lại không ghi đè bản gốc khi bản tối giản vẫn đang hoạt động. Phím 5 khôi phục các thiết lập mà script đã chỉnh; không cài lại các app đã bị gỡ bởi script dọn riêng.

Menu này áp dụng cho **tài khoản Windows hiện tại**; không mở PowerShell bằng một tài khoản admin khác. Script có chặn tên máy thật đã biết, nhưng vẫn phải tự kiểm tra đang ở trong máy ảo.

Muốn áp dụng thẳng không hiện menu, **sau khi đã hoàn tất chép file và biết Explorer sẽ được tải lại**, dùng:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup/51440316f462c9d752bb9c35c987afead536eed3/Optimize-RAID-UI.ps1'))) -Action Apply
```

Đổi `Apply` thành `Restore` để khôi phục, hoặc `Preview` để chỉ xem danh sách thay đổi.

Các mục **4/5** của menu chỉ chỉnh/khôi phục giao diện; không gỡ/cài app, không thay đổi sleep hoặc Windows Update. Mục **6** chạy công cụ ngoài theo mô tả trên. Ẩn Widgets không bảo đảm toàn bộ thành phần Widgets ngừng chạy nền; các mục giao diện không ép gỡ gói hệ thống hoặc phần mềm ghim sẵn. Một số hiệu ứng hiện đại hoặc chính sách quản trị có thể không tuân theo thiết lập này.

Đã kiểm tra bằng Windows PowerShell 5.1: cú pháp, biên dịch phần gọi API Windows, các lệnh đọc trạng thái, và sao lưu/khôi phục registry qua JSON (gồm giá trị chưa tồn tại, DWORD, chuỗi, chuỗi mở rộng và dữ liệu nhị phân) trên khóa thử riêng. Chưa thực thi Apply/Restore lên giao diện máy ảo trong kiểm thử; chưa có ảnh xác nhận giao diện sau áp dụng.

## Cách nhanh: một lệnh dọn app + cài Chrome và WinRAR

Trong **máy ảo**, mở Start → tìm **Windows PowerShell** → **Run as administrator**. Tạo snapshot trước khi dọn, rồi dán nguyên dòng này và Enter:

```powershell
irm 'https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup/main/Setup-RAID-VM.ps1' | iex
```

Không cần tải ZIP hoặc chép file ra Desktop. Máy ảo cần Internet: PowerShell tự tải script và bộ cài về `C:\ProgramData\RaidVM-Setup\<ngày-giờ-mã>`, cài Chrome/WinRAR còn thiếu rồi mới dọn các app Windows bên dưới. Bộ cài lấy từ Google và RARLAB, được kiểm tra chữ ký trước khi chạy; bản script dọn được cố định phiên bản và kiểm tra SHA-256. Không tắt Defender hay kiểm tra chứng chỉ mạng.

- Nếu đã có Chrome hoặc WinRAR tại các đường dẫn cài đặt phổ biến, script giữ bản đang có, không tự cập nhật chúng.
- WinRAR được cài ở dạng **dùng thử**, không kèm bản quyền hoặc công cụ kích hoạt. Bản cài WinRAR mới là bản tiếng Anh x64 ổn định.
- Nếu tải, kiểm tra chữ ký hoặc cài tiện ích thất bại, script dừng trước bước dọn app. Một tiện ích có thể đã cài thành công trước khi bước tiếp theo thất bại.
- Dùng Windows PowerShell **64-bit** trên máy ảo Windows 11 **x64**, không áp dụng bản setup này cho ARM64.
- Script không tự cài RAID/Plarium Play và không tự khởi động lại. Chạy một lần trên mỗi máy ảo mới.

Muốn **xem trước**, không cài hoặc gỡ app, dùng dòng này thay cho dòng trên:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup/main/Setup-RAID-VM.ps1'))) -Preview
```

Chế độ xem trước vẫn tải script dọn về thư mục setup để liệt kê các app. Đây là lệnh tải và thực thi mã từ repo này bằng quyền quản trị; có thể mở [Setup-RAID-VM.ps1](Setup-RAID-VM.ps1) để đọc trước. Không cần thay đổi ExecutionPolicy lâu dài.

## Cách thủ công: chỉ dọn app, không cài thêm tiện ích

### 1. Tải script trong máy ảo

1. Mở Chrome hoặc Edge **trong máy ảo** và truy cập repo này. Repo công khai nên có thể xem và tải mà không cần đăng nhập GitHub.
2. Bấm **Code → Download ZIP**.
3. Giải nén ZIP bằng **Extract All / Giải nén tất cả**.
4. Chép riêng file `Debloat-Win11-RAID.ps1` từ thư mục đã giải nén ra **Desktop của máy ảo**.

Không chạy trực tiếp file đang nằm trong ZIP. Không cần cài Git hay GitHub Desktop.

### 2. Mở PowerShell quản trị

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

Các script đã được phân tích cú pháp bằng Windows PowerShell. Đã kiểm tra SHA-256 của bản dọn được tải từ GitHub, đường dẫn tải chính hãng và chữ ký bộ cài WinRAR. Chưa thực thi cài Chrome/WinRAR hoặc gỡ app trên một máy ảo kiểm thử; không có cam kết mọi phiên bản Windows hoặc launcher sẽ hoạt động giống nhau.

- [Microsoft: Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage)
- [Microsoft: Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)
- [Google: Chrome Enterprise download](https://chromeenterprise.google/download/)
- [RARLAB: WinRAR downloads](https://www.rarlab.com/download.htm)
- [Microsoft: Taskbar settings resource](https://github.com/microsoft/winget-dsc/blob/main/resources/Microsoft.Windows.Developer/Microsoft.Windows.Developer.psm1)
- [Microsoft: SystemParametersInfo](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow)

`Debloat-Win11-RAID.ps1` chỉ dọn app. `Setup-RAID-VM.ps1` tải bản dọn đã cố định phiên bản và các bộ cài chính hãng nói trên. Các mục 4/5 trong `Optimize-RAID-UI.ps1` chỉnh giao diện bằng registry/API Windows; riêng mục 6 mở lệnh MAS bên thứ ba do người dùng yêu cầu. Không dùng công cụ chỉnh taskbar của bên thứ ba.
