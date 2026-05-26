// ======================================================
// ARDUINO NANO ROBOT CAR HARDWARE SERIAL CONTROLLER
// Connected over TX1 and RX0 (D0 and D1)
// Remember to unplug RX0 and TX1 during code uploads!
// ======================================================

// ======================================================
// TB6612FNG MOTOR DRIVER PINS
// ======================================================
#define PWMA 5
#define PWMB 6

#define AIN1 7
#define AIN2 8

#define BIN1 9
#define BIN2 10

// ======================================================
// RGB LED PINS
// D2 = Blue
// D3 = Green
// D4 = Red
// ======================================================
#define BLUE_PIN 2
#define GREEN_PIN 3
#define RED_PIN 4

// ======================================================
// 8 LINE SENSOR PINS
// D1-D8 -> A0-A7
// ======================================================
const int sensorPins[8] = {
  A0, A1, A2, A3, A4, A5, A6, A7
};

// White = around 850 below
// Black = around 960+
int threshold = 930;

// Array order: D1 D2 D3 D4 D5 D6 D7 D8
// Physical left-to-right from back of robot: D8 D7 D6 D5 D4 D3 D2 D1
int weights[8] = {
  7, 5, 3, 1, -1, -3, -5, -7
};

// ======================================================
// ROBOT SETTINGS
// ======================================================
int speedValue = 155;
int slowSpeed = 95;
int maxSpeed = 255;
int minDrivePwm = 90;
int leftTrim = 0;
int rightTrim = 0;
int manualCurvePercent = 68;

String robotMode = "MANUAL";
String ledMode = "BLUE";

String commandBuffer = "";
unsigned long lastCharTime = 0;
const unsigned long commandTimeout = 120;

unsigned long lastMovementCommandTime = 0;
const unsigned long movementFailsafeMs = 800;
bool manualMovementActive = false;

unsigned long lastLedUpdate = 0;
int ledStep = 0;

float Kp = 12.0;

// ======================================================
// ROUTE PLAN FROM FLUTTER
// PATH:42,38,32,29
// ROUTE:SSX
// START
// ======================================================
const byte MAX_ROUTE = 48;
int routeNodes[MAX_ROUTE + 1];
char routeActions[MAX_ROUTE];
byte routeNodeCount = 0;
byte routeActionCount = 0;
int routeIndex = 0;
bool routeReady = false;
bool routeRunning = false;
bool routeFinished = false;
bool nodeLocked = false;
bool finishExitEnabled = false;
char finishExitAction = 'S';

unsigned long lastNodeTime = 0;
unsigned long nodeCandidateStart = 0;

unsigned long nodeCooldownMs = 450;
const unsigned long nodeUnlockMinMs = 200;

int nodePauseMs = 3000;
int nodeStraightForwardMs = 260;
int nodeTurnForwardMs = 260;
int finalStopForwardMs = 90;

int afterTurnForwardMs = 120;
int turnTimeoutMs = 1900;
int minTurnBeforeDetectMs = 320;
int lineStableMs = 45;
int lostConfirmMs = 35;
int telemetryIntervalMs = 140;

// Slower pivot values
int nodeTurnSpeed = 145;
int shallowTurnSpeed = 120;
int catchTurnSpeed = 105;
int minPivotPwm = 125;
int shallowMinTurnBeforeDetectMs = 180;
int nodeBlackMinCount = 6;
int lineBlackMinCount = 2;
int lineBlackMaxCount = 5;

int lastLineDirection = 0;
// -1 = left
//  0 = center
//  1 = right

// ======================================================
// SENSOR GLOBALS
// ======================================================
int rawSensor[8];
int binarySensor[8];
int blackCount = 0;
float currentPosition = 0;

// ======================================================
// TELEMETRY GLOBALS
// ======================================================
unsigned long lastTelemetryTime = 0;

// ======================================================
// FUNCTION PROTOTYPES
// ======================================================
void stopMotors();
void hardBrakeMotors(int brakeMs);
void setLedOff();
void setLedRed();
void setLedGreen();
void setLedBlue();
void setLedPink();
void setLedCyan();
void setLedYellow();
void setLedWhite();
void resetRouteProgress();
void enterTraversalReady();
void parsePathCommand(String pathText);
void parseRouteCommand(String routeText);
void parseFinishCommand(String finishText);
void startRoute();
bool routeStillActive();
void nodePauseBlocking();
void lineTraceMode();
void checkMovementFailsafe();
void updateLedMode();
void readLineSensors();
bool normalCenterDetected();
bool centerDetected();
bool nodeBlockDetected();
bool lineBandDetected();
bool lineCenteredDetected();
bool middleHasAdjacentBlackPair();
bool possibleNodeDetected();
void handleRouteNode();
void executeStraightNode();
void executeShallowLeftTurnNode();
void executeShallowRightTurnNode();
void executeLeftTurnNode();
void executeRightTurnNode();
void executeUTurnNode();
void executeFinishExitNode();

// ======================================================
// SETUP
// ======================================================
void setup() {
  // Bluetooth module & PC share hardware Serial at 9600 baud rate
  Serial.begin(9600);

  pinMode(PWMA, OUTPUT);
  pinMode(PWMB, OUTPUT);

  pinMode(AIN1, OUTPUT);
  pinMode(AIN2, OUTPUT);

  pinMode(BIN1, OUTPUT);
  pinMode(BIN2, OUTPUT);

  pinMode(BLUE_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);
  pinMode(RED_PIN, OUTPUT);

  for (int i = 0; i < 8; i++) {
    pinMode(sensorPins[i], INPUT);
  }

  stopMotors();
  setLedOff();

  // Startup indicator
  setLedRed();
  delay(300);
  setLedBlue();
  delay(300);
  setLedGreen();
  delay(300);

  robotMode = "MANUAL";
  ledMode = "BLUE";
  setLedBlue();

  Serial.println("==================================================");
  Serial.println("Hardware Serial Robot Controller Ready!");
  Serial.println("==================================================");
}

