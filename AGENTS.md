# Robot Bluetooth Controller Agent Notes

This repository is the active Flutter Android app and Arduino Nano firmware for a Bluetooth HC-05 robot controller.

## Project Location

- Main repo: `/home/eru/robot_bluetooth_controller`
- Current firmware copy inside repo: `/home/eru/robot_bluetooth_controller/firmware/robot_traversal_current_uploaded.ino`
- Arduino upload project folder: `/home/eru/robot_bt_manual_test`
- Extra firmware backup copy: `/home/eru/Downloads/robot_traversal_current_uploaded.ino`

The repo was pushed to GitHub at:

- Remote: `https://github.com/Erlavush/robot_bluetooth_controller`
- Branch: `main`
- Known saved commit: `3d6beff` (`Save robot traversal controller snapshot`)

## Hardware

- Board: Arduino Nano
- Bluetooth: HC-05 classic Bluetooth, SPP/RFCOMM only, not BLE
- HC-05 currently uses Nano hardware serial pins:
  - Nano RX0/D0
  - Nano TX1/D1
- Important: unplug RX0/TX1 while uploading firmware to the Nano.
- Motor driver: TB6612FNG
- Motor pins:
  - `PWMA` D5
  - `PWMB` D6
  - `AIN1` D7
  - `AIN2` D8
  - `BIN1` D9
  - `BIN2` D10
- RGB LED pins:
  - Blue D2
  - Green D3
  - Red D4
- 8 line sensors:
  - D1-D8 sensor channels map to Nano `A0-A7`
  - Firmware raw order is `D1,D2,D3,D4,D5,D6,D7,D8`
  - UI displays reversed as `D8,D7,D6,D5,D4,D3,D2,D1`

## Bluetooth Rules

Preserve the existing classic Bluetooth implementation.

- Do not replace HC-05 communication with BLE.
- Flutter uses native Android Kotlin channels:
  - MethodChannel: `robot_bluetooth_controller/classic_bluetooth`
  - EventChannel: `robot_bluetooth_controller/classic_bluetooth_events`
- HC-05 UUID:
  - `00001101-0000-1000-8000-00805F9B34FB`
- Native connection logic uses:
  - `createRfcommSocketToServiceRecord`
  - `createInsecureRfcommSocketToServiceRecord`
  - fallback channel 1
- Every command sent to Arduino must end with newline.

## Current App Flow

### Manual Mode

- App opens in manual mode.
- On Bluetooth connect, app sends manual setup and blue LED.
- Manual buttons send:
  - `F` forward
  - `B` backward
  - `L` rotate left
  - `R` rotate right
  - `G` forward-left
  - `I` forward-right
  - `H` backward-left
  - `J` backward-right
  - `S` stop
- Held movement sends immediate command and heartbeat repeats.
- Releasing movement sends `S`.
- LED menu sends `CRED`, `CGREEN`, `CBLUE`, `CPINK`, `CCYAN`, `CYELLOW`, `CWHITE`, `COFF`, `CPOLICE`, `CRAINBOW`, `CRANDOM`.
- Manual log is separate from traversal telemetry and should show user command activity.

### Traversal Mode

Entering traversal mode must not make the robot drive.

When user taps Traversal Mode:

1. Flutter sends `S`.
2. Flutter sends `LINE`.
3. Firmware enters traversal-ready mode:
   - Motors stopped
   - LED green
   - Sensor telemetry enabled
   - Robot does not run yet

When user selects a route and presses Confirm:

1. Flutter sends `S`
2. Flutter sends `LINE`
3. Flutter sends `PATH:<node list>`
4. Flutter sends `ROUTE:<commands>`
5. Flutter sends `START`

Only `START` should make the robot begin line traversal.

Back to Manual or Stop must send:

- `S`
- `MANUAL`
- `CBLUE`

## Firmware Traversal Protocol

Firmware accepts:

- `LINE`: traversal-ready only, does not drive
- `PATH:42,38,32,29`: loads path nodes
- `ROUTE:SSX`: loads route actions
- `START`: starts line traversal
- `S`: stop and return manual
- `MANUAL`: stop and return manual
- `CFG:CATCHTURN=<value>`: slower catch-turn pivot speed after blind turn time

Firmware emits traversal logs:

- `STATE:LINE`
- `STATE:ROUTE`
- `NODE:<node>`
- `IDX:<current>/<total>`
- `CMD:<S/L/R/U/X>`
- `STATE:NODE`
- `STATE:STRAIGHT`
- `STATE:TURN_LEFT`
- `STATE:TURN_RIGHT`
- `STATE:TURN_CATCH`
- `STATE:UTURN`
- `STATE:FINAL_NODE`
- `STATE:FINISHED`

