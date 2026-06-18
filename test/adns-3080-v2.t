#include <Arduino.h>
#include <SPI.h>

static constexpr int PIN_ADNS_CS   = 10;
static constexpr int PIN_ADNS_RST  = 9;
static constexpr int PIN_SPI_MOSI  = 11;
static constexpr int PIN_SPI_MISO  = 13;
static constexpr int PIN_SPI_SCK   = 12;
static constexpr int PIN_ADNS_NPD  = -1;

static constexpr uint32_t SENSOR_READ_HZ = 1000;
static constexpr uint32_t SENSOR_PERIOD_US = 1000000UL / SENSOR_READ_HZ;

static constexpr uint32_t DEBUG_PRINT_HZ = 50;
static constexpr uint32_t DEBUG_PERIOD_US = 1000000UL / DEBUG_PRINT_HZ;

static uint32_t last_next_read_time_us = 0u;
static uint32_t last_next_print_time_us = 0u;

static constexpr uint32_t ADNS_SPI_HZ = 2000000;

namespace ADNS3080 
{
  static constexpr uint8_t PRODUCT_ID              = 0x00;
  static constexpr uint8_t REVISION_ID             = 0x01;
  static constexpr uint8_t MOTION                  = 0x02;
  static constexpr uint8_t DELTA_X                 = 0x03;
  static constexpr uint8_t DELTA_Y                 = 0x04;
  static constexpr uint8_t SQUAL                   = 0x05;
  static constexpr uint8_t PIXEL_SUM               = 0x06;
  static constexpr uint8_t MAXIMUM_PIXEL           = 0x07;
  static constexpr uint8_t CONFIGURATION_BITS      = 0x0A;
  static constexpr uint8_t EXTENDED_CONFIG         = 0x0B;
  static constexpr uint8_t DATA_OUT_LOWER          = 0x0C;
  static constexpr uint8_t DATA_OUT_UPPER          = 0x0D;
  static constexpr uint8_t SHUTTER_LOWER           = 0x0E;
  static constexpr uint8_t SHUTTER_UPPER           = 0x0F;
  static constexpr uint8_t MOTION_CLEAR            = 0x12;
  static constexpr uint8_t FRAME_CAPTURE           = 0x13;
  static constexpr uint8_t SROM_ENABLE             = 0x14;
  static constexpr uint8_t FRAME_PERIOD_MAX_LOWER  = 0x19;
  static constexpr uint8_t FRAME_PERIOD_MAX_UPPER  = 0x1A;
  static constexpr uint8_t FRAME_PERIOD_MIN_LOWER  = 0x1B;
  static constexpr uint8_t FRAME_PERIOD_MIN_UPPER  = 0x1C;
  static constexpr uint8_t SHUTTER_MAX_LOWER       = 0x1D;
  static constexpr uint8_t SHUTTER_MAX_UPPER       = 0x1E;
  static constexpr uint8_t SROM_ID                 = 0x1F;
  static constexpr uint8_t OBSERVATION             = 0x3D;
  static constexpr uint8_t INVERSE_PRODUCT_ID      = 0x3F;
  static constexpr uint8_t PIXEL_BURST             = 0x40;
  static constexpr uint8_t MOTION_BURST            = 0x50;
  static constexpr uint8_t SROM_LOAD               = 0x60;

  static constexpr uint8_t PRODUCT_ID_VALUE        = 0x17;
  static constexpr uint8_t INVERSE_PRODUCT_VALUE   = 0xE8;

  // Motion register bits
  static constexpr uint8_t MOTION_BIT              = 0x80;
  static constexpr uint8_t OVERFLOW_BIT            = 0x10;

  // Configuration_Bits
  static constexpr uint8_t CONFIG_1600_CPI         = 0x10;
}

// Datasheet timing
static constexpr uint32_t T_SRAD_US       = 50;  // normal read address-data delay
static constexpr uint32_t T_SRAD_MOT_US   = 75;  // Motion/Motion_Burst delay
static constexpr uint32_t T_SWW_US        = 50;  // write to write delay
static constexpr uint32_t T_SWR_US        = 50;  // write to read delay
static constexpr uint32_t T_BEXIT_US      = 5;   // burst exit, datasheet min 4 us