// ======================================================
// TELEMETRY SENDER
// ======================================================
void sendTelemetry() {
  int sensorValues[8];
  int activeBlackCount = 0;
  String bits = "";
  String rawValues = "";

  // Read all 8 sensors
  for (int i = 0; i < 8; i++) {
    sensorValues[i] = analogRead(sensorPins[i]);
    
    // Convert to binary bit based on threshold
    if (sensorValues[i] > threshold) {
      bits += "1";
      activeBlackCount++;
    } else {
      bits += "0";
    }
    
    // Package raw analog values
    rawValues += String(sensorValues[i]);
    if (i < 7) {
      rawValues += ",";
    }
  }

  // Calculate currentPosition
  readLineSensors();

  // Construct the SENS packet
  // Format: SENS:00000000|RAW:850,840...|POS:0.0|BLACK:0|THR:930
  String telemetryPacket = "SENS:" + bits + "|RAW:" + rawValues + "|POS:" + String(currentPosition, 2) + "|BLACK:" + String(activeBlackCount) + "|THR:" + String(threshold);

  Serial.println(telemetryPacket);
}

void checkTelemetry() {
  // Only stream telemetry automatically in LINE (Traversal) mode!
  // In MANUAL mode, automatic streaming is 100% DISABLED to save CPU/lag!
  if (robotMode == "LINE") {
    if (millis() - lastTelemetryTime >= (unsigned long)telemetryIntervalMs) {
      lastTelemetryTime = millis();
      sendTelemetry();
    }
  }
}

// ======================================================
// LOOP
// ======================================================
void loop() {
  readBluetooth();

  if (robotMode == "LINE" && routeRunning && !routeFinished) {
    lineTraceMode();
  } else if (robotMode == "LINE") {
    stopMotors();
    readLineSensors();
  }

  checkMovementFailsafe();
  updateLedMode();
  checkTelemetry();
}

// ======================================================
// BLUETOOTH READER
// ======================================================
void readBluetooth() {
  while (Serial.available()) {
    char c = Serial.read();
    lastCharTime = millis();

    if (c == '\r' || c == '\n') {
      if (commandBuffer.length() > 0) {
        processCommand(commandBuffer);
        commandBuffer = "";
      }
    } else {
      commandBuffer += c;
    }
  }

  if (commandBuffer.length() > 0 && millis() - lastCharTime > commandTimeout) {
    processCommand(commandBuffer);
    commandBuffer = "";
  }
}

