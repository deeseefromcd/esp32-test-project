/*
  Blink для ESP32-S3-DevKitC-1 — тестовый проект для Wokwi (PlatformIO).

  Мигает светодиодом, подключённым к GPIO48.
  На реальной плате ESP32-S3-DevKitC-1 на GPIO48 висит встроенный RGB-светодиод,
  поэтому в Wokwi этот же пин используется для внешнего светодиода из diagram.json.

  Схема:
    ESP32-S3 GPIO48 ---> LED (анод) ---> LED (катод) ---> резистор 220 Ом ---> GND
*/

#include <Arduino.h>

#define LED_PIN 48            // GPIO48 — на плате это встроенный светодиод
#define BLINK_DELAY_MS 1000   // период мигания: 1 секунда

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