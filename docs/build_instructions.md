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
  *(Absolute path: `C:\Users\joseph\.gemini\antigravity\playground\zonal-kuiper\build\app\outputs\flutter-apk\app-release.apk`)*

## 🛠️ How to Build a Release APK

To build a fresh release APK, open your terminal (make sure you are inside the `zonal-kuiper` project folder) and run the following command using the absolute path to your Flutter batch file:

```powershell
C:\Users\joseph\.gemini\antigravity\scratch\flutter_setup\flutter\bin\flutter.bat build apk --release
```
