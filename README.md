# TuroLink (P2P Classroom)

TuroLink is a Flutter application designed for creating and joining peer-to-peer (P2P) classrooms.

This guide provides instructions for anyone looking to set up, run, or build this project from scratch.

## 🚀 Prerequisites

Before you can run or build the app, you need to have the Flutter SDK installed on your machine.

1. **Install Flutter SDK:**
   Follow the official instructions to install Flutter for your operating system:
   [Flutter Installation Guide](https://docs.flutter.dev/get-started/install)
   *(Make sure you also set up your Android development environment by installing Android Studio and the Android SDK as guided in the link above).*

2. **Verify Installation:**
   Open a terminal/command prompt and run:
   ```bash
   flutter doctor
   ```
   Resolve any missing dependencies (like accepting Android licenses or installing command-line tools) indicated by the output.

---

## 💻 How to Run the App (Development)

To test and run the app during development, you will need either a connected physical Android/iOS device or an emulator running.

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/jojseph/TuroLink.git
   ```

2. **Navigate to the Project Folder:**
   ```bash
   cd TuroLink
   ```

3. **Get Dependencies:**
   Fetch all the required packages (this reads the `pubspec.yaml` file):
   ```bash
   flutter pub get
   ```

4. **Run the App:**
   With your device connected or emulator running, execute:
   ```bash
   flutter run
   ```
   If you have multiple devices connected, Flutter will prompt you to select one, or you can specify the device ID: `flutter run -d <device_id>`.

---

## 📦 How to Build an APK (Production)

If you want to create an `.apk` file that can be shared and installed on any Android device, you'll need to build a release APK.

1. Open your terminal in the root of the project folder (`TuroLink`).
2. Run the following command:
   ```bash
   flutter build apk --release
   ```
3. Wait for the build process to finish. It will take a few minutes.
4. Once completed, your APK will be available at this path inside the project:
   ```text
   build/app/outputs/flutter-apk/app-release.apk
   ```
   You can copy this `app-release.apk` file to your Android phone and install it directly!

---

## 📚 Helpful Resources

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)
- [Flutter Online Documentation](https://docs.flutter.dev/)
