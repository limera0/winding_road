import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

class ProfileService {
  static const _key = 'user_profile_v1';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return UserProfile.empty;
    try {
      return UserProfile.fromJsonString(raw);
    } catch (_) {
      return UserProfile.empty;
    }
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, profile.toJsonString());
  }
}
