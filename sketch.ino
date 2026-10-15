/*
  Blink для ESP32-S3-DevKitC-1 — тестовый проект для Wokwi.

  Этот файл — копия src/main.cpp в формате .ino для вставки в редактор на wokwi.com
  (там файл прошивки называется sketch.ino). Локальная сборка PlatformIO берёт код
  из src/main.cpp, поэтому этот файл на сборку не влияет.

  Мигает светодиодом на GPIO48 (на реальной плате ESP32-S3-DevKitC-1 это встроенный RGB).

  Схема:
    ESP32-S3 GPIO48 ---> LED (анод) ---> LED (катод) ---> резистор 220 Ом ---> GND
*/

#define LED_PIN 48
#define BLINK_DELAY_MS 1000

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  Serial.println("ESP32-S3 blink started (GPIO48)");
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  Serial.println("LED ON");
  delay(BLINK_DELAY_MS);

  digitalWrite(LED_PIN, LOW);
  Serial.println("LED OFF");
  delay(BLINK_DELAY_MS);
}