// ======================================================
// COMMAND PROCESSOR
// ======================================================
void processCommand(String cmd) {
  cmd.trim();
  cmd.toUpperCase();

  if (cmd.length() == 0) return;

  // ---------------- TRAVERSAL ROUTE COMMANDS ----------------
  if (cmd.startsWith("PATH:")) {
    parsePathCommand(cmd.substring(5));
    return;
  } else if (cmd.startsWith("ROUTE:")) {
    parseRouteCommand(cmd.substring(6));
    return;
  } else if (cmd.startsWith("FINISH:")) {
    parseFinishCommand(cmd.substring(7));
    return;
  } else if (cmd.startsWith("MLINE:")) {
    parseRouteCommand(cmd.substring(6));
    startRoute();
    return;
  } else if (cmd == "START" || cmd == "RUN") {
    startRoute();
    return;
  }

  // ---------------- MOVEMENT COMMANDS ----------------
  if (cmd == "F") {
    robotMode = "MANUAL";
    markManualMovementActive();
    moveForward();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "B") {
    robotMode = "MANUAL";
    markManualMovementActive();
    moveBackward();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "L") {
    robotMode = "MANUAL";
    markManualMovementActive();
    rotateLeft();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "R") {
    robotMode = "MANUAL";
    markManualMovementActive();
    rotateRight();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "G") {
    robotMode = "MANUAL";
    markManualMovementActive();
    forwardLeft();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "I") {
    robotMode = "MANUAL";
    markManualMovementActive();
    forwardRight();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "H") {
    robotMode = "MANUAL";
    markManualMovementActive();
    backwardLeft();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "J") {
    robotMode = "MANUAL";
    markManualMovementActive();
    backwardRight();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "S") {
    robotMode = "MANUAL";
    manualMovementActive = false;
    routeRunning = false;
    routeFinished = false;
    finishExitEnabled = false;
    stopMotors();
    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  }

  // ---------------- SPEED COMMAND ----------------
  else if (cmd.startsWith("V")) {
    int newSpeed = cmd.substring(1).toInt();
    newSpeed = constrain(newSpeed, 90, 255);

    speedValue = newSpeed;

    slowSpeed = speedValue / 2;
    if (slowSpeed < 95) slowSpeed = 95;

    nodeTurnSpeed = constrain(speedValue - 10, 125, 170);

    Serial.print("OK:SPD=");
    Serial.println(speedValue);
  }

  // ---------------- LED COMMANDS ----------------
  else if (cmd == "CRED" || cmd == "RED") {
    ledMode = "RED";
    setLedRed();
    Serial.println("OK:LED=RED");
  } else if (cmd == "CGREEN" || cmd == "GREEN") {
    ledMode = "GREEN";
    setLedGreen();
    Serial.println("OK:LED=GREEN");
  } else if (cmd == "CBLUE" || cmd == "BLUE") {
    ledMode = "BLUE";
    setLedBlue();
    Serial.println("OK:LED=BLUE");
  } else if (cmd == "CPINK" || cmd == "PINK") {
    ledMode = "PINK";
    setLedPink();
    Serial.println("OK:LED=PINK");
  } else if (cmd == "CCYAN" || cmd == "CYAN") {
    ledMode = "CYAN";
    setLedCyan();
    Serial.println("OK:LED=CYAN");
  } else if (cmd == "CYELLOW" || cmd == "YELLOW") {
    ledMode = "YELLOW";
    setLedYellow();
    Serial.println("OK:LED=YELLOW");
  } else if (cmd == "CWHITE" || cmd == "WHITE") {
    ledMode = "WHITE";
    setLedWhite();
    Serial.println("OK:LED=WHITE");
  } else if (cmd == "COFF" || cmd == "OFF") {
    ledMode = "OFF";
    setLedOff();
    Serial.println("OK:LED=OFF");
  } else if (cmd == "CPOLICE" || cmd == "POLICE") {
    ledMode = "POLICE";
    ledStep = 0;
    lastLedUpdate = 0;
    Serial.println("OK:LED=POLICE");
  } else if (cmd == "CRAINBOW" || cmd == "RAINBOW") {
    ledMode = "RAINBOW";
    ledStep = 0;
    lastLedUpdate = 0;
    Serial.println("OK:LED=RAINBOW");
  } else if (cmd == "CRANDOM" || cmd == "RANDOM") {
    ledMode = "RANDOM";
    ledStep = 0;
    lastLedUpdate = 0;
    Serial.println("OK:LED=RANDOM");
  }

  // ---------------- MODE COMMANDS ----------------
  else if (cmd == "MMANUAL" || cmd == "MANUAL") {
    robotMode = "MANUAL";
    manualMovementActive = false;
    routeRunning = false;
    finishExitEnabled = false;
    stopMotors();

    ledMode = "BLUE";
    setLedBlue();

    Serial.println("STATE:MANUAL");
    Serial.println("OK:MANUAL");
  } else if (cmd == "MLINE" || cmd == "LINE") {
    enterTraversalReady();
  }

  // ---------------- UTILITY COMMANDS ----------------
  else if (cmd == "PING") {
    Serial.println("OK:PING");
  } else if (cmd == "GETSENS") {
    // One-time query responds to satisfy the watchdog in manual mode
    sendTelemetry();
  } else if (cmd == "TEL:RAW" || cmd == "TEL:COMPACT") {
    Serial.println("OK:TEL=RAW");
  }

  // ---------------- CONFIGURATION COMMANDS ----------------
  else if (cmd.startsWith("CFG:")) {
    String pair = cmd.substring(4);
    int equals = pair.indexOf('=');
    if (equals > 0) {
      String key = pair.substring(0, equals);
      key.trim();
      String valStr = pair.substring(equals + 1);
      valStr.trim();
      float val = valStr.toFloat();
      
      if (key == "THR") {
        threshold = constrain((int)val, 0, 1023);
      } else if (key == "SPD") {
        speedValue = constrain((int)val, 90, 255);
        if (slowSpeed > speedValue) slowSpeed = speedValue;
      } else if (key == "TURN") {
        nodeTurnSpeed = constrain((int)val, 60, 255);
      } else if (key == "STURN") {
        shallowTurnSpeed = constrain((int)val, 40, 220);
      } else if (key == "CATCHTURN") {
        catchTurnSpeed = constrain((int)val, 40, 220);
      } else if (key == "SLOW") {
        slowSpeed = constrain((int)val, 50, 220);
      } else if (key == "KP") {
        Kp = constrain(val, 0.0, 60.0);
      } else if (key == "PAUSE") {
        nodePauseMs = constrain((int)val, 0, 3000);
      } else if (key == "COOLDOWN") {
        nodeCooldownMs = (unsigned long)constrain((int)val, 0, 3000);
      } else if (key == "NODEFWD") {
        nodeStraightForwardMs = constrain((int)val, 0, 2500);
        nodeTurnForwardMs = nodeStraightForwardMs;
      } else if (key == "TURNTIME") {
        turnTimeoutMs = constrain((int)val, 200, 5000);
      } else if (key == "MINTURN") {
        minTurnBeforeDetectMs = constrain((int)val, 0, 2000);
      } else if (key == "SMINTURN") {
        shallowMinTurnBeforeDetectMs = constrain((int)val, 0, 1500);
      } else if (key == "AFTERTURN") {
        afterTurnForwardMs = constrain((int)val, 0, 2000);
      } else if (key == "FINALFWD") {
        finalStopForwardMs = constrain((int)val, 0, 1500);
      } else if (key == "MINPWM") {
        minDrivePwm = constrain((int)val, 0, 255);
      } else if (key == "MINPIVOT") {
        minPivotPwm = constrain((int)val, 0, 255);
      } else if (key == "LTRIM") {
        leftTrim = constrain((int)val, -80, 80);
      } else if (key == "RTRIM") {
        rightTrim = constrain((int)val, -80, 80);
      } else if (key == "STABLEMS") {
        lineStableMs = constrain((int)val, 0, 1000);
      } else if (key == "LOSTMS") {
        lostConfirmMs = constrain((int)val, 0, 1000);
      } else if (key == "NODEBLACK") {
        nodeBlackMinCount = constrain((int)val, 4, 8);
      } else if (key == "LINEMAX") {
        lineBlackMaxCount = constrain((int)val, 3, 7);
      } else if (key == "TELMS") {
        telemetryIntervalMs = constrain((int)val, 80, 1000);
      } else if (key == "MCURVE") {
        manualCurvePercent = constrain((int)val, 35, 90);
      } else {
        Serial.print("ERR:CFG_UNKNOWN=");
        Serial.println(key);
        return;
      }
      
      Serial.print("CFG:");
      Serial.print(key);
      Serial.print("=");
      Serial.println(valStr);
    }
  }
}

void resetRouteProgress() {
  routeIndex = 0;
  routeFinished = false;
  nodeLocked = false;
  lastNodeTime = 0;
  nodeCandidateStart = 0;
  lastLineDirection = 0;
}

void enterTraversalReady() {
  robotMode = "LINE";
  manualMovementActive = false;
  routeRunning = false;

  stopMotors();
  resetRouteProgress();

  ledMode = "LINE_DIAGNOSTIC";
  setLedGreen();

  Serial.println("STATE:LINE");
  Serial.println("OK:LINE");
  sendTelemetry();
}

void parsePathCommand(String pathText) {
  routeNodeCount = 0;

  int start = 0;
  while (start < pathText.length() && routeNodeCount < MAX_ROUTE + 1) {
    int comma = pathText.indexOf(',', start);
    if (comma < 0) comma = pathText.length();

    String token = pathText.substring(start, comma);
    token.trim();
    int node = token.toInt();

    if (node > 0) {
      routeNodes[routeNodeCount++] = node;
    }

    start = comma + 1;
  }

  routeReady = routeNodeCount > 0 && routeActionCount > 0;

  Serial.print("OK:PATH=");
  for (byte i = 0; i < routeNodeCount; i++) {
    if (i > 0) Serial.print(',');
    Serial.print(routeNodes[i]);
  }
  Serial.println();
}

void parseRouteCommand(String routeText) {
  routeActionCount = 0;

  for (int i = 0; i < routeText.length() && routeActionCount < MAX_ROUTE; i++) {
    char action = routeText.charAt(i);
    if (
      action == 'S' ||
      action == 'Q' ||
      action == 'E' ||
      action == 'L' ||
      action == 'R' ||
      action == 'U' ||
      action == 'X'
    ) {
      routeActions[routeActionCount++] = action;
    }
  }

  routeReady = routeNodeCount > 0 && routeActionCount > 0;

  Serial.print("OK:ROUTE=");
  for (byte i = 0; i < routeActionCount; i++) {
    Serial.print(routeActions[i]);
  }
  Serial.println();
}

void parseFinishCommand(String finishText) {
  finishText.trim();
  finishText.toUpperCase();

  if (finishText == "OFF" || finishText == "NONE" || finishText == "0") {
    finishExitEnabled = false;
    finishExitAction = 'S';
    Serial.println(F("OK:FINISH=OFF"));
    return;
  }

  if (finishText.length() == 0) {
    finishExitEnabled = false;
    Serial.println(F("ERR:FINISH_EMPTY"));
    return;
  }

  char action = finishText.charAt(0);
  if (
    action == 'S' ||
    action == 'Q' ||
    action == 'E' ||
    action == 'L' ||
    action == 'R' ||
    action == 'U'
  ) {
    finishExitEnabled = true;
    finishExitAction = action;
    Serial.print(F("OK:FINISH="));
    Serial.println(finishExitAction);
  } else {
    finishExitEnabled = false;
    Serial.println(F("ERR:FINISH_BAD"));
  }
}

void startRoute() {
  if (routeActionCount == 0) {
    routeRunning = false;
    routeReady = false;
    stopMotors();
    Serial.println("ERR:ROUTE_EMPTY");
    return;
  }

  if (routeNodeCount == 0) {
    routeRunning = false;
    routeReady = false;
    stopMotors();
    Serial.println("ERR:PATH_EMPTY");
    return;
  }

  robotMode = "LINE";
  manualMovementActive = false;
  routeReady = true;
  routeRunning = true;
  resetRouteProgress();

  ledMode = "LINE_DIAGNOSTIC";
  setLedGreen();

  Serial.println("STATE:ROUTE");
  Serial.println("OK:START");
}

// ======================================================
// MANUAL FAILSAFE
// ======================================================
void markManualMovementActive() {
  manualMovementActive = true;
  routeRunning = false;
  lastMovementCommandTime = millis();
}

void checkMovementFailsafe() {
  if (robotMode == "MANUAL" && manualMovementActive && millis() - lastMovementCommandTime > movementFailsafeMs) {
    manualMovementActive = false;
    stopMotors();
  }
}

// ======================================================
// MOTOR DIRECTION HELPERS
// ======================================================
void setLeftForward() {
  digitalWrite(AIN1, HIGH);
  digitalWrite(AIN2, LOW);
}

void setLeftBackward() {
  digitalWrite(AIN1, LOW);
  digitalWrite(AIN2, HIGH);
}

void setRightForward() {
  digitalWrite(BIN1, HIGH);
  digitalWrite(BIN2, LOW);
}

void setRightBackward() {
  digitalWrite(BIN1, LOW);
  digitalWrite(BIN2, HIGH);
}

// ======================================================
// MOTOR MOVEMENT
// ======================================================
void moveForward() {
  setLeftForward();
  setRightForward();

  analogWrite(PWMA, speedValue);
  analogWrite(PWMB, speedValue);
}

