import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole {
  rider,
  driver,
}

class AppRoleNotifier extends StateNotifier<AppRole> {
  final SharedPreferences _prefs;
  static const String _prefKey = 'selected_app_role';

  AppRoleNotifier(this._prefs) : super(AppRole.rider) {
    _loadRole();
  }

  void _loadRole() {
    final saved = _prefs.getString(_prefKey);
    if (saved == 'driver') {
      state = AppRole.driver;
    } else {
      state = AppRole.rider;
    }
  }

  Future<void> setRole(AppRole role) async {
    state = role;
    await _prefs.setString(_prefKey, role == AppRole.driver ? 'driver' : 'rider');
  }

  Future<void> toggle() async {
    final next = state == AppRole.rider ? AppRole.driver : AppRole.rider;
    await setRole(next);
  }
}

// We use a future provider for SharedPreferences to ensure it's ready
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in the ProviderScope');
});

final appRoleProvider = StateNotifierProvider<AppRoleNotifier, AppRole>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppRoleNotifier(prefs);
});
