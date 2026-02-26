# Keep Google Nearby Connections API classes
-keep class com.google.android.gms.nearby.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# Keep the nearby_connections Flutter plugin
-keep class com.pkmnapps.nearby_connections.** { *; }

# Keep Google Play Services
-dontwarn com.google.android.gms.**
-keep class com.google.android.gms.internal.** { *; }

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Dart/Flutter generated classes
-dontwarn io.flutter.embedding.**
-keep class io.flutter.embedding.** { *; }