void moveBackward() {
  setLeftBackward();
  setRightBackward();

  analogWrite(PWMA, speedValue);
  analogWrite(PWMB, speedValue);
}

void rotateLeft() {
  setLeftBackward();
  setRightForward();

  analogWrite(PWMA, speedValue);
  analogWrite(PWMB, speedValue);
}

void rotateRight() {
  setLeftForward();
  setRightBackward();

  analogWrite(PWMA, speedValue);
  analogWrite(PWMB, speedValue);
}

void forwardLeft() {
  setLeftForward();
  setRightForward();

  int curveSpeed = constrain((speedValue * manualCurvePercent) / 100, minDrivePwm, speedValue);
  analogWrite(PWMA, curveSpeed);
  analogWrite(PWMB, speedValue);
}

void forwardRight() {
  setLeftForward();
  setRightForward();

  analogWrite(PWMA, speedValue);
  int curveSpeed = constrain((speedValue * manualCurvePercent) / 100, minDrivePwm, speedValue);
  analogWrite(PWMB, curveSpeed);
}

void backwardLeft() {
  setLeftBackward();
  setRightBackward();

  int curveSpeed = constrain((speedValue * manualCurvePercent) / 100, minDrivePwm, speedValue);
  analogWrite(PWMA, curveSpeed);
  analogWrite(PWMB, speedValue);
}

void backwardRight() {
  setLeftBackward();
  setRightBackward();

  analogWrite(PWMA, speedValue);
  int curveSpeed = constrain((speedValue * manualCurvePercent) / 100, minDrivePwm, speedValue);
  analogWrite(PWMB, curveSpeed);
}

void moveMotors(int leftSpeed, int rightSpeed) {
  setLeftForward();
  setRightForward();

  leftSpeed = constrain(leftSpeed + leftTrim, 0, maxSpeed);
  rightSpeed = constrain(rightSpeed + rightTrim, 0, maxSpeed);

  if (leftSpeed > 0 && leftSpeed < minDrivePwm) {
    leftSpeed = minDrivePwm;
  }

  if (rightSpeed > 0 && rightSpeed < minDrivePwm) {
    rightSpeed = minDrivePwm;
  }

  analogWrite(PWMA, leftSpeed);
  analogWrite(PWMB, rightSpeed);
}

void moveMotorsBackward(int leftSpeed, int rightSpeed) {
  setLeftBackward();
  setRightBackward();

  leftSpeed = constrain(leftSpeed + leftTrim, 0, maxSpeed);
  rightSpeed = constrain(rightSpeed + rightTrim, 0, maxSpeed);

  if (leftSpeed > 0 && leftSpeed < minDrivePwm) {
    leftSpeed = minDrivePwm;
  }

  if (rightSpeed > 0 && rightSpeed < minDrivePwm) {
    rightSpeed = minDrivePwm;
  }

  analogWrite(PWMA, leftSpeed);
  analogWrite(PWMB, rightSpeed);
}

void stopMotors() {
  analogWrite(PWMA, 0);
  analogWrite(PWMB, 0);
}

void hardBrakeMotors(int brakeMs) {
  // TB6612FNG short brake: IN1 and IN2 both HIGH while PWM is active
  digitalWrite(AIN1, HIGH);
  digitalWrite(AIN2, HIGH);
  digitalWrite(BIN1, HIGH);
  digitalWrite(BIN2, HIGH);

  analogWrite(PWMA, 255);
  analogWrite(PWMB, 255);

  delay(brakeMs);

  analogWrite(PWMA, 0);
  analogWrite(PWMB, 0);
}

void driveForwardTimed(int durationMs, int spd) {
  unsigned long start = millis();

  if (spd < minDrivePwm) spd = minDrivePwm;

  while (millis() - start < durationMs) {
    readBluetooth();
    if (robotMode != "LINE" || !routeRunning) {
      stopMotors();
      return;
    }
    moveMotors(spd, spd);
  }

  stopMotors();
}

bool routeStillActive() {
  return robotMode == "LINE" && routeRunning;
}

void nodePauseBlocking() {
  unsigned long start = millis();
  unsigned long lastBlink = 0;
  bool redState = true;

  stopMotors();
  Serial.println("STATE:PAUSE");

  while (millis() - start < (unsigned long)nodePauseMs) {
    readBluetooth();
    if (!routeStillActive()) {
      stopMotors();
      return;
    }

    stopMotors();
    if (millis() - lastBlink >= 120) {
      lastBlink = millis();
      if (redState) {
        setLedRed();
      } else {
        setLedBlue();
      }
      redState = !redState;
    }

    checkTelemetry();
    delay(5);
  }

  stopMotors();
}

void pivotLeftTimedControl(int spd) {
  if (spd < minPivotPwm) spd = minPivotPwm;
  spd = constrain(spd, 0, 255);

  setLeftBackward();
  setRightForward();

  analogWrite(PWMA, spd);
  analogWrite(PWMB, spd);
}

void pivotRightTimedControl(int spd) {
  if (spd < minPivotPwm) spd = minPivotPwm;
  spd = constrain(spd, 0, 255);

  setLeftForward();
  setRightBackward();

  analogWrite(PWMA, spd);
  analogWrite(PWMB, spd);
}

// ======================================================
// RGB LED
// ======================================================
void setLedRed() {
  digitalWrite(RED_PIN, HIGH);
  digitalWrite(GREEN_PIN, LOW);
  digitalWrite(BLUE_PIN, LOW);
}

void setLedGreen() {
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GREEN_PIN, HIGH);
  digitalWrite(BLUE_PIN, LOW);
}

