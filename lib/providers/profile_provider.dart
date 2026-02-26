import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';
import 'package:uuid/uuid.dart';

class ProfileProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  UserProfile? _profile;

  UserProfile? get profile => _profile;
  bool get hasProfile => _profile != null;
  bool get isTeacher => _profile?.isTeacher ?? false;

  /// Load profile from local DB
  Future<void> loadProfile() async {
    _profile = await _dbService.getProfile();
    notifyListeners();
  }

  /// Save or update profile
  Future<void> saveProfile(String displayName, bool isTeacher) async {
    _profile = UserProfile(
      deviceId: _profile?.deviceId ?? const Uuid().v4(),
      displayName: displayName,
      isTeacher: isTeacher,
    );
    await _dbService.saveProfile(_profile!);
    notifyListeners();
  }

  /// Clear profile (for switching roles)
  Future<void> clearProfile() async {
    _profile = null;
    notifyListeners();
  }
}
