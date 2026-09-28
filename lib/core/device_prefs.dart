import 'package:shared_preferences/shared_preferences.dart';
import '../presentation/models/discount_preset.dart';

class DevicePrefs {
  static late SharedPreferences _prefs;

  static const String _companyIdKey = 'provisioned_company_id';
  static const String _storeIdKey = 'provisioned_store_id';
  static const String _registerIdKey = 'provisioned_register_id';
  static const String _currentEmployeeIdKey = 'current_employee_id';
  static const String _currentEmployeeRoleKey = 'current_employee_role';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Provisioning Binding ---
  static String? get companyId {
    try {
      return _prefs.getString(_companyIdKey);
    } catch (_) {
      return null;
    }
  }
  static Future<bool> setCompanyId(String? id) {
    if (id == null) return _prefs.remove(_companyIdKey);
    return _prefs.setString(_companyIdKey, id);
  }

  static String? get storeId {
    try {
      return _prefs.getString(_storeIdKey);
    } catch (_) {
      return null;
    }
  }
  static Future<bool> setStoreId(String? id) {
    if (id == null) return _prefs.remove(_storeIdKey);
    return _prefs.setString(_storeIdKey, id);
  }

  static String? get registerId => _prefs.getString(_registerIdKey);
  static Future<bool> setRegisterId(String? id) {
    if (id == null) return _prefs.remove(_registerIdKey);
    return _prefs.setString(_registerIdKey, id);
  }

  // --- Session Binding ---
  static String? get currentEmployeeId => _prefs.getString(_currentEmployeeIdKey);
  static Future<bool> setCurrentEmployeeId(String? id) {
    if (id == null) return _prefs.remove(_currentEmployeeIdKey);
    return _prefs.setString(_currentEmployeeIdKey, id);
  }

  static const String _lastSyncTimestampKey = 'last_sync_timestamp';

  static String? get currentEmployeeRole => _prefs.getString(_currentEmployeeRoleKey);
  static Future<bool> setCurrentEmployeeRole(String? role) {
    if (role == null) return _prefs.remove(_currentEmployeeRoleKey);
    return _prefs.setString(_currentEmployeeRoleKey, role);
  }

  static String? get lastSyncTimestamp => _prefs.getString(_lastSyncTimestampKey);
  static Future<bool> setLastSyncTimestamp(String? isoString) {
    if (isoString == null) return _prefs.remove(_lastSyncTimestampKey);
    return _prefs.setString(_lastSyncTimestampKey, isoString);
  }

  static bool get isProvisioned => companyId != null && storeId != null && registerId != null;

  static const String _requirePinKey = 'require_pin_for_unlock';
  static bool get requirePinForUnlock => _prefs.getBool(_requirePinKey) ?? false;
  static Future<bool> setRequirePinForUnlock(bool require) {
    return _prefs.setBool(_requirePinKey, require);
  }

  // --- Discount & Promotion Rules (Admin Configured) ---
  static const String _seniorPwdPercentKey = 'senior_pwd_discount_percent';
  static const String _maxCustomDiscountKey = 'max_custom_discount_percent';
  static const String _discountPresetsKey = 'custom_discount_presets';

  static double get seniorPwdDiscountPercent =>
      _prefs.getDouble(_seniorPwdPercentKey) ?? 20.0;

  static Future<bool> setSeniorPwdDiscountPercent(double percent) {
    return _prefs.setDouble(_seniorPwdPercentKey, percent);
  }

  static double get maxCustomDiscountPercent =>
      _prefs.getDouble(_maxCustomDiscountKey) ?? 50.0;

  static Future<bool> setMaxCustomDiscountPercent(double percent) {
    return _prefs.setDouble(_maxCustomDiscountKey, percent);
  }

  static List<DiscountPreset> get discountPresets {
    final raw = _prefs.getString(_discountPresetsKey);
    if (raw != null && raw.isNotEmpty) {
      final list = DiscountPreset.decodeList(raw);
      if (list.isNotEmpty) return list;
    }
    // Standard default presets
    return [
      DiscountPreset(
        id: 'senior_pwd',
        label: 'Senior Citizen / PWD',
        percent: seniorPwdDiscountPercent,
        isSystem: true,
      ),
      const DiscountPreset(
        id: 'employee_10',
        label: 'Employee Discount',
        percent: 10.0,
      ),
      const DiscountPreset(
        id: 'vip_5',
        label: 'VIP Member',
        percent: 5.0,
      ),
    ];
  }

  static Future<bool> setDiscountPresets(List<DiscountPreset> presets) {
    return _prefs.setString(_discountPresetsKey, DiscountPreset.encodeList(presets));
  }

  static Future<void> clearProvisioning() async {
    await setCompanyId(null);
    await setStoreId(null);
    await setRegisterId(null);
    await setCurrentEmployeeId(null);
    await setCurrentEmployeeRole(null);
    await _prefs.remove(_requirePinKey);
  }
}

