#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h> 
#include <addons/TokenHelper.h>  
#include <SPI.h>
#include <MFRC522.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h> 

// --- DATOS DE RED (Hotspot) ---
#define WIFI_SSID "iPhone de Rafa"
#define WIFI_PASSWORD "angel210411"

// --- CREDENCIALES DE FIREBASE ---
#define API_KEY "AIzaSyCLusy0Ww6PtSeh3HUazxhUTgSVMpxOH2M"
#define PROJECT_ID "sami-d5050" 

// --- PINES HARDWARE ---
#define SS_PIN     5
#define RST_PIN    4
#define DATA_PIN   13
#define CLOCK_PIN  14
#define LATCH_PIN  27
#define TRIG_PIN   26
#define ECHO_PIN   25
#define BUZZER_PIN 2

#define MOTOR_SPEED 800 

// --- MAPEO BINARIO DE MOTORES ---
const byte M1_STEP = 0b00000001; 
const byte M1_DIR  = 0b00000010; 
const byte M3_STEP = 0b00010000; 
const byte M3_DIR  = 0b00100000; 

// --- OBJETOS ---
MFRC522 rfid(SS_PIN, RST_PIN);
LiquidCrystal_I2C lcd(0x27, 16, 2);
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastCheckTime = 0;

// --- FUNCIONES HARDWARE ---
void updateShiftRegister(byte data) {
  digitalWrite(LATCH_PIN, LOW);
  shiftOut(DATA_PIN, CLOCK_PIN, MSBFIRST, data);
  digitalWrite(LATCH_PIN, HIGH);
}

float obtenerDistancia() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duracion = pulseIn(ECHO_PIN, HIGH, 20000); 
  if (duracion == 0) return 999.0;
  return (duracion * 0.0343) / 2.0;
}

void sonarBuzzer(bool exito) {
  if (exito) {
    digitalWrite(BUZZER_PIN, HIGH); delay(100);
    digitalWrite(BUZZER_PIN, LOW);  delay(50);
    digitalWrite(BUZZER_PIN, HIGH); delay(100);
    digitalWrite(BUZZER_PIN, LOW);
  } else {
    digitalWrite(BUZZER_PIN, HIGH); delay(600);
    digitalWrite(BUZZER_PIN, LOW);
  }
}

time_t parseISO8601(String timestampStr) {
  int y, m, d, h, min, s;
  if (sscanf(timestampStr.c_str(), "%d-%d-%dT%d:%d:%d", &y, &m, &d, &h, &min, &s) == 6) {
    struct tm t_tm;
    t_tm.tm_year = y - 1900;
    t_tm.tm_mon = m - 1;
    t_tm.tm_mday = d;
    t_tm.tm_hour = h;
    t_tm.tm_min = min;
    t_tm.tm_sec = s;
    t_tm.tm_isdst = 0;
    return mktime(&t_tm); 
  }
  return 0;
}

bool ejecutarMotorConMonitoreo(String materialId, unsigned long duracionMs) {
  unsigned long tiempoInicio = millis();
  unsigned long ultimoCheck = 0;
  
  byte stepBit = 0;
  byte dirBit = 0;

  if (materialId == "c1") {
    stepBit = M1_STEP; dirBit = M1_DIR; 
  } else if (materialId == "g1") {
    stepBit = M3_STEP; dirBit = M3_DIR; 
  } else {
    stepBit = M1_STEP; dirBit = M1_DIR;
  }
  
  while (millis() - tiempoInicio < duracionMs) {
    if (millis() - ultimoCheck > 60) {
      ultimoCheck = millis();
      float distancia = obtenerDistancia();
      // Frena a menos de 15 cm
      if (distancia < 15.0 && distancia > 0.5) {
        updateShiftRegister(0); 
        return true; 
      }
    }
    updateShiftRegister(stepBit | dirBit);
    delayMicroseconds(MOTOR_SPEED);
    updateShiftRegister(dirBit);
    delayMicroseconds(MOTOR_SPEED);
  }
  updateShiftRegister(0); 
  return false; 
}