SPISettings adns_spi(ADNS_SPI_HZ, MSBFIRST, SPI_MODE3);

struct FlowSample 
{
  int8_t dx = 0;
  int8_t dy = 0;
  uint8_t motion = 0;
  uint8_t squal = 0;
  uint16_t shutter = 0;
  uint8_t max_pixel = 0;
  bool has_motion = false;
  bool overflow = false;
  uint32_t t_us = 0;
};

FlowSample s;

static int32_t flow_x = 0;
static int32_t flow_y = 0;

static int32_t print_dx_sum = 0;
static int32_t print_dy_sum = 0;
static int8_t last_dx = 0;
static int8_t last_dy = 0;
static uint8_t last_squal = 0;
static uint16_t last_shutter = 0;
static uint8_t last_max_pixel = 0;
static bool had_over_flow = false;

void adns_recover_serial_port() 
{
  digitalWrite(PIN_ADNS_CS, HIGH);
  delayMicroseconds(1000);
}

void adns_write(uint8_t reg, uint8_t value) 
{
  SPI.beginTransaction(adns_spi);

  digitalWrite(PIN_ADNS_CS, LOW);
  SPI.transfer(reg | 0x80);
  SPI.transfer(value);
  digitalWrite(PIN_ADNS_CS, HIGH);

  SPI.endTransaction();

  delayMicroseconds(T_SWW_US);
}

uint8_t adns_read(uint8_t reg, bool motionDelay = false) 
{
  uint8_t value;

  SPI.beginTransaction(adns_spi);

  digitalWrite(PIN_ADNS_CS, LOW);
  SPI.transfer(reg & 0x7F);
  delayMicroseconds(motionDelay ? T_SRAD_MOT_US : T_SRAD_US);
  value = SPI.transfer(0x00);
  digitalWrite(PIN_ADNS_CS, HIGH);

  SPI.endTransaction();

  return value;
}

bool adns_read_motion_burst(FlowSample &s) 
{
  uint8_t buffer[7];

  SPI.beginTransaction(adns_spi);

  digitalWrite(PIN_ADNS_CS, LOW);

  SPI.transfer(ADNS3080::MOTION_BURST);
  delayMicroseconds(T_SRAD_MOT_US);

  // Motion_Burst order:
  // Motion, Delta_X, Delta_Y, SQUAL, Shutter_Upper, Shutter_Lower, Maximum_Pixel
  for (uint8_t i = 0; i < sizeof(buffer); i++) 
  {
    buffer[i] = SPI.transfer(0x00);
  }

  digitalWrite(PIN_ADNS_CS, HIGH);

  SPI.endTransaction();

  delayMicroseconds(T_BEXIT_US);

  s.motion = buffer[0];
  s.dx = (int8_t)buffer[1];
  s.dy = (int8_t)buffer[2];
  s.squal = buffer[3];
  s.shutter = ((uint16_t)buffer[4] << 8) | buffer[5];
  s.max_pixel = buffer[6];
  s.has_motion = s.motion & ADNS3080::MOTION_BIT;
  s.overflow = s.motion & ADNS3080::OVERFLOW_BIT;
  s.t_us = micros();

  return s.has_motion;
}

void adns_hardware_reset() 
{
  digitalWrite(PIN_ADNS_CS, HIGH);

  digitalWrite(PIN_ADNS_RST, HIGH);
  delayMicroseconds(20);
  digitalWrite(PIN_ADNS_RST, LOW);

  delay(35);

  adns_recover_serial_port();
}

void adns_clear_motion() 
{
  adns_write(ADNS3080::MOTION_CLEAR, 0xFF);
  flow_x = 0;
  flow_y = 0;
}

bool adns_check_link() 
{
  const uint8_t pid = adns_read(ADNS3080::PRODUCT_ID);
  const uint8_t ipid = adns_read(ADNS3080::INVERSE_PRODUCT_ID);

  Serial.print("Product ID: 0x");
  Serial.print(pid, HEX);
  Serial.print("  Inverse ID: 0x");
  Serial.println(ipid, HEX);

  return (pid == ADNS3080::PRODUCT_ID_VALUE) && (ipid == ADNS3080::INVERSE_PRODUCT_VALUE);
}

