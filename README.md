| Biến       | Ý nghĩa                                              | Dùng để làm gì                           |
| ---------- | ---------------------------------------------------- | ---------------------------------------- |
| `dx`       | Độ dịch chuyển tức thời theo trục X từ lần đọc trước | Tính vận tốc/trôi ngang X                |
| `dy`       | Độ dịch chuyển tức thời theo trục Y từ lần đọc trước | Tính vận tốc/trôi ngang Y                |
| `flowX`    | Tổng cộng dồn của nhiều `dx`                         | Theo dõi vị trí tương đối X              |
| `flowY`    | Tổng cộng dồn của nhiều `dy`                         | Theo dõi vị trí tương đối Y              |
| `squal`    | Chất lượng bề mặt/ảnh mà sensor thấy                 | Kiểm tra sensor có bám mặt đất tốt không |
| `shutter`  | Thời gian phơi sáng nội bộ của cảm biến              | Đánh giá ánh sáng/nền có đủ tốt không    |
| `maxPixel` | Giá trị pixel sáng nhất trong frame                  | Đánh giá ảnh quá tối/quá sáng            |
| `overflow` | Báo dữ liệu chuyển động bị tràn/mất                  | Nếu có thì bỏ sample đó                  |

dx, dy

dx và dy là dịch chuyển mới nhất mà ADNS-3080 đo được giữa hai lần đọc. Ví dụ:

dx = 5, dy = -2

nghĩa là ảnh bề mặt đã dịch 5 count theo X và -2 count theo Y so với lần trước.

Với drone, thường dùng dx/dy để ước lượng vận tốc:

velocityX ≈ dx / dt
velocityY ≈ dy / dt

Nhưng để ra vận tốc thật theo m/s, bạn còn cần độ cao. Bay càng cao thì cùng một dx tương ứng với quãng đường thật càng lớn.

flowX, flowY

flowX và flowY không phải dữ liệu trực tiếp từ sensor. Đây là biến trong code của bạn:

flowX += dx;
flowY += dy;

Nó là tổng dịch chuyển tương đối từ lúc bạn clear motion hoặc reset code. Trong test serial, nó giúp bạn thấy sensor có đang cộng dồn đúng không.

Ví dụ:

Lần 1: dx = 3  -> flowX = 3
Lần 2: dx = 4  -> flowX = 7
Lần 3: dx = -2 -> flowX = 5

Với drone giữ vị trí, flowX/flowY có thể dùng như “vị trí tương đối tạm thời”, nhưng quan trọng hơn vẫn là dùng dx/dy để tạo velocity hold.

squal

squal là Surface Quality. Nó đo số lượng đặc điểm/texture hợp lệ mà sensor nhìn thấy trong frame hiện tại. Datasheet nói số đặc điểm hợp lệ xấp xỉ bằng:

features = squal * 4

Giá trị squal gần 0 thường nghĩa là không có bề mặt, quá xa, sai focus, thiếu sáng, hoặc nền quá trơn; datasheet cũng nói SQUAL thường cao nhất khi bề mặt ở đúng khoảng cách focus tối ưu.

Gợi ý dùng cho drone:

if (squal < 15) {
  // Không tin dữ liệu flow
}

Khi test tốt trên giấy/vải, bạn có thể thấy squal khoảng vài chục đến hơn 100 tùy bề mặt và ánh sáng.

shutter

shutter là thời gian phơi sáng nội bộ của cảm biến, tính theo clock cycles. ADNS-3080 tự điều chỉnh shutter để giữ độ sáng ảnh trong vùng bình thường. Datasheet nói shutter được điều chỉnh mỗi frame trong chế độ mặc định.

Hiểu đơn giản:

shutter thấp  -> ảnh đủ sáng, sensor không cần phơi lâu
shutter cao   -> ảnh tối hoặc bề mặt khó nhìn, sensor phải phơi lâu hơn

Với drone, nếu shutter tăng quá cao và squal thấp, dữ liệu flow dễ kém tin cậy.

maxPixel

maxPixel là giá trị pixel sáng nhất trong ảnh mà sensor đang thấy. Nó giúp đánh giá ảnh có bị tối/quá sáng không.

Cách hiểu thực tế:

maxPixel quá thấp  -> ảnh tối, LED yếu, quá xa mặt đất, sai focus
maxPixel quá cao   -> ảnh quá sáng/chói, có thể bão hòa
maxPixel vừa phải  -> ảnh có khả năng tracking tốt hơn

Không nên chỉ dùng maxPixel một mình. Hãy xem cùng squal và shutter.

overflow

overflow nghĩa là sensor phát hiện chuyển động quá lớn hoặc dữ liệu delta bị tràn trước khi MCU đọc kịp. Trong code của bạn, bit này là 0x10 của thanh ghi Motion.

Khi overflow = 1, không nên dùng dx/dy của sample đó cho điều khiển drone:

if (overflow) {
  // bỏ sample
  // clear motion
}

Vì lúc này dữ liệu đã có khả năng mất một phần chuyển động.
