# RAID VM Toolkit — bảng điều khiển tiếng Việt

Dành cho Tuấn dùng **máy ảo Windows 11 x64 để chạy RAID: Shadow Legends qua Plarium Play**. Một lệnh mở toàn bộ công cụ; chọn chức năng bằng nút bấm, không phải nhớ từng lệnh riêng.

## Mở bằng một lệnh

Trong **máy ảo**, mở **Windows PowerShell**, bằng đúng tài khoản đang đăng nhập Desktop, rồi dán:

```powershell
irm 'https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup/3e56dc22178e47c571479496c7efb2162c0de1c3/Start-RAID-Toolkit.ps1' | iex
```

Không cần tải ZIP, Git, GitHub Desktop hoặc cài bộ SDK. Máy ảo cần Internet để tải công cụ và bộ cài được chọn. Lệnh chỉ mở bảng điều khiển, chưa tự cài, gỡ hay đổi thiết lập. Các tác vụ cần quản trị sẽ yêu cầu UAC; dùng đúng tài khoản Windows hiện tại.

**Bản sửa khởi chạy 1.0.1:** chỉ báo đã mở khi cửa sổ WinForms đã hiện và trả trạng thái sẵn sàng. Nếu cửa sổ lỗi, tiến trình thoát hoặc chờ quá 20 giây, PowerShell báo lỗi kèm đường dẫn nhật ký. Bản này cũng tránh bị phiên giao diện ẩn của bản cũ chặn lại.

Chỉ chạy trong máy ảo. Công cụ chặn tên máy thật đã biết trong phiên thiết lập này; đây không phải cơ chế nhận diện mọi máy thật.

## Các chức năng

| Mục | Thực hiện |
| --- | --- |
| **1. Dọn app** | Xem trước hoặc gỡ danh sách app Windows tiêu dùng, Store/Xbox và thử gỡ OneDrive bằng bộ gỡ có chữ ký Microsoft. |
| **2. Cài phần mềm** | Tích chọn Chrome, WinRAR x64, .NET Desktop Runtime 8 x64, Visual C++ v14 x86 và x64. Không chạy dọn app ở mục này. |
| **3. Windows Update** | Đọc trạng thái, đặt chính sách chặn cập nhật tự động, hoặc khôi phục thiết lập đã sao lưu. |
| **4. Tối giản giao diện** | Start/icon sang trái; ẩn Widgets/thời tiết, Search và Task View; giảm hiệu ứng, tắt trong suốt, nền tối trơn. |
| **5. Khôi phục giao diện** | Trả lại các thiết lập giao diện đã lưu. Không cài lại app đã gỡ. |
| **6. Công cụ riêng** | Mở cửa sổ riêng chạy lệnh bên thứ ba đã được người dùng yêu cầu. |
| **9. Làm nhanh** | Cài các mục đã chọn → dọn app → tối giản giao diện. Không ghép chặn Update hoặc công cụ riêng. |

Cửa sổ có tiến trình đang thực hiện, kết quả từng bước và nút **Mở nhật ký**. Tác vụ chạy trong tiến trình riêng để cửa sổ vẫn phản hồi. Khi đang chạy, các nút thực hiện bị khóa để tránh chạy trùng. Không tự khởi động lại máy ảo.

## Trước khi dọn hoặc tối giản

- Tạo **snapshot khi máy ảo đã tắt** trước lần dọn đầu tiên. Gỡ app có thể xóa dữ liệu của app đó; nhật ký không phải bản sao lưu phục hồi.
- Chọn **Xem trước danh sách** ở mục 1 trước khi gỡ. Bản này gỡ Store/Xbox nên không dùng cho máy cần Xbox/Game Pass hoặc cài game qua Microsoft Store.
- Hoàn tất việc chép file trước mục **4, 5 hoặc 9**: Explorer được tải lại để nhận thiết lập, các cửa sổ File Explorer có thể đóng.
- Trong **Làm nhanh**, nếu cài phần mềm chưa hoàn tất, công cụ dừng trước bước dọn app. Nếu một mục giao diện bị chặn, các mục khác vẫn được xử lý và kết quả báo một phần.

