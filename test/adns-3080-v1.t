#include <Arduino.h>
#include <SPI.h>

static const uint8_t ADNS_RST_PIN = 9;
static const uint8_t ADNS_CS_PIN  = 10;

SPISettings adns_spi(2000000, MSBFIRST, SPI_MODE3);

#define ADNS3080_PRODUCT_ID          0x00
#define ADNS3080_REVISION_ID         0x01
#define ADNS3080_MOTION              0x02
#define ADNS3080_DELTA_X             0x03
#define ADNS3080_DELTA_Y             0x04
#define ADNS3080_SQUAL               0x05
#define ADNS3080_MAXIMUM_PIXEL       0x07
#define ADNS3080_CONFIGURATION_BITS  0x0A
#define ADNS3080_SHUTTER_LOWER       0x0E
#define ADNS3080_SHUTTER_UPPER       0x0F
#define ADNS3080_MOTION_CLEAR        0x12
#define ADNS3080_MOTION_BURST        0x50

#define ADNS3080_PRODUCT_ID_VALUE    0x17

// Motion register bits
#define ADNS3080_MOTION_BIT          0x80
#define ADNS3080_OVERFLOW_BIT        0x10

typedef struct
{
  uint8_t motion;
  int8_t dx;
  int8_t dy;
  uint8_t squal;
  uint16_t shutter;
  uint8_t maxPixel;
  bool hasMotion;
  bool overflow;
} ADNSMotion;

ADNSMotion m;

static void adns_reset();
static void adns_clear_motion();

static void adns_write_reg(uint8_t reg, uint8_t value);
static uint8_t adns_read_reg(uint8_t reg);
static void adns_read_burst(uint8_t reg, uint8_t *buf, uint8_t len);

static bool adns_read_motion(ADNSMotion &m);
static bool adns_begin();

static int32_t total_x = 0;
static int32_t total_y = 0;

static constexpr uint32_t read_interval_us = 1000u; // 1000 Hz
static constexpr uint32_t print_interval_us = 20000u; // 50 Hz
static uint32_t last_read_time_us = 0u;
static uint32_t last_print_time_us = 0u;

static int32_t print_dx_sum = 0;
static int32_t print_dy_sum = 0;

static int8_t last_dx = 0;
static int8_t last_dy = 0;
static uint8_t last_squal = 0u;
static uint16_t last_shutter = 0u;
static uint8_t last_max_pixel = 0u;
static uint8_t last_motion = 0u;
static bool last_overflow = false;

void setup() 
{
  Serial.begin(115200);
  delay(2000);

  pinMode(ADNS_CS_PIN, OUTPUT);
  pinMode(ADNS_RST_PIN, OUTPUT);

  digitalWrite(ADNS_CS_PIN, HIGH);
  digitalWrite(ADNS_RST_PIN, LOW);

  SPI.begin();

  if (adns_begin() == false) 
  {
    Serial.println("ADNS-3080 init failed");
    for (;;) {}
  }
  else
  {
    Serial.println("ADNS-3080 init success");
  }
}

void loop() 
{
  uint32_t now = micros();

  // 1000 Hz
  if (now - last_read_time_us >= read_interval_us) 
  {
    last_read_time_us = now;

    adns_read_motion(m);

    last_motion = m.motion;
    last_squal = m.squal;
    last_shutter = m.shutter;
    last_max_pixel = m.maxPixel;
    last_overflow = m.overflow;

    if (m.overflow == true) 
    {
      adns_clear_motion();
    }

    if (m.hasMotion == true && m.overflow == false)
    {
      total_x += m.dx;
      total_y += m.dy;

      print_dx_sum += m.dx;
      print_dy_sum += m.dy;

      last_dx = m.dx;
      last_dy = m.dy;
    }
  }

  // 50 Hz
  if (now - last_print_time_us >= print_interval_us) 
  {
    last_print_time_us = now;

    Serial.print("totalX=");
    Serial.print(total_x);
    Serial.print(" | totalY=");
    Serial.print(total_y);
    Serial.print(" | Dx=");
    Serial.print(last_dx);
    Serial.print(" | Dy=");
    Serial.print(last_dy);
    Serial.print(" | Squal=");
    Serial.print(last_squal);
    Serial.print(" | Shutter=");
    Serial.print(last_shutter);
    Serial.print(" | MaxPixel=");
    Serial.print(last_max_pixel);
    Serial.print(" | Motion=");
    Serial.print(last_motion, HEX);
    Serial.print(" | Overflow=");
    Serial.println(last_overflow ? 1 : 0);

    print_dx_sum = 0;
    print_dy_sum = 0;
  }
}