void setLedBlue() {
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GREEN_PIN, LOW);
  digitalWrite(BLUE_PIN, HIGH);
}

void setLedPink() {
  digitalWrite(RED_PIN, HIGH);
  digitalWrite(GREEN_PIN, LOW);
  digitalWrite(BLUE_PIN, HIGH);
}

void setLedCyan() {
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GREEN_PIN, HIGH);
  digitalWrite(BLUE_PIN, HIGH);
}

void setLedYellow() {
  digitalWrite(RED_PIN, HIGH);
  digitalWrite(GREEN_PIN, HIGH);
  digitalWrite(BLUE_PIN, LOW);
}

void setLedWhite() {
  digitalWrite(RED_PIN, HIGH);
  digitalWrite(GREEN_PIN, HIGH);
  digitalWrite(BLUE_PIN, HIGH);
}

void setLedOff() {
  digitalWrite(RED_PIN, LOW);
  digitalWrite(GREEN_PIN, LOW);
  digitalWrite(BLUE_PIN, LOW);
}

// ======================================================
// LED EFFECTS
// ======================================================
void updateLedMode() {
  if (robotMode == "LINE") {
    return;
  }

  if (ledMode == "POLICE") {
    updatePoliceLed();
  } else if (ledMode == "RAINBOW") {
    updateRainbowLed();
  } else if (ledMode == "RANDOM") {
    updateRandomLed();
  }
}

void updatePoliceLed() {
  if (millis() - lastLedUpdate < 150) return;

  lastLedUpdate = millis();
  ledStep++;

  if (ledStep % 2 == 0) {
    setLedRed();
  } else {
    setLedBlue();
  }
}

void updateRainbowLed() {
  if (millis() - lastLedUpdate < 700) return;

  lastLedUpdate = millis();
  ledStep++;

  int colorIndex = ledStep % 7;

  if (colorIndex == 0) setLedRed();
  else if (colorIndex == 1) setLedYellow();
  else if (colorIndex == 2) setLedGreen();
  else if (colorIndex == 3) setLedCyan();
  else if (colorIndex == 4) setLedBlue();
  else if (colorIndex == 5) setLedPink();
  else if (colorIndex == 6) setLedWhite();
}

void updateRandomLed() {
  if (millis() - lastLedUpdate < 500) return;

  lastLedUpdate = millis();

  digitalWrite(RED_PIN, random(0, 2));
  digitalWrite(GREEN_PIN, random(0, 2));
  digitalWrite(BLUE_PIN, random(0, 2));
}

// ======================================================
// SENSOR READING
// ======================================================
void readLineSensors() {
  blackCount = 0;
  int weightedSum = 0;

  for (int i = 0; i < 8; i++) {
    rawSensor[i] = analogRead(sensorPins[i]);

    if (rawSensor[i] > threshold) {
      binarySensor[i] = 1;
    } else {
      binarySensor[i] = 0;
    }
  }

  // Fill tiny one-sensor gaps.
  for (int i = 1; i < 7; i++) {
    if (binarySensor[i] == 0 && binarySensor[i - 1] == 1 && binarySensor[i + 1] == 1) {
      binarySensor[i] = 1;
    }
  }

  for (int i = 0; i < 8; i++) {
    if (binarySensor[i] == 1) {
      blackCount++;
      weightedSum += weights[i];
    }
  }

  if (blackCount > 0) {
    currentPosition = (float)weightedSum / blackCount;
  } else {
    currentPosition = 0;
  }

  if (middleHasAdjacentBlackPair() && !nodeBlockDetected()) {
    nodeCandidateStart = 0;
  }
}

bool centerDetected() {
  return (
    (binarySensor[3] == 1 && binarySensor[4] == 1) || 
    (binarySensor[2] == 1 && binarySensor[3] == 1 && binarySensor[4] == 1) || 
    (binarySensor[3] == 1 && binarySensor[4] == 1 && binarySensor[5] == 1) || 
    (binarySensor[2] == 1 && binarySensor[3] == 1 && binarySensor[4] == 1 && binarySensor[5] == 1)
  );
}

bool normalCenterDetected() {
  bool outerBlack =
    binarySensor[0] == 1 || binarySensor[1] == 1 || binarySensor[6] == 1 || binarySensor[7] == 1;

  return centerDetected() && blackCount >= 2 && blackCount <= 4 && !outerBlack;
}

bool nodeBlockDetected() {
  return blackCount >= nodeBlackMinCount;
}

bool lineBandDetected() {
  return blackCount >= lineBlackMinCount && blackCount <= lineBlackMaxCount;
}

bool lineCenteredDetected() {
  return centerDetected() && lineBandDetected() && !nodeBlockDetected();
}

bool middleHasAdjacentBlackPair() {
  return (
    (binarySensor[2] == 1 && binarySensor[3] == 1) ||
    (binarySensor[3] == 1 && binarySensor[4] == 1) ||
    (binarySensor[4] == 1 && binarySensor[5] == 1)
  );
}

bool possibleNodeDetected() {
  if (!routeRunning || routeIndex >= routeActionCount) return false;

  unsigned long now = millis();

  if (!nodeBlockDetected()) {
    nodeCandidateStart = 0;
    return false;
  }

  if (nodeCandidateStart == 0) {
    nodeCandidateStart = now;
    return false;
  }

  return now - nodeCandidateStart >= (unsigned long)lostConfirmMs;
}

