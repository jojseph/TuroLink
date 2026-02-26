import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SharingService {
  /// Shares a file. To ensure compatibility with Android's FileProvider,
  /// this copies the file to the app's cache directory before sharing.
  static Future<void> shareFile(String sourceFilePath, {String? text}) async {
    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        debugPrint('File does not exist: $sourceFilePath');
        return;
      }

      // 1. Get cache directory
      final cacheDir = await getTemporaryDirectory();
      
      // 2. Create the destination path in cache
      final fileName = sourceFile.uri.pathSegments.last;
      final cachedFilePath = '${cacheDir.path}/$fileName';
      
      // 3. Copy file to cache
      final cachedFile = await sourceFile.copy(cachedFilePath);

      // 4. Share using share_plus
      final xFile = XFile(cachedFile.path);
      await Share.shareXFiles([xFile], text: text);

    } catch (e) {
      debugPrint('Error sharing file: $e');
    }
  }

  /// Convenience method to pick a file then share it immediately.
  static Future<void> pickAndShareFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        await shareFile(result.files.single.path!);
      }
    } catch (e) {
      debugPrint('Error picking file to share: $e');
    }
  }
}
