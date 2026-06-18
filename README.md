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