// ======================================================
// LINE TRACE MODE
// ======================================================
void lineTraceMode() {
  if (routeFinished) {
    routeRunning = false;
    stopMotors();
    setLedWhite();
    Serial.println("STATE:FINISHED");
    return;
  }

  readLineSensors();

  if (nodeLocked && millis() - lastNodeTime > nodeUnlockMinMs && lineCenteredDetected()) {
    nodeLocked = false;
  }

  if (!nodeLocked && millis() - lastNodeTime > nodeCooldownMs && possibleNodeDetected()) {
    handleRouteNode();
    return;
  }

  if (blackCount == 0) {
    setLedYellow();

    if (lastLineDirection < 0) {
      pivotLeftTimedControl(slowSpeed);
    } else if (lastLineDirection > 0) {
      pivotRightTimedControl(slowSpeed);
    } else {
      stopMotors();
    }

    return;
  }

  int correction = currentPosition * Kp;

  int leftSpeed = speedValue + correction;
  int rightSpeed = speedValue - correction;

  leftSpeed = constrain(leftSpeed, 0, maxSpeed);
  rightSpeed = constrain(rightSpeed, 0, maxSpeed);

  if (normalCenterDetected()) {
    setLedGreen();
    lastLineDirection = 0;
    moveMotors(speedValue, speedValue);
  } else if (currentPosition < -0.8) {
    setLedRed();
    lastLineDirection = -1;
    moveMotors(leftSpeed, rightSpeed);
  } else if (currentPosition > 0.8) {
    setLedBlue();
    lastLineDirection = 1;
    moveMotors(leftSpeed, rightSpeed);
  } else {
    setLedPink();
    moveMotors(leftSpeed, rightSpeed);
  }
}

// ======================================================
// NODE HANDLING
// ======================================================
void handleRouteNode() {
  if (!routeRunning || routeIndex >= routeActionCount) {
    routeFinished = true;
    routeRunning = false;
    stopMotors();
    setLedWhite();
    Serial.println("STATE:FINISHED");
    return;
  }

  nodeLocked = true;
  lastNodeTime = millis();
  nodeCandidateStart = 0;
  lastLineDirection = 0;

  // Active hard brake immediately to prevent physical coasting overlap
  hardBrakeMotors(35);

  int nodeLabel = routeIndex < routeNodeCount ? routeNodes[routeIndex] : routeIndex + 1;
  char action = routeActions[routeIndex];

  Serial.print("NODE:");
  Serial.println(nodeLabel);
  Serial.print("IDX:");
  Serial.print(routeIndex + 1);
  Serial.print('/');
  Serial.println(routeActionCount);
  Serial.print("CMD:");
  Serial.println(action);
  Serial.println("STATE:NODE");

  nodePauseBlocking();
  if (!routeStillActive()) {
    return;
  }

  if (action == 'X') {
    Serial.println("STATE:FINAL_NODE");
    if (finishExitEnabled) {
      executeFinishExitNode();
    } else {
      driveForwardTimed(finalStopForwardMs, slowSpeed);
    }

    stopMotors();
    setLedWhite();

    routeFinished = true;
    routeRunning = false;
    Serial.println("STATE:FINISHED");
    return;
  }

  if (action == 'S') {
    executeStraightNode();
  } else if (action == 'Q') {
    executeShallowLeftTurnNode();
  } else if (action == 'E') {
    executeShallowRightTurnNode();
  } else if (action == 'L') {
    executeLeftTurnNode();
  } else if (action == 'R') {
    executeRightTurnNode();
  } else if (action == 'U') {
    executeUTurnNode();
  }

  routeIndex++;

  if (routeIndex >= routeActionCount) {
    routeFinished = true;
    routeRunning = false;
    stopMotors();
    setLedWhite();
    Serial.println("STATE:FINISHED");
  }
}

void executeStraightNode() {
  Serial.println("STATE:STRAIGHT");
  setLedGreen();

  driveForwardTimed(nodeStraightForwardMs, slowSpeed);
  Serial.println("STATE:RESUME_LINE");
}

void executeShallowLeftTurnNode() {
  Serial.println(F("STATE:TURN_LEFT_SHALLOW"));
  setLedRed();

  driveForwardTimed(nodeTurnForwardMs, slowSpeed);

  unsigned long start = millis();
  unsigned long centerStart = 0;
  bool catchLogged = false;

  while (millis() - start < turnTimeoutMs) {
    readBluetooth();
    if (!routeStillActive()) {
      stopMotors();
      return;
    }
    bool detectionAllowed = millis() - start > (unsigned long)shallowMinTurnBeforeDetectMs;
    if (detectionAllowed && !catchLogged) {
      Serial.println(F("STATE:TURN_CATCH"));
      catchLogged = true;
    }
    pivotLeftTimedControl(detectionAllowed ? catchTurnSpeed : shallowTurnSpeed);
    readLineSensors();

    if (detectionAllowed && lineCenteredDetected()) {
      if (centerStart == 0) centerStart = millis();

      if (millis() - centerStart >= (unsigned long)lineStableMs) {
        stopMotors();
        delay(80);

        driveForwardTimed(afterTurnForwardMs, speedValue);
        return;
      }
    } else {
      centerStart = 0;
    }
  }

  stopMotors();
  Serial.println(F("WARN:TURN_LEFT_SHALLOW_TIMEOUT"));
}

