#include <OneWire.h>
#include <DallasTemperature.h>
#include <ESP8266WiFi.h>
#include <WiFiClient.h>
#include <LoRa.h>
#include <SPI.h>

// ----------------------------------------------------------------------------------------------
// LoRa Configuration
#define BAND 920E6
#define SS 15
#define RST 5
#define DIO0 4
const String expectedPassword = "Hive";
int counter = 0;

// ----------------------------------------------------------------------------------------------
// WiFi Credentials
const char WIFI_SSID[] = "4G Home WiFi (K10)_492042";
const char WIFI_PASSWORD[] = "67492042";

// ----------------------------------------------------------------------------------------------
// ThingsBoard Credentials
constexpr char THINGSBOARD_SERVER[] = "demo.thingsboard.io";
constexpr char THINGSBOARD_TOKEN[] = "L4yymXEx5QjDJJlSAbQ2";

// ----------------------------------------------------------------------------------------------
// Google Sheets Script ID
String GAS_ID = "AKfycbyW5loJJVNUYpx_TVH9Wnq0rB8U07xysukqEO3pP4mkVnzUgQL55V71wJsL1PKMaRWYCQ";
const char* GOOGLE_HOST = "script.google.com";

// ----------------------------------------------------------------------------------------------
// Interval Configuration
#define UPDATE_INTERVAL_GOOGLE_MS (900000) // 900 วินาทีสำหรับ Google Sheets
#define UPDATE_INTERVAL_THINGSBOARD_MS (10000) // 10 วินาทีสำหรับ ThingsBoard

// ----------------------------------------------------------------------------------------------
// Variables
WiFiClient espClient;
float Temperature = 0.0; // ตัวแปร Temperature ใช้ส่งข้อมูล
bool wifiConnected = false;
unsigned long lastGoogleUpdate = 0;
unsigned long lastThingsBoardUpdate = 0;

// ตัวแปรสำหรับข้อมูลจาก LoRa
String Temperature_sensor1_status;
String Temperature_sensor2_status;
String Peltier_status;
String Fan_status;
String warning = "";

