# Flutter Build Instructions & Important Paths

If you need to build the app again in the future or find where things are stored, refer to this document.

## 📍 Important Locations

* **Flutter SDK Path:** 
  `C:\Users\joseph\.gemini\antigravity\scratch\flutter_setup\flutter\bin\flutter.bat`
  *(Note: Because Flutter isn't added to your system's global environment variables, you have to use this full path to run flutter commands in the terminal)*

* **Android SDK Path:**
  `C:\Users\joseph\AppData\Local\Android\sdk`

* **Release APK Output Location:**
  `build\app\outputs\flutter-apk\app-release.apk`
  *(Absolute path: `C:\Users\joseph\.gemini\antigravity\playground\TuroLink\build\app\outputs\flutter-apk\app-release.apk`)*

## 🛠️ How to Build a Release APK

To build a fresh release APK, open your terminal (make sure you are inside the `TuroLink` project folder) and run the following command using the absolute path to your Flutter batch file:

```powershell
C:\Users\joseph\.gemini\antigravity\scratch\flutter_setup\flutter\bin\flutter.bat build apk --release
```

## ⏳ Why the Build Process Takes Long

Occasionally, you might notice that running the build command above takes several minutes to execute. Here's why this happens:

1. **Gradle and Dependency Resolution (`Downloading packages...`)**: Especially if you wipe the build directory or it's a first-time build, Flutter has to use Gradle to re-evaluate your `pubspec.yaml`, fetch your packages from `pub.dev`, and resolve complex dependencies. The `nearby_connections` plugin relies on additional platform-specific requirements.
2. **Release Mode Compilation (`Running Gradle task 'assembleRelease'...`)**: Release builds fundamentally take much longer than debug builds.
   - Using the Dart compiler (AOT compilation), the entire source code natively compiles to machine code (ARM) rather than a fast VM instance.
   - Android tools (like ProGuard / R8 defaults) shrink down and process removing unseen code during this phase, making the final APK as small and performant as possible.