void executeShallowRightTurnNode() {
  Serial.println(F("STATE:TURN_RIGHT_SHALLOW"));
  setLedBlue();

  driveForwardTimed(nodeTurnForwardMs, slowSpeed);

  unsigned long start = millis();
  unsigned long centerStart = 0;
  bool catchLogged = false;

  while (millis() - start < turnTimeoutMs) {
    readBluetooth();
    if (!routeStillActive()) {
      stopMotors();
      return;
    }
    bool detectionAllowed = millis() - start > (unsigned long)shallowMinTurnBeforeDetectMs;
    if (detectionAllowed && !catchLogged) {
      Serial.println(F("STATE:TURN_CATCH"));
      catchLogged = true;
    }
    pivotRightTimedControl(detectionAllowed ? catchTurnSpeed : shallowTurnSpeed);
    readLineSensors();

    if (detectionAllowed && lineCenteredDetected()) {
      if (centerStart == 0) centerStart = millis();

      if (millis() - centerStart >= (unsigned long)lineStableMs) {
        stopMotors();
        delay(80);

        driveForwardTimed(afterTurnForwardMs, speedValue);
        return;
      }
    } else {
      centerStart = 0;
    }
  }

  stopMotors();
  Serial.println(F("WARN:TURN_RIGHT_SHALLOW_TIMEOUT"));
}

void executeLeftTurnNode() {
  Serial.println("STATE:TURN_LEFT");
  setLedRed();

  driveForwardTimed(nodeTurnForwardMs, slowSpeed);

  unsigned long start = millis();
  unsigned long centerStart = 0;
  bool catchLogged = false;

  while (millis() - start < turnTimeoutMs) {
    readBluetooth();
    if (!routeStillActive()) {
      stopMotors();
      return;
    }
    bool detectionAllowed = millis() - start > (unsigned long)minTurnBeforeDetectMs;
    if (detectionAllowed && !catchLogged) {
      Serial.println("STATE:TURN_CATCH");
      catchLogged = true;
    }
    pivotLeftTimedControl(detectionAllowed ? catchTurnSpeed : nodeTurnSpeed);
    readLineSensors();

    if (detectionAllowed && lineCenteredDetected()) {
      if (centerStart == 0) centerStart = millis();

      if (millis() - centerStart >= (unsigned long)lineStableMs) {
        stopMotors();
        delay(80);

        driveForwardTimed(afterTurnForwardMs, speedValue);
        return;
      }
    } else {
      centerStart = 0;
    }
  }

  stopMotors();
  Serial.println("WARN:TURN_LEFT_TIMEOUT");
}

void executeRightTurnNode() {
  Serial.println("STATE:TURN_RIGHT");
  setLedBlue();

  driveForwardTimed(nodeTurnForwardMs, slowSpeed);

  unsigned long start = millis();
  unsigned long centerStart = 0;
  bool catchLogged = false;

  while (millis() - start < turnTimeoutMs) {
    readBluetooth();
    if (!routeStillActive()) {
      stopMotors();
      return;
    }
    bool detectionAllowed = millis() - start > (unsigned long)minTurnBeforeDetectMs;
    if (detectionAllowed && !catchLogged) {
      Serial.println("STATE:TURN_CATCH");
      catchLogged = true;
    }
    pivotRightTimedControl(detectionAllowed ? catchTurnSpeed : nodeTurnSpeed);
    readLineSensors();

    if (detectionAllowed && lineCenteredDetected()) {
      if (centerStart == 0) centerStart = millis();

      if (millis() - centerStart >= (unsigned long)lineStableMs) {
        stopMotors();
        delay(80);

        driveForwardTimed(afterTurnForwardMs, speedValue);
        return;
      }
    } else {
      centerStart = 0;
    }
  }

  stopMotors();
  Serial.println("WARN:TURN_RIGHT_TIMEOUT");
}

void executeUTurnNode() {
  Serial.println("STATE:UTURN");
  setLedYellow();

  driveForwardTimed(nodeTurnForwardMs, slowSpeed);

  unsigned long start = millis();
  int uTurnTimeoutMs = turnTimeoutMs + 900;
  int uTurnMinDetectMs = minTurnBeforeDetectMs + 250;
  unsigned long centerStart = 0;
  bool catchLogged = false;

  while (millis() - start < (unsigned long)uTurnTimeoutMs) {
    readBluetooth();
    if (!routeStillActive()) {
      stopMotors();
      return;
    }
    bool detectionAllowed = millis() - start > (unsigned long)uTurnMinDetectMs;
    if (detectionAllowed && !catchLogged) {
      Serial.println("STATE:TURN_CATCH");
      catchLogged = true;
    }
    pivotRightTimedControl(detectionAllowed ? catchTurnSpeed : nodeTurnSpeed);
    readLineSensors();

    if (detectionAllowed && lineCenteredDetected()) {
      if (centerStart == 0) centerStart = millis();

      if (millis() - centerStart >= (unsigned long)lineStableMs) {
        stopMotors();
        delay(80);

        driveForwardTimed(afterTurnForwardMs, speedValue);
        return;
      }
    } else {
      centerStart = 0;
    }
  }

  stopMotors();
  Serial.println("WARN:UTURN_TIMEOUT");
}

void executeFinishExitNode() {
  Serial.print(F("STATE:FINISH_EXIT_"));
  Serial.println(finishExitAction);

  if (finishExitAction == 'S') {
    executeStraightNode();
  } else if (finishExitAction == 'Q') {
    executeShallowLeftTurnNode();
  } else if (finishExitAction == 'E') {
    executeShallowRightTurnNode();
  } else if (finishExitAction == 'L') {
    executeLeftTurnNode();
  } else if (finishExitAction == 'R') {
    executeRightTurnNode();
  } else if (finishExitAction == 'U') {
    executeUTurnNode();
  }

  driveForwardTimed(finalStopForwardMs, slowSpeed);
}
