import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_persistence_service.dart';
import 'feature_flag_service.dart';
import 'push_notification_service.dart';

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
    String? nickname,
    String? studentNumber,
    String? timeZoneName,
    String? timeZoneOffset,
    String? deviceLocale,
    String? phone,
  }) async {
    final registration = await FeatureFlagService.availability(
      'registrations',
      forceRefresh: true,
    );
    if (!registration.enabled) throw Exception(registration.message);

    AuthResponse? response;
    try {
      response = await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password.trim(),
        data: {
          'name': name.trim(),
          'surname': surname.trim(),
          if (nickname != null && nickname.isNotEmpty)
            'nickname': nickname.trim(),
          'campus': campus,
          'department': department,
          'course': department,
          'level': level,
          'student_type': studentType,
          // Keep the legacy camelCase value while deployed database triggers
          // are upgraded to the canonical snake_case contract.
          'studentType': studentType,
          'gender': gender,
          if (studentNumber != null && studentNumber.isNotEmpty)
            'student_number': studentNumber.trim(),
          if (timeZoneName != null && timeZoneName.isNotEmpty)
            'timezone_name': timeZoneName,
          if (timeZoneOffset != null && timeZoneOffset.isNotEmpty)
            'timezone_offset': timeZoneOffset,
          if (deviceLocale != null && deviceLocale.isNotEmpty)
            'device_locale': deviceLocale,
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

    final user =
        response.user ??
        response.session?.user ??
        Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          'email': email.trim(),
          'name': name.trim(),
          'surname': surname.trim(),
          if (nickname != null && nickname.isNotEmpty)
            'nickname': nickname.trim(),
          'campus': campus,
          'department': department,
          'course': department,
          'level': level,
          'student_type': studentType,
          'gender': gender,
          if (studentNumber != null && studentNumber.isNotEmpty)
            'student_number': studentNumber.trim(),
          if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
        }, onConflict: 'id');
      } catch (error) {
        // Email-confirmation signups do not have an authenticated session yet,
        // so the database trigger remains the authoritative profile writer.
        debugPrint('Deferred signup profile sync: $error');
      }
    }

    final needsVerification = user?.emailConfirmedAt == null;
    if (!needsVerification && response.session != null && user != null) {
      await _synchroniseProfileFromMetadata(user);
      await AuthPersistenceService.rememberSignedInUser();
    }
    return AuthResult(
      response: _AuthResponseWrapper(user),
      needsVerification: needsVerification,
    );
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

    final user =
        response.user ??
        response.session?.user ??
        Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('Unable to sign in. Please try again.');
    }

    final needsVerification = user.emailConfirmedAt == null;
    if (!needsVerification) {
      await _synchroniseProfileFromMetadata(user);
      await AuthPersistenceService.rememberSignedInUser();
    }
    return AuthResult(
      response: _AuthResponseWrapper(user),
      needsVerification: needsVerification,
    );
  }

  Future<void> _synchroniseProfileFromMetadata(User user) async {
    try {
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final profile = await Supabase.instance.client
          .from('profiles')
          .select(
            'name,surname,nickname,campus,department,course,level,'
            'student_type,gender,student_number',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) return;

      String text(dynamic value) => value?.toString().trim() ?? '';
      dynamic metadataValue(String snakeCase, [String? camelCase]) {
        final primary = metadata[snakeCase];
        if (text(primary).isNotEmpty) return primary;
        return camelCase == null ? null : metadata[camelCase];
      }

      final department = metadataValue('department', 'course');
      final course = metadataValue('course', 'department');
      final candidates = <String, dynamic>{
        'name': metadataValue('name'),
        'surname': metadataValue('surname'),
        'nickname': metadataValue('nickname'),
        'campus': metadataValue('campus'),
        'department': department,
        'course': course,
        'level': metadataValue('level'),
        'student_type': metadataValue('student_type', 'studentType'),
        'gender': metadataValue('gender'),
        'student_number': metadataValue('student_number', 'studentNumber'),
      };
      final patch = <String, dynamic>{};
      for (final entry in candidates.entries) {
        final current = text(profile[entry.key]);
        final replacement = text(entry.value);
        if ((current.isEmpty || current == 'Not selected') &&
            replacement.isNotEmpty) {
          patch[entry.key] = replacement;
        }
      }
      if (patch.isNotEmpty) {
        await Supabase.instance.client
            .from('profiles')
            .update(patch)
            .eq('id', user.id);
      }
    } catch (error) {
      debugPrint('Profile metadata sync failed: $error');
    }
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
    return AuthResult(
      response: _AuthResponseWrapper(user),
      needsVerification: false,
    );
  }

  Future<AuthResult> signInAnonymously() async {
    throw UnsupportedError('Anonymous sign-in is not supported by Supabase.');
  }

  Future<void> signOut() async {
    await AuthPersistenceService.clear();
    try {
      await PushNotificationService.unregisterCurrentDevice();
      await Supabase.instance.client.auth.signOut();
    } on AssertionError catch (_) {
      // If Supabase isn't initialized, treat signOut as a no-op.
      return;
    }
  }

  static String emailConfirmationRedirect() {
    if (kIsWeb) {
      return Uri.base
          .replace(
            path: '/',
            queryParameters: const {'emailConfirmed': '1'},
            fragment: '',
          )
          .toString();
    }
    return 'https://student.ogvibes.co.za/?emailConfirmed=1';
  }

  static String passwordRecoveryRedirect() {
    if (kIsWeb) {
      return Uri.base
          .replace(
            path: '/',
            queryParameters: const {'passwordRecovery': '1'},
            fragment: '',
          )
          .toString();
    }
    return 'https://student.ogvibes.co.za/?passwordRecovery=1';
  }
}
