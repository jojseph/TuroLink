import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles runtime permission requests required for P2P Nearby Connections.
class PermissionService {
  /// Request all permissions needed for P2P (Location, Bluetooth, Nearby Wi-Fi).
  /// Returns `true` if all required permissions are granted.
  static Future<bool> requestP2PPermissions() async {
    // 1. Location permission (required for Nearby Connections)
    final locationStatus = await Permission.location.request();
    if (!locationStatus.isGranted) {
      debugPrint('[Permissions] Location permission denied');
      if (locationStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return false;
    }

    // 2. Check that location services (GPS) are enabled
    final locationServiceEnabled =
        await Permission.location.serviceStatus.isEnabled;
    if (!locationServiceEnabled) {
      debugPrint('[Permissions] Location services (GPS) not enabled');
      return false;
    }

    // 3. Bluetooth permissions (Android 12+)
    if (Platform.isAndroid) {
      final bluetoothPermissions = await [
        Permission.bluetooth,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();

      final allBluetoothGranted = bluetoothPermissions.values
          .every((s) => s.isGranted || s.isLimited);

      if (!allBluetoothGranted) {
        debugPrint('[Permissions] Some Bluetooth permissions denied');
        // Bluetooth permissions may not be strictly required on all devices,
        // so we continue but log the warning
      }

      // 4. Nearby Wi-Fi Devices (Android 13+)
      final nearbyWifiStatus = await Permission.nearbyWifiDevices.request();
      if (!nearbyWifiStatus.isGranted && !nearbyWifiStatus.isLimited) {
        debugPrint('[Permissions] Nearby Wi-Fi Devices permission denied');
        // Continue — may not be required on older Android versions
      }
    }

    debugPrint('[Permissions] All required P2P permissions granted');
    return true;
  }
}