Route commands mean:

- `S`: go straight through node
- `L`: turn left
- `R`: turn right
- `U`: U-turn
- `X`: final stop node

Turn handling is two-speed:

1. Drive forward using `NODEFWD` with detection disabled.
2. Blind rotate using `TURN` until `MINTURN` has elapsed.
3. Slow catch rotate using `CATCHTURN`.
4. Accept the new line once center sensors are stable for `STABLEMS`.

## Sensor Telemetry

Firmware sends raw telemetry like:

```text
SENS:00111100|RAW:120,180,950,963,970,940,210,160|POS:0.00|BLACK:4|THR:900
```

Flutter must always parse `SENS:` packets so the top sensor UI keeps updating.

Critical rule:

- Do parse `SENS:` and `T:` telemetry.
- Do not append `SENS:` / raw telemetry packets to the visible Arduino Log during traversal, because it hides node logs.
- Filtering must happen after parsing, not before parsing.

This was a previous source of breakage. If the red sensor panels disappear, check that `RobotTelemetry.parseLine(line)` still runs before any display-log filter.

## Current Important Files

- `lib/main.dart`: app shell and orientation/fullscreen setup
- `lib/screens/manual_control_screen.dart`: manual driving screen
- `lib/screens/traversal_screen.dart`: traversal UI, sensor bar, map, route confirm flow
- `lib/models/robot_graph.dart`: hardcoded graph nodes/edges/coordinates
- `lib/models/route_planner.dart`: shortest path and turn command generation
- `lib/models/calibration.dart`: calibration definitions
- `lib/widgets/node_map.dart`: map painter and click handling
- `lib/services/bluetooth_service.dart`: Bluetooth state, command sending, telemetry parser integration, logs
- `lib/services/native_classic_bluetooth.dart`: Flutter wrapper for native Kotlin channels
- `android/app/src/main/kotlin/com/example/robot_bluetooth_controller/MainActivity.kt`: native classic Bluetooth SPP/RFCOMM code
- `firmware/robot_traversal_current_uploaded.ino`: current uploaded Nano sketch copy

## Validation Commands

From repo root:

```bash
/home/eru/Tools/flutter/bin/flutter analyze --no-pub
```

Build APK:

```bash
JAVA_HOME=/home/eru/.jdks PATH=/home/eru/.jdks/bin:$PATH /home/eru/Tools/flutter/bin/flutter build apk --debug --no-pub
```

Install APK to connected phone:

```bash
adb -s 8TEUFEOVFMUCW4JN install -r build/app/outputs/flutter-apk/app-debug.apk
```

Compile firmware:

```bash
arduino-cli compile --fqbn arduino:avr:nano /home/eru/robot_bt_manual_test
```

Upload firmware:

```bash
arduino-cli upload -p /dev/ttyUSB0 --fqbn arduino:avr:nano /home/eru/robot_bt_manual_test
```

Safe no-drive serial smoke test:

```bash
/bin/bash -lc 'stty -F /dev/ttyUSB0 9600 raw -echo; timeout 8 cat /dev/ttyUSB0 & reader=$!; sleep 3; printf "LINE\nPATH:42,38,32,29\nROUTE:SSX\nS\n" > /dev/ttyUSB0; wait $reader'
```

Expected smoke-test response includes:

```text
STATE:LINE
OK:LINE
SENS:...
OK:PATH=42,38,32,29
OK:ROUTE=SSX
STATE:MANUAL
OK:MANUAL
```

Do not send `START` in a smoke test unless the robot is physically safe to move.

## Known Practical Notes

- `/dev/ttyUSB0` sometimes disappears briefly; rescan with `arduino-cli board list`.
- The phone device previously appeared as `8TEUFEOVFMUCW4JN`.
- The app is intentionally fullscreen landscape.
- Fonts are bundled locally:
  - Quicksand for the app UI
  - Fira Code for logs/serial monitor text
- Traversal sensor UI should default to showing raw values.
- Manual telemetry should stay minimal to avoid control lag.
- Visible traversal log should prioritize route and node events, not raw sensor spam.

## Agent Safety Rules

- Do not revert user changes without explicit permission.
- Do not replace classic Bluetooth with BLE.
- Do not disable sensor telemetry parsing to make logs cleaner.
- Do not make `LINE` start the robot driving. `LINE` is ready mode; `START` is run mode.
- If editing firmware, keep the repo copy and Arduino project copy synchronized:
  - `/home/eru/robot_bluetooth_controller/firmware/robot_traversal_current_uploaded.ino`
  - `/home/eru/robot_bt_manual_test/robot_bt_manual_test.ino`
- If firmware is uploaded successfully, update the firmware copy in the repo before committing.
