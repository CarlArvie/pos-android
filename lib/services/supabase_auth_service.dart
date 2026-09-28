import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/supabase_constants.dart';

class SupabaseAuthService {
  /// Creates a new user in Supabase Auth via REST API without altering the current session.
  /// Returns the newly created user's UUID (profile_id).
  static Future<String> signUpUserBackend(String email, String password) async {
    final url = Uri.parse('${SupabaseConstants.projectUrl}/auth/v1/signup');

    final response = await http.post(
      url,
      headers: {
        'apikey': SupabaseConstants.anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      
      // If email confirmations are enabled, the 'user' object might be null or unverified.
      // Assuming auto-confirm is on, or we can get the ID anyway.
      if (data['user'] != null && data['user']['id'] != null) {
        return data['user']['id'];
      } else if (data['id'] != null) {
        return data['id']; // Sometimes it returns the user directly at the root
      }
      throw Exception('Failed to retrieve user ID from response: ${response.body}');
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['msg'] ?? 'Failed to create auth user');
    }
  }

  /// Verifies a user's password via REST API without altering the local Flutter auth session.
  static Future<bool> verifyPasswordBackend(String email, String password) async {
    try {
      final url = Uri.parse('${SupabaseConstants.projectUrl}/auth/v1/token?grant_type=password');
      final response = await http.post(
        url,
        headers: {
          'apikey': SupabaseConstants.anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