// ----------------------------------------------------------------------------------------------
// WiFi Connection Function
void InitWiFi() {
  Serial.println("Connecting to WiFi...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  wifiConnected = true;
  Serial.println("\nWiFi connected!");
}

// ----------------------------------------------------------------------------------------------
// Function to send data to Google Sheets
void update_google_sheet() {
  Serial.print("Connecting to ");
  Serial.println(GOOGLE_HOST);

  WiFiClientSecure client;
  client.setInsecure();
  const int httpPort = 443;

  if (!client.connect(GOOGLE_HOST, httpPort)) {
    Serial.println("Connection to Google Sheets failed.");
    return;
  }

  String url = "/macros/s/" + GAS_ID + "/exec?temperature=" + String(Temperature);
  Serial.print("Requesting URL: ");
  Serial.println(url);

  client.print(String("GET ") + url + " HTTP/1.1\r\n" +
               "Host: " + GOOGLE_HOST + "\r\n" + 
               "Connection: close\r\n\r\n");
  Serial.println("Google Sheets update sent successfully.");
}

// ----------------------------------------------------------------------------------------------
// Function to send data to ThingsBoard
void sendToThingsBoard() {
  if (!wifiConnected) {
    Serial.println("WiFi not connected. Reconnecting...");
    InitWiFi();
  }

  String payload = "{\"temperature\":" + String(Temperature, 2) + "}";
  String url = String("/api/v1/") + THINGSBOARD_TOKEN + "/telemetry";

  Serial.println("Connecting to ThingsBoard...");

  if (espClient.connect(THINGSBOARD_SERVER, 80)) {
    espClient.println("POST " + url + " HTTP/1.1");
    espClient.println("Host: " + String(THINGSBOARD_SERVER));
    espClient.println("Content-Type: application/json");
    espClient.print("Content-Length: ");
    espClient.println(payload.length());
    espClient.println();
    espClient.println(payload);

    while (espClient.connected() && !espClient.available()) {
      delay(10);
    }

    while (espClient.available()) {
      String response = espClient.readString();
      Serial.println("Response: " + response);
    }

    espClient.stop();
    Serial.println("ThingsBoard update sent successfully.");
  } else {
    Serial.println("Failed to connect to ThingsBoard.");
  }
}

// ----------------------------------------------------------------------------------------------
// LoRa Initialization
void startLoRa() {
  LoRa.setPins(SS, RST, DIO0);
  while (!LoRa.begin(BAND) && counter < 10) {
    Serial.print(".");
    counter++;
    delay(500);
  }
  if (counter == 10) {
    Serial.println("LoRa Initialization Failed!");
    return;
  }
  Serial.println("LoRa Initialization successful.");

  LoRa.setTxPower(14);
  LoRa.setSpreadingFactor(7);
  LoRa.setSignalBandwidth(500E3);
  LoRa.setCodingRate4(5);
  LoRa.setPreambleLength(8);
  delay(2000);
}

// ----------------------------------------------------------------------------------------------
// LoRa Message Unpacking Function
void unpackLoRaMessage(String LoRaMessage) {
  String Headcode;
  int readingID;
  int warningIndex = LoRaMessage.indexOf("WARNING:");

  int index1 = LoRaMessage.indexOf("/");
  int index2 = LoRaMessage.indexOf("$");
  int index3 = LoRaMessage.indexOf("#");
  int index4 = LoRaMessage.indexOf("&");
  int index5 = LoRaMessage.indexOf("%");
  int index6 = LoRaMessage.indexOf("=");

  if (index1 == -1 || index2 == -1 || index3 == -1 || index4 == -1 || index5 == -1 || index6 == -1) {
    Serial.println("Invalid LoRa message format.");
    return;
  }

  Headcode = LoRaMessage.substring(0, index1);
  if (Headcode != expectedPassword) {
    Serial.println("Invalid password in LoRa message.");
    return;
  }

  readingID = LoRaMessage.substring(index1 + 1, index2).toInt();
  Temperature = LoRaMessage.substring(index2 + 1, index3).toFloat();
  Temperature_sensor1_status = LoRaMessage.substring(index3 + 1, index4);
  Temperature_sensor2_status = LoRaMessage.substring(index4 + 1, index5);
  Peltier_status = LoRaMessage.substring(index5 + 1, index6);
  Fan_status = LoRaMessage.substring(index6 + 1, warningIndex == -1 ? LoRaMessage.length() : warningIndex - 1);

  if (warningIndex != -1) {
    warning = LoRaMessage.substring(warningIndex + 8);
  }

  // Display extracted values
  Serial.println("Received LoRa Message:");
  Serial.println("Reading ID: " + String(readingID));
  Serial.println("Temperature: " + String(Temperature));
  Serial.println("Sensor 1 Status: " + Temperature_sensor1_status);
  Serial.println("Sensor 2 Status: " + Temperature_sensor2_status);
  Serial.println("Peltier Status: " + Peltier_status);
  Serial.println("Fan Status: " + Fan_status);
  if (warning != "") {
    Serial.println("Warning: " + warning);
  }
}

// ----------------------------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);

  startLoRa();
  InitWiFi();
}

// ----------------------------------------------------------------------------------------------
void loop() {
  unsigned long currentMillis = millis();

  // รับข้อความจาก LoRa ก่อน
  if (LoRa.available()) {
    String receivedMessage = "";

    // รับข้อความ LoRa ทั้งหมด
    while (LoRa.available()) {
      receivedMessage += (char)LoRa.read();
      Serial.println(receivedMessage);
    }

    // แยกข้อมูลที่ได้รับจาก LoRa
    unpackLoRaMessage(receivedMessage);

    // หลังจากได้รับข้อความจาก LoRaแล้ว อัปเดต Google Sheets
    update_google_sheet();
    Serial.println("Google Sheets updated with Temperature: " + String(Temperature));

    // และอัปเดต ThingsBoard
    sendToThingsBoard();
    Serial.println("ThingsBoard updated with Temperature: " + String(Temperature));
  } else {
    // ถ้าไม่มีข้อความจาก LoRa ให้ตรวจสอบทุก 100ms
    delay(100);
  }
}