static bool adns_begin() 
{
  adns_reset();

  uint8_t id = adns_read_reg(ADNS3080_PRODUCT_ID);
  uint8_t rev = adns_read_reg(ADNS3080_REVISION_ID);

  Serial.print("Product ID = 0x");
  Serial.println(id, HEX);

  Serial.print("Revision ID = 0x");
  Serial.println(rev, HEX);

  if (id != ADNS3080_PRODUCT_ID_VALUE) 
  {
    return false;
  }

  // Set 1600 CPI
  uint8_t cfg = adns_read_reg(ADNS3080_CONFIGURATION_BITS);
  adns_write_reg(ADNS3080_CONFIGURATION_BITS, cfg | 0x10);

  delay(1);
  adns_clear_motion();

  return true;
}

static void adns_reset() 
{
  digitalWrite(ADNS_CS_PIN, HIGH);

  digitalWrite(ADNS_RST_PIN, HIGH);
  delayMicroseconds(20);
  digitalWrite(ADNS_RST_PIN, LOW);

  delay(35);

  digitalWrite(ADNS_CS_PIN, HIGH);
  delayMicroseconds(1000);
}

static void adns_clear_motion() 
{
  adns_write_reg(ADNS3080_MOTION_CLEAR, 0xFF);
  total_x = 0;
  total_y = 0;
}

static bool adns_read_motion(ADNSMotion &m) 
{
  uint8_t buffer[7];

  adns_read_burst(ADNS3080_MOTION_BURST, buffer, 7);

  m.motion = buffer[0];
  m.dx = (int8_t)buffer[1];
  m.dy = (int8_t)buffer[2];
  m.squal = buffer[3];
  m.shutter = ((uint16_t)buffer[4] << 8) | buffer[5];
  m.maxPixel = buffer[6];

  m.hasMotion = m.motion & ADNS3080_MOTION_BIT;
  m.overflow = m.motion & ADNS3080_OVERFLOW_BIT;

  return m.hasMotion;
}

static void adns_write_reg(uint8_t reg, uint8_t value) 
{
  SPI.beginTransaction(adns_spi);

  digitalWrite(ADNS_CS_PIN, LOW);

  SPI.transfer(reg | 0x80);

  delayMicroseconds(75);

  SPI.transfer(value);

  digitalWrite(ADNS_CS_PIN, HIGH);

  SPI.endTransaction();

  delayMicroseconds(50);
}

static uint8_t adns_read_reg(uint8_t reg) 
{
  uint8_t value = 0;

  SPI.beginTransaction(adns_spi);

  digitalWrite(ADNS_CS_PIN, LOW);

  SPI.transfer(reg & 0x7F);

  delayMicroseconds(75);

  value = SPI.transfer(0x00);

  digitalWrite(ADNS_CS_PIN, HIGH);

  SPI.endTransaction();

  delayMicroseconds(1);

  return value;
}

static void adns_read_burst(uint8_t reg, uint8_t *buf, uint8_t len) 
{
  SPI.beginTransaction(adns_spi);

  digitalWrite(ADNS_CS_PIN, LOW);

  SPI.transfer(reg & 0x7F);

  delayMicroseconds(75);

  for (uint8_t i = 0; i < len; i++) 
  {
    buf[i] = SPI.transfer(0x00);
  }

  digitalWrite(ADNS_CS_PIN, HIGH);

  SPI.endTransaction();

  delayMicroseconds(5);
}