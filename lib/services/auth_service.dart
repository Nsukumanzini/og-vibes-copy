import 'package:supabase_flutter/supabase_flutter.dart';

class AuthResult {
  const AuthResult({required this.response, required this.needsVerification});

  final dynamic response;
  final bool needsVerification;
}

// Minimal wrapper used to provide a `.user` property where callers
// expect the old Supabase response object with a `user` field.
class _AuthResponseWrapper {
  _AuthResponseWrapper(this.user);
  final User? user;
}

class AuthService {
  AuthService();

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String name,
    required String surname,
    required String campus,
    required String department,
    required String level,
    required String studentType,
    required String gender,
    String? studentNumber,
    String? timeZoneName,
    String? timeZoneOffset,
    String? deviceLocale,
    String? phone,
  }) async {
    AuthResponse? response;
    try {
      response = await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password.trim(),
        data: {
          'name': name.trim(),
          'surname': surname.trim(),
          'campus': campus,
          'department': department,
          'level': level,
          'studentType': studentType,
          'gender': gender,
          if (studentNumber != null && studentNumber.isNotEmpty) 'studentNumber': studentNumber.trim(),
          if (timeZoneName != null && timeZoneName.isNotEmpty) 'timeZoneName': timeZoneName,
          if (timeZoneOffset != null && timeZoneOffset.isNotEmpty) 'timeZoneOffset': timeZoneOffset,
          if (deviceLocale != null && deviceLocale.isNotEmpty) 'deviceLocale': deviceLocale,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
    } on AssertionError catch (_) {
      throw Exception(
        'Supabase is not initialized. Provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define or ensure .env.local is included and loaded.',
      );
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(e.toString());
    }

    final user = response.user ?? response.session?.user ?? Supabase.instance.client.auth.currentUser;
    final needsVerification = user?.emailConfirmedAt == null;
    return AuthResult(response: _AuthResponseWrapper(user), needsVerification: needsVerification);
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    AuthResponse? response;
    try {
      response = await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password.trim(),
      );
    } on AssertionError catch (_) {
      throw Exception(
        'Supabase is not initialized. Provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define or ensure .env.local is included and loaded.',
      );
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(e.toString());
    }

    final user = response.user ?? response.session?.user ?? Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('Unable to sign in. Please try again.');
    }

    final needsVerification = user.emailConfirmedAt == null;
    return AuthResult(response: _AuthResponseWrapper(user), needsVerification: needsVerification);
  }

  Future<AuthResult> signInWithPhoneOtp({required String phone}) async {
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: phone);
    } on AssertionError catch (_) {
      throw Exception(
        'Supabase is not initialized. Provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define or ensure .env.local is included and loaded.',
      );
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('Unable to sign in with phone. Please try again.');
    }
    return AuthResult(response: _AuthResponseWrapper(user), needsVerification: false);
  }

  Future<AuthResult> signInAnonymously() async {
    throw UnsupportedError('Anonymous sign-in is not supported by Supabase.');
  }

  Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AssertionError catch (_) {
      // If Supabase isn't initialized, treat signOut as a no-op.
      return;
    }
  }
}

