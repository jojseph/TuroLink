# TuroLink (P2P Classroom)

TuroLink is a Flutter application designed for creating and joining peer-to-peer (P2P) classrooms.

## 📝 Project Description

TuroLink is an innovative peer-to-peer (P2P) classroom solution built with Flutter, designed to facilitate learning and collaboration in environments with limited or no internet connectivity. By leveraging local network technologies, TuroLink allows educators and students to connect directly, share documents, and interact in real-time.

**Key Highlights:**
- **Offline First:** Seamless P2P communication using `nearby_connections`.
- **On-Device AI:** Integrated AI assistance powered by **Google Gemma**.
- **Secure Handling:** PDF generation and secure document sharing.
- **Easy Onboarding:** QR-based connection and intuitive dashboard experience.

## 🔗 Quick Links

- **Pitch + Demo:** [YouTube](https://youtu.be/667e4-XLki4) (Backup Link: [Google Drive](https://drive.google.com/drive/folders/1MLIYqsAdG0JEr6-jt9iNSLSmvBFAnVsJ?usp=drive_link)) *[Note: Video is copyrighted; provided as a backup]*
- **Report - Borneo:** [Google Drive](https://drive.google.com/drive/folders/1lVW6oYmO7mZtW9Xkt6cuS8FdJgW1Ncmq?usp=sharing)

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
   flutter build apk --release --no-tree-shake-icons

   *(Note: If the `flutter` command is not recognized, you may need to use the full path to the executable, for example: `C:\Users\joseph\.gemini\antigravity\scratch\flutter_setup\flutter\bin\flutter.bat build apk --release --no-tree-shake-icons`)*
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