void adns_set_1600CPI() 
{
  uint8_t config = adns_read(ADNS3080::CONFIGURATION_BITS);
  config |= ADNS3080::CONFIG_1600_CPI;
  adns_write(ADNS3080::CONFIGURATION_BITS, config);

  uint8_t motion = adns_read(ADNS3080::MOTION, true);
  Serial.print("Motion reg after 1600 CPI set: 0x");
  Serial.println(motion, HEX);
}

void adns_enable_fixed_6469FPS_experimental() 
{
  uint8_t ext = adns_read(ADNS3080::EXTENDED_CONFIG);
  ext |= 0x01;
  adns_write(ADNS3080::EXTENDED_CONFIG, ext);

  adns_write(ADNS3080::FRAME_PERIOD_MAX_LOWER, 0x7E);
  adns_write(ADNS3080::FRAME_PERIOD_MAX_UPPER, 0x0E);

  delay(1);
}

bool adns_begin() 
{
  pinMode(PIN_ADNS_CS, OUTPUT);
  pinMode(PIN_ADNS_RST, OUTPUT);

  digitalWrite(PIN_ADNS_CS, HIGH);
  digitalWrite(PIN_ADNS_RST, LOW);

  if (PIN_ADNS_NPD >= 0) 
  {
    pinMode(PIN_ADNS_NPD, OUTPUT);
    digitalWrite(PIN_ADNS_NPD, HIGH); // NPD high = chạy bình thường
  }

  SPI.begin(PIN_SPI_SCK, PIN_SPI_MISO, PIN_SPI_MOSI, PIN_ADNS_CS);

  delay(10);
  adns_hardware_reset();

  if (!adns_check_link()) 
  {
    return false;
  }

  adns_set_1600CPI();
  adns_clear_motion();

  const uint8_t rev = adns_read(ADNS3080::REVISION_ID);
  const uint8_t srom = adns_read(ADNS3080::SROM_ID);

  Serial.print("Revision ID: 0x");
  Serial.println(rev, HEX);

  Serial.print("SROM ID: 0x");
  Serial.println(srom, HEX);

  return true;
}

void setup() 
{
    Serial.begin(115200);
    delay(2000);

    if (adns_begin() == false) 
    {
      Serial.println("ADNS-3080 init failed");
      for (;;) {}
    }
    else
    {
      Serial.println("ADNS-3080 init successful");
    }
}

void loop() 
{
  const uint32_t now = micros();

  if ((now - last_next_read_time_us) > SENSOR_PERIOD_US) 
  {
    last_next_read_time_us = now;

    adns_read_motion_burst(s);

    if (s.overflow == true) 
    {
      had_over_flow = true;
      adns_clear_motion();
    }

    if (s.has_motion) {
      flow_x += s.dx;
      flow_y += s.dy;

      print_dx_sum += s.dx;
      print_dy_sum += s.dy;

      last_dx = s.dx;
      last_dy = s.dy;
      last_squal = s.squal;
      last_shutter = s.shutter;
      last_max_pixel = s.max_pixel;
    } 
    else 
    {
      last_squal = s.squal;
      last_shutter = s.shutter;
      last_max_pixel = s.max_pixel;
    }
  }

  if ((now - last_next_print_time_us) > DEBUG_PERIOD_US) {
    last_next_print_time_us = now;

    Serial.print("Flow X: ");
    Serial.print(flow_x);
    Serial.print("| Flow Y: ");
    Serial.print(flow_y);
    Serial.print(" | Last dx: ");
    Serial.print(last_dx);
    Serial.print(" | Last dy: ");
    Serial.print(last_dy);
    Serial.print(" | Last SQUAL: ");
    Serial.print(last_squal);
    Serial.print(" | Last Shutter: ");
    Serial.print(last_shutter);
    Serial.print(" | Last Max Pixel: ");
    Serial.print(last_max_pixel);
    Serial.print(" | Had Overflow: ");
    Serial.println(had_over_flow ? 1 : 0);

    print_dx_sum = 0;
    print_dy_sum = 0;
    had_over_flow = false;
  }
}