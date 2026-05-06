# 📞 LiveKit Voice & Video Call Flutter SDK

SDK Flutter untuk membangun fitur **Voice Call** dan **Video Call** real-time berbasis **LiveKit (WebRTC)** dengan arsitektur yang stabil, scalable, dan siap production.

SDK ini menggunakan pendekatan **Call Engine + SDK Layer**, sehingga:
- tidak ada duplikasi logic (caller vs callee)
- lifecycle panggilan konsisten
- mudah diintegrasikan ke berbagai aplikasi

---

## ✨ Key Features

- 🔊 **Voice & 🎥 Video Call (Realtime)**  
  Latensi rendah menggunakan WebRTC via LiveKit

- 🧠 **Centralized Call Engine (SSOT)**  
  Semua state & lifecycle dikelola oleh `CallEngine`

- 🔁 **Stable Call Lifecycle**  
  Start → Ringing → Connected → End

- 🔒 **Single Active Call Enforcement**  
  Mencegah multiple call dalam satu waktu

- 🎛️ **Media Control**  
  Toggle mic, kamera, dan switch kamera

- 🔌 **Abstraction Layer (Media + Signaling)**  
  Mudah swap LiveKit / signaling tanpa ubah core logic

- 📜 **Structured Logging**  
  Logging lifecycle dan event untuk debugging

---

## 🏗️ Architecture Overview

SDK menggunakan layered architecture:


SDK / UI
↓
Application (light orchestration)
↓
CallEngine (core logic & state machine)
↓
Infrastructure (LiveKit / Signaling)


---

## ⚙️ Prerequisites

Pastikan sudah memiliki:

1. Flutter SDK (disarankan versi terbaru)
2. Server LiveKit:
   - LiveKit Cloud, atau
   - Self-hosted LiveKit
3. Credentials:
   - LiveKit URL (wss)
   - Access Token

---

## 📱 Platform Setup

### Android

Tambahkan permission di:
`android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
🍏 iOS

Tambahkan di:
ios/Runner/Info.plist

<key>NSCameraUsageDescription</key>
<string>Aplikasi membutuhkan akses kamera untuk video call</string>

<key>NSMicrophoneUsageDescription</key>
<string>Aplikasi membutuhkan akses mikrofon untuk voice call</string>
📦 Installation

Tambahkan dependency:

dependencies:
  flutter:
    sdk: flutter
  livekit_client: ^2.0.0

Lalu jalankan:

flutter pub get
🚀 Quick Start
1. Connect ke Room
final room = Room();

await room.connect(
  'wss://your-livekit-url',
  'YOUR_ACCESS_TOKEN',
);
2. Enable Media
await room.localParticipant.setMicrophoneEnabled(true);
await room.localParticipant.setCameraEnabled(true);
3. Render Video
VideoTrackRenderer(track);
4. Disconnect
await room.disconnect();
🔁 Call Lifecycle (Engine)

Lifecycle dikelola oleh CallEngine:

idle
 → calling
 → ringing
 → connecting
 → connected
 → ended

Engine memastikan:

state tidak lompat
tidak ada race condition
satu call aktif dalam satu waktu
📜 Logging

SDK menyediakan logging untuk:

state transition
signaling event
media event
error

Disarankan untuk menghubungkan ke logger aplikasi (Crashlytics / custom logger)

📁 Example

Cek folder:
/example

Untuk implementasi:

UI call screen
event handling
video grid
🤝 Contribution

Kontribusi terbuka:

buka issue
submit pull request
diskusi improvement
📄 License

MIT License