Script dọn giữ RAID/Plarium Play, Steam nếu có, driver, Guest Additions phục vụ chuột/copy-paste, DirectX, .NET, Visual C++, WebView2, App Installer, codec, Defender, Windows Update và thành phần lõi Windows. Không ép gỡ Edge hoặc xóa thư mục hệ thống. Không chủ động xóa thư mục dữ liệu OneDrive.

Dọn app hoặc tắt hiệu ứng không bảo đảm tăng FPS hay sửa lỗi chuột/driver. Công cụ không tự đổi cấu hình VirtualBox và không cài RAID/Plarium Play.

## Cài phần mềm và thư viện

- Bộ cài từ Google, RARLAB và Microsoft; kiểm tra chữ ký Authenticode và nhà phát hành trước khi chạy. .NET được đối chiếu thêm SHA-512 trong metadata Microsoft.
- Các bộ cài cần dùng được tải và xác minh trước khi bắt đầu cài. Nếu bước chuẩn bị/xác minh lỗi, chưa khởi chạy bộ cài nào của lần đó.
- Nếu một bộ cài lỗi trong giai đoạn cài, các bộ cài độc lập còn lại vẫn được thử và có kết quả riêng. Phần mềm đã cài thành công trước lỗi không tự được gỡ lại.
- Giữ bản Chrome/WinRAR và dòng runtime 8.0.x/14.x đã có; công cụ không phải trình cập nhật phiên bản vá cho phần mềm hiện có.
- **WinRAR là bản dùng thử**, không kèm bản quyền hoặc công cụ kích hoạt WinRAR.
- **.NET Desktop Runtime 8 x64** phục vụ phần mềm cần đúng phiên bản 8; không cài SDK. .NET 8 hết hỗ trợ ngày **10/11/2026**. Giữ runtime cần thiết và theo dõi cập nhật từ hãng phần mềm. [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)
- **Visual C++ v14 x86/x64** là dòng runtime dùng chung cho các ứng dụng tương thích xây bằng Visual Studio 2015 trở đi. Chưa gộp các runtime 2005–2013 hoặc .NET Framework 3.5 vào bộ này; cài riêng khi phần mềm cũ yêu cầu. [Microsoft VC++](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)

## Windows Update: phạm vi và khôi phục

Mục 3 chỉ quản lý chính sách `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoUpdate`. Không tắt BITS, WaaSMedic, Defender, không sửa quyền dịch vụ/registry, không chặn mạng Microsoft.

- Dùng trên các phiên bản Windows hỗ trợ chính sách tương ứng như Pro, Enterprise, Education và IoT; **Windows Home bị từ chối thao tác chặn**.
- Đây là **chặn cập nhật tự động bằng chính sách**, không bảo đảm ngăn mọi cách cập nhật hoặc chặn vĩnh viễn. Cập nhật thủ công và chính sách quản trị mạnh hơn có thể vẫn áp dụng. Thao tác chặn có thể ngừng nhận bản vá bảo mật tự động.
- Lưu trạng thái gốc một lần trước khi đổi; chạy chặn lại không ghi đè bản gốc. **Khôi phục** trả đúng trạng thái trước khi công cụ chỉnh. Nếu ban đầu đã bị chặn, khôi phục vẫn giữ trạng thái chặn ban đầu.
- Nếu MDM đặt bỏ qua các chính sách Windows Update từ Group Policy, công cụ báo không hỗ trợ thay vì báo đã chặn thành công.