// --- SETUP ---
void setup() {
  Serial.begin(115200);
  SPI.begin();       
  rfid.PCD_Init();   

  pinMode(DATA_PIN, OUTPUT);
  pinMode(CLOCK_PIN, OUTPUT);
  pinMode(LATCH_PIN, OUTPUT);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  updateShiftRegister(0); 

  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();
  
  lcd.clear();
  lcd.print("Conectando Wi-Fi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }
  Serial.println("\nWiFi Conectado!");

  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Sincronizando hora");
  while (time(nullptr) < 1000000000l) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("\nHora sincronizada.");
  
  config.api_key = API_KEY;
  config.signer.test_mode = true; 
  config.token_status_callback = tokenStatusCallback;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  lcd.clear();
  lcd.print("S.A.M.I. ONLINE");
  delay(2000);
}

// --- LOOP ---
void loop() {

  if (rfid.PICC_IsNewCardPresent() && rfid.PICC_ReadCardSerial()) {
    String uidLeido = "";
    for (byte i = 0; i < rfid.uid.size; i++) {
      uidLeido += String(rfid.uid.uidByte[i] < 0x10 ? "0" : "");
      uidLeido += String(rfid.uid.uidByte[i], HEX);
    }
    uidLeido.toUpperCase();
    rfid.PICC_HaltA(); // Detiene la lectura actual

    Serial.print("Gafete para vinculación detectado: ");
    Serial.println(uidLeido);

    // Sube el UID a la "bandeja" de Firebase
    FirebaseJson updateRfid;
    updateRfid.set("fields/ultimo_rfid_leido/stringValue", uidLeido);
    
    if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "(default)", "sistema/estado", updateRfid.raw(), "ultimo_rfid_leido")) {
      lcd.clear();
      lcd.print("Gafete Copiado!");
      sonarBuzzer(true); // Suena para avisar que se leyó con éxito
      delay(2000);
      
      // Regresa la pantalla a la normalidad
      lcd.clear();
      lcd.print("S.A.M.I. STANDBY");
      lcd.setCursor(0, 1);
      lcd.print("Esperando Pedido");
    }
  }
  
  if (Firebase.ready() && (millis() - lastCheckTime > 4000 || lastCheckTime == 0)) {
    lastCheckTime = millis();
    
    lcd.setCursor(0, 0);
    lcd.print("S.A.M.I. STANDBY");
    lcd.setCursor(0, 1);
    lcd.print("Esperando Pedido");

    FirebaseJson query;
    // PASO 1: ESP32 busca pedidos marcados como 'Pendiente'
    query.set("from/[0]/collectionId", "orders");
    query.set("where/fieldFilter/field/fieldPath", "status");
    query.set("where/fieldFilter/op", "EQUAL");
    query.set("where/fieldFilter/value/stringValue", "Pendiente");
    query.set("limit", 1);

    if (Firebase.Firestore.runQuery(&fbdo, PROJECT_ID, "(default)", "", &query)) {
      String payload = fbdo.payload();
      
      if (payload.indexOf("\"document\"") > 0) {
        FirebaseJsonArray jsonArray;
        jsonArray.setJsonArrayData(payload);
        FirebaseJsonData jsonData;

        jsonArray.get(jsonData, "[0]/document/name");
        String fullPath = jsonData.stringValue;
        String docPath = fullPath.substring(fullPath.indexOf("orders/"));
        
        jsonArray.get(jsonData, "[0]/document/fields/userName/stringValue");
        String userName = jsonData.stringValue;

        jsonArray.get(jsonData, "[0]/document/fields/material/stringValue");
        String materialName = jsonData.stringValue;

        jsonArray.get(jsonData, "[0]/document/fields/materialId/stringValue");
        String materialId = jsonData.stringValue; 

        // Extrayendo el RFID esperado registrado por la App en Firestore
        jsonArray.get(jsonData, "[0]/document/fields/rfid_id/stringValue");
        String expectedRfid = jsonData.stringValue; 

        jsonArray.get(jsonData, "[0]/document/fields/timestamp/timestampValue");
        String timestampStr = jsonData.stringValue;

        time_t horaActual = time(nullptr);
        time_t horaOrden = parseISO8601(timestampStr);
        double diferenciaSegundos = difftime(horaActual, horaOrden);

        if (diferenciaSegundos > 30.0 || diferenciaSegundos < 0) {
          FirebaseJson cancelDoc;
          cancelDoc.set("fields/status/stringValue", "Cancelado");
          Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "(default)", docPath.c_str(), cancelDoc.raw(), "status");
          return; 
        }

        // PASO 2: CONFIRMAR (Muestra la pregunta en el LCD y espera respuesta de la app)
        lcd.clear();
        String linea1 = userName + " pide";
        if(linea1.length() > 16) linea1 = linea1.substring(0, 16);
        lcd.print(linea1);
        
        lcd.setCursor(0, 1);
        String linea2 = materialName + "?";
        if(linea2.length() > 16) linea2 = linea2.substring(0, 16);
        lcd.print(linea2);

        unsigned long inicioEspera = millis();
        bool confirmadoPorApp = false;
        bool canceladoPorApp = false;

        while (millis() - inicioEspera < 25000) { 
          if (Firebase.Firestore.getDocument(&fbdo, PROJECT_ID, "(default)", docPath.c_str(), "status")) {
            FirebaseJson response;
            response.setJsonData(fbdo.payload());
            FirebaseJsonData statusData;
            response.get(statusData, "fields/status/stringValue");
            String statusActual = statusData.stringValue;

            // Si en Flutter presionaron el botón "Sí, Confirmar"
            if (statusActual == "Confirmado") {
              confirmadoPorApp = true;
              break;
            } else if (statusActual == "Cancelado") {
              canceladoPorApp = true;
              break;
            }
          }
          delay(1500); 
        }

        FirebaseJson finalUpdate;

        if (confirmadoPorApp) {
          
          // PASO 3: VERIFICACIÓN RFID
          // Notifica a Flutter cambiando el estado, y la App le dice al usuario "Acerque su Gafete"
          finalUpdate.set("fields/status/stringValue", "Validando RFID");
          Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "(default)", docPath.c_str(), finalUpdate.raw(), "status");

          lcd.clear();
          lcd.print("Pase Gafete...");
          lcd.setCursor(0, 1);
          lcd.print("Verificando...");

          unsigned long inicioRfid = millis();
          bool tarjetaValidada = false;

          while (millis() - inicioRfid < 30000) {
            if (rfid.PICC_IsNewCardPresent() && rfid.PICC_ReadCardSerial()) {
              String uidLeido = "";
              for (byte i = 0; i < rfid.uid.size; i++) {
                uidLeido += String(rfid.uid.uidByte[i] < 0x10 ? "0" : "");
                uidLeido += String(rfid.uid.uidByte[i], HEX);
              }
              uidLeido.toUpperCase();
              rfid.PICC_HaltA(); 

              if (uidLeido == expectedRfid) {
                tarjetaValidada = true;
                break; // Gafete correcto
              } else {
                lcd.clear();
                lcd.print("Gafete Incorrecto");
                sonarBuzzer(false);
                delay(2000);
                lcd.clear();
                lcd.print("Pase Gafete...");
                lcd.setCursor(0, 1);
                lcd.print("Verificando...");
              }
            }
            delay(100);
          }

          if (tarjetaValidada) {
            // PASO 4: DESPACHAR
            // Cambiamos estado para que en la App aparezca la pantalla de Despacho
            finalUpdate.set("fields/status/stringValue", "Despachando");
            Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "(default)", docPath.c_str(), finalUpdate.raw(), "status");

            sonarBuzzer(true);
            lcd.clear();
            lcd.print("Despachando...");
            lcd.setCursor(0, 1);
            lcd.print(materialName);

            bool exitoFisico = ejecutarMotorConMonitoreo(materialId, 12000);

            if (exitoFisico) {
              lcd.clear();
              lcd.print("Entrega Exitosa!");
              sonarBuzzer(true);
              finalUpdate.set("fields/status/stringValue", "Completado");
            } else {
              lcd.clear();
              lcd.print("Error: Objeto NO");
              lcd.setCursor(0,1);
              lcd.print("detectado (15cm)");
              sonarBuzzer(false);
              finalUpdate.set("fields/status/stringValue", "Rechazado");
            }
          } else {
            // Se acabo el tiempo del RFID
            lcd.clear();
            lcd.print("Acceso Denegado");
            sonarBuzzer(false);
            finalUpdate.set("fields/status/stringValue", "Cancelado");
          }
        } 
        else {
          // Canceló en la pantalla del teléfono o el tiempo venció
          lcd.clear();
          lcd.print(canceladoPorApp ? "Pedido Cancelado" : "Tiempo Agotado");
          sonarBuzzer(false);
          finalUpdate.set("fields/status/stringValue", "Cancelado");
        }

        // CIERRE FINAL EN LA BASE DE DATOS
        Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "(default)", docPath.c_str(), finalUpdate.raw(), "status");

        delay(3000);
        lcd.clear();
        lastCheckTime = millis(); 
      }
    }
  }
}
