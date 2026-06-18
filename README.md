# ADNS-3080 Optical Flow Sensor

<img width="350" height="350" alt="image" src="https://github.com/user-attachments/assets/7d981546-2c7e-4cba-9180-192404946c97" />

---

## Mục lục

- [Tổng quan các biến](#tổng-quan-các-biến)
- [`dx`, `dy`](#dx-dy)
- [`flowX`, `flowY`](#flowx-flowy)
- [`squal`](#squal)
- [`shutter`](#shutter)
- [`maxPixel`](#maxpixel)
- [`overflow`](#overflow)
- [Gợi ý lọc dữ liệu cho drone](#gợi-ý-lọc-dữ-liệu-cho-drone)
- [Ghi chú thực tế khi test](#ghi-chú-thực-tế-khi-test)

---

## Tổng quan các biến

| Biến | Ý nghĩa | Dùng để làm gì |
| --- | --- | --- |
| `dx` | Độ dịch chuyển tức thời theo trục X từ lần đọc trước | Tính vận tốc hoặc độ trôi ngang theo trục X |
| `dy` | Độ dịch chuyển tức thời theo trục Y từ lần đọc trước | Tính vận tốc hoặc độ trôi ngang theo trục Y |
| `flowX` | Tổng cộng dồn của nhiều giá trị `dx` | Theo dõi vị trí tương đối theo trục X |
| `flowY` | Tổng cộng dồn của nhiều giá trị `dy` | Theo dõi vị trí tương đối theo trục Y |
| `squal` | Chất lượng bề mặt hoặc chất lượng ảnh mà sensor nhìn thấy | Kiểm tra sensor có bám mặt đất tốt không |
| `shutter` | Thời gian phơi sáng nội bộ của cảm biến | Đánh giá ánh sáng hoặc nền có đủ tốt không |
| `maxPixel` | Giá trị pixel sáng nhất trong frame | Đánh giá ảnh đang quá tối hay quá sáng |
| `overflow` | Báo dữ liệu chuyển động bị tràn hoặc bị mất | Nếu có overflow thì nên bỏ sample đó |

---

## `dx`, `dy`

`dx` và `dy` là độ dịch chuyển mới nhất mà ADNS-3080 đo được giữa hai lần đọc dữ liệu.

Ví dụ:

```cpp
dx = 5;
dy = -2;
```

Nghĩa là ảnh bề mặt đã dịch:

- `5 count` theo trục X
- `-2 count` theo trục Y

so với lần đọc trước đó.

Với drone, `dx` và `dy` thường được dùng để ước lượng vận tốc ngang:

```cpp
velocityX ≈ dx / dt;
velocityY ≈ dy / dt;
```

Trong đó:

- `dx`, `dy`: độ dịch chuyển đo được từ sensor
- `dt`: thời gian giữa hai lần đọc
- `velocityX`, `velocityY`: vận tốc tương đối theo trục X/Y

> Lưu ý: Để đổi sang vận tốc thật theo đơn vị `m/s`, cần biết thêm **độ cao bay**. Drone bay càng cao thì cùng một giá trị `dx` sẽ tương ứng với quãng đường thật càng lớn.

---

## `flowX`, `flowY`

`flowX` và `flowY` không phải là dữ liệu trực tiếp từ sensor. Đây thường là biến được tạo trong code để cộng dồn nhiều lần đọc `dx` và `dy`.

Ví dụ:

```cpp
flowX += dx;
flowY += dy;
```

Nó biểu diễn tổng dịch chuyển tương đối kể từ lúc:

- reset code,
- clear motion,
- hoặc bắt đầu quá trình đo.

Ví dụ với `flowX`:

| Lần đọc | `dx` | `flowX` |
| --- | ---: | ---: |
| 1 | `3` | `3` |
| 2 | `4` | `7` |
| 3 | `-2` | `5` |

Với drone giữ vị trí, `flowX` và `flowY` có thể dùng như một dạng **vị trí tương đối tạm thời**. Tuy nhiên, trong điều khiển thực tế, `dx` và `dy` thường quan trọng hơn vì chúng giúp tạo tín hiệu **velocity hold**.

---

## `squal`

`squal` là viết tắt của **Surface Quality**.

Biến này cho biết số lượng đặc điểm hoặc texture hợp lệ mà sensor nhìn thấy trong frame hiện tại. Theo datasheet, số đặc điểm hợp lệ có thể xấp xỉ:

```text
features = squal * 4
```

Giá trị `squal` thấp thường cho thấy sensor đang gặp vấn đề như:

- không nhìn thấy bề mặt rõ,
- drone quá xa mặt đất,
- sai khoảng cách focus,
- thiếu sáng,
- nền quá trơn,
- hoặc bề mặt không đủ texture.

Datasheet cũng cho biết `squal` thường cao nhất khi bề mặt nằm đúng khoảng cách focus tối ưu.

Gợi ý dùng cho drone:

```cpp
if (squal < 15) {
  // Không tin dữ liệu optical flow
  // Có thể bỏ sample hoặc giảm trọng số dữ liệu
}
```

Khi test tốt trên giấy, vải hoặc bề mặt có texture rõ, `squal` có thể nằm trong khoảng từ vài chục đến hơn `100`, tùy điều kiện bề mặt và ánh sáng.

---

## `shutter`

`shutter` là thời gian phơi sáng nội bộ của cảm biến, tính theo clock cycles.

ADNS-3080 tự điều chỉnh shutter để giữ độ sáng ảnh trong vùng phù hợp. Ở chế độ mặc định, shutter được điều chỉnh theo từng frame.

Cách hiểu đơn giản:

| Giá trị `shutter` | Ý nghĩa |
| --- | --- |
| Thấp | Ảnh đủ sáng, sensor không cần phơi sáng lâu |
| Cao | Ảnh tối hoặc bề mặt khó nhìn, sensor phải phơi sáng lâu hơn |

Với drone, nếu `shutter` tăng quá cao đồng thời `squal` thấp, dữ liệu optical flow thường kém tin cậy.

---

## `maxPixel`

`maxPixel` là giá trị pixel sáng nhất trong ảnh mà sensor đang nhìn thấy.

Biến này giúp đánh giá frame hiện tại đang:

- quá tối,
- đủ sáng,
- hay quá sáng/chói.

Cách hiểu thực tế:

| Giá trị `maxPixel` | Ý nghĩa có thể xảy ra |
| --- | --- |
| Quá thấp | Ảnh tối, LED yếu, quá xa mặt đất hoặc sai focus |
| Quá cao | Ảnh quá sáng, bị chói hoặc có thể bão hòa |
| Vừa phải | Ảnh có khả năng tracking tốt hơn |

Không nên đánh giá dữ liệu chỉ bằng `maxPixel`. Nên xem kết hợp với:

- `squal`,
- `shutter`,
- và trạng thái `overflow`.

---

## `overflow`

`overflow` cho biết sensor đã phát hiện chuyển động quá lớn hoặc dữ liệu delta đã bị tràn trước khi MCU kịp đọc.

Trong code, bit `overflow` thường là bit `0x10` của thanh ghi `Motion`.

Khi `overflow = 1`, không nên dùng `dx` và `dy` của sample đó cho điều khiển drone.

Ví dụ:

```cpp
if (overflow) {
  // Bỏ sample hiện tại
  // Clear motion nếu cần
  return;
}
```

Lý do là khi overflow xảy ra, dữ liệu có khả năng đã bị mất một phần chuyển động thật.

---

## Gợi ý lọc dữ liệu cho drone

Một cách đơn giản để kiểm tra dữ liệu optical flow trước khi sử dụng:

```cpp
bool isFlowValid(int squal, bool overflow) {
  if (overflow) {
    return false;
  }

  if (squal < 15) {
    return false;
  }

  return true;
}
```

Khi đọc sensor:

```cpp
if (!isFlowValid(squal, overflow)) {
  // Không dùng dx/dy cho vòng điều khiển
  // Có thể giữ giá trị cũ hoặc giảm độ tin cậy của optical flow
  return;
}

flowX += dx;
flowY += dy;

velocityX = dx / dt;
velocityY = dy / dt;
```

Nếu muốn dùng cho drone thực tế, nên kết hợp optical flow với các cảm biến khác như:

- IMU,
- cảm biến độ cao,
- barometer,
- sonar,
- lidar,
- hoặc ToF sensor.

---

## Ghi chú thực tế khi test

Khi test ADNS-3080 trên Serial Monitor, nên quan sát cùng lúc các biến:

```text
dx, dy, flowX, flowY, squal, shutter, maxPixel, overflow
```

Một sample tốt thường có đặc điểm:

- `overflow = 0`
- `squal` đủ cao
- `shutter` không tăng quá bất thường
- `maxPixel` không quá thấp hoặc quá cao
- `dx`, `dy` thay đổi hợp lý khi di chuyển sensor

Nếu thấy `squal` thấp liên tục, nên kiểm tra:

- khoảng cách từ sensor đến mặt đất,
- độ focus của lens,
- ánh sáng LED,
- bề mặt test có đủ texture hay không,
- tốc độ di chuyển có quá nhanh hay không.

---

## Tóm tắt nhanh

| Biến | Nên hiểu là |
| --- | --- |
| `dx`, `dy` | Dịch chuyển tức thời mới nhất |
| `flowX`, `flowY` | Tổng dịch chuyển cộng dồn |
| `squal` | Độ tin cậy về texture/bề mặt |
| `shutter` | Sensor đang cần phơi sáng lâu hay ngắn |
| `maxPixel` | Mức sáng cao nhất trong ảnh |
| `overflow` | Dữ liệu đã bị tràn, nên bỏ sample |