[Microsoft: cấu hình Automatic Updates bằng registry](https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings#configuring-automatic-updates-by-editing-the-registry)

## Tiếng Việt và các mục bị Windows chặn

Phần khởi chạy dùng chữ ASCII, tải mã dưới dạng byte và giải mã UTF-8 rõ ràng. Các script lưu cục bộ dưới dạng UTF-8 BOM cho Windows PowerShell 5.1. Cửa sổ dùng font Segoe UI và thông báo chính bằng tiếng Việt; nhật ký kỹ thuật có thể chứa lỗi bằng ngôn ngữ của Windows. [Microsoft: PowerShell character encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1)

Một thiết lập không ghi được sẽ có kết quả lỗi riêng; không đổi quyền registry để ép ghi. Nếu Widgets/thời tiết còn hiện và kết quả nhắc `TaskbarDa`, vào **Settings → Personalization → Taskbar → Widgets → Off**. Windows tiếng Nhật: **設定 → 個人用設定 → タスク バー → ウィジェット**. [Microsoft: taskbar](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-taskbar-in-windows)

## Công cụ riêng ở mục 6

Chỉ khi chủ động chọn mục 6 và xác nhận, công cụ mở cửa sổ PowerShell riêng chạy `irm https://get.activated.win | iex`, theo yêu cầu người dùng trước đó. Đây là mã bên thứ ba từ get.activated.win/Massgrave, có thể yêu cầu quyền quản trị. Không tự chọn phương thức hoặc khẳng định kích hoạt thành công. Khôi phục giao diện không hoàn tác thay đổi của công cụ ngoài. Chưa thực thi công cụ này trong kiểm thử.

## Sao lưu và nhật ký nằm ở đâu?

| Nội dung | Vị trí |
| --- | --- |
| Bộ công cụ đã kiểm tra | `%LOCALAPPDATA%\RaidVM-Toolkit\Releases\<commit>` |
| Yêu cầu, kết quả JSON và log từng lần chạy | `%LOCALAPPDATA%\RaidVM-Toolkit\Runs\<ngày-giờ-mã>` |
| Trạng thái và lỗi khởi chạy cửa sổ | `%LOCALAPPDATA%\RaidVM-Toolkit\Launches\<ngày-giờ-mã>` |
| Sao lưu giao diện | `%LOCALAPPDATA%\RaidVM-UI\desktop-before.json` |
| Sao lưu chính sách Update | `C:\ProgramData\RaidVM-Toolkit\Update\before.json` |
| Bộ cài/nhật ký cài phần mềm | `C:\ProgramData\RaidVM-Toolkit\Install\<ngày-giờ-mã>` |
| Danh sách app trước/sau khi dọn | `C:\ProgramData\RaidVM-Cleanup\<ngày-giờ>` |

Bản sao lưu giao diện từ menu cũ vẫn dùng được. Khi khôi phục lỗi một phần, bản sao lưu tiếp tục được giữ để thử lại. Không tải nhật ký hoặc bản sao lưu cá nhân lên repo công khai.

## Trạng thái kiểm tra

Đã kiểm tra trên Windows PowerShell 5.1: cú pháp, hiển thị WinForms tiếng Việt, xử lý UTF-8/BOM, truyền tham số và kết quả qua tiến trình con, hash/cache bộ khởi chạy, luồng Làm nhanh, lỗi từng bước và sao lưu/khôi phục. Các thao tác cài/gỡ và chặn cập nhật được kiểm thử bằng mô phỏng; phần registry thử nghiệm chỉ dùng khóa thử riêng. Đã chạy thực tế chức năng chỉ đọc trạng thái Update và xem trước bộ cài.

**Chưa chạy toàn bộ cài/gỡ/chặn cập nhật trong máy ảo kiểm thử**, chưa chứng minh tăng hiệu năng hoặc tương thích mọi bản Windows/game. Ảnh xem thử giao diện không phải bằng chứng đã tối ưu máy ảo.

## Các tệp trong repo

- `Start-RAID-Toolkit.ps1`: một điểm khởi chạy; tải bản cố định và kiểm tra mã băm trước khi mở cửa sổ.
- `Toolkit.manifest.json`: danh sách sáu module và SHA-256 văn bản đã chuẩn hóa.
- `RAID-Toolkit.ps1`: cửa sổ WinForms tiếng Việt.
- `Invoke-RAID-Task.ps1`: tác vụ nền, kiểm tra tài khoản/quyền và ghi kết quả.
- `Install-RAID-Apps.ps1`, `Debloat-Win11-RAID.ps1`, `Manage-RAID-Update.ps1`, `Optimize-RAID-UI.ps1`: các chức năng độc lập.
- `Setup-RAID-VM.ps1`: lệnh cũ cài Chrome/WinRAR rồi dọn, giữ để tương thích. Bảng điều khiển mới không gọi luồng gộp này.

Mã băm giúp kiểm tra bản tải có đúng bộ tệp đã cố định; đây không phải chữ ký số Microsoft cho script của repo. Lệnh khởi chạy tải và thực thi mã từ repo này.
