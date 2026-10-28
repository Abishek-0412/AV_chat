# AV_chat

Ephemeral, end-to-end encrypted chat and voice calls (Android). See [PLAN.md](PLAN.md).

| Folder | What |
|---|---|
| `app/` | Flutter Android app |
| `server/` | Relay server (Dart). Memory only, saves nothing |
| `packages/av_protocol/` | Message envelope format shared by app and server |

## Run

```bash
# 1. Start the relay on your PC
cd server && dart run bin/server.dart          # listens on 0.0.0.0:8080
curl localhost:8080/health                     # {"status":"ok","protocol":1}

# 2a. App on the Android emulator (reaches the PC at 10.0.2.2)
cd app && flutter run

# 2b. App on a real phone on the same Wi-Fi (use your PC's LAN IP: `hostname -I`)
cd app && flutter run --dart-define=RELAY_URL=ws://192.168.1.5:8080

# 2c. UI only, no server needed
cd app && flutter run -t lib/main_sandbox.dart
```

## Check

```bash
(cd packages/av_protocol && dart test)
(cd server && dart analyze && dart test)
(cd app && flutter analyze && flutter test)
```
