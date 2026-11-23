import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import '../services/offline_data_adapter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

import 'my_posts_screen.dart';
import '../services/offline_cache_service.dart';
import '../services/diagnostics_service.dart';
import '../utils/theme_constants.dart';

Map<String, dynamic> mapProfileRowToUiProfile(Map<String, dynamic> row) {
  final name = ((row['name'] ?? '') as String).trim();
  final surname = ((row['surname'] ?? '') as String).trim();
  final department = ((row['department'] ?? '') as String).trim();
  final campus = ((row['campus'] ?? '') as String).trim();
  final level = ((row['level'] ?? '') as String).trim();
  final photoUrl = ((row['photo_url'] ?? '') as String).trim();
  final nickname = ((row['nickname'] ?? '') as String).trim();

  return {
    'fullName': nickname.isNotEmpty ? nickname : 'OG Vibester',
    'name': name,
    'surname': surname,
    'department': department.isNotEmpty ? department : 'Not set',
    'campus': campus.isNotEmpty ? campus : 'Not set',
    'level': level.isNotEmpty ? level : 'Not set',
    'photoUrl': photoUrl,
    'email': (row['email'] as String?)?.trim() ?? '',
    'nickname': nickname,
    'studentNumber': (row['student_number'] as String?)?.trim() ?? '',
    'phone': (row['phone'] as String?)?.trim() ?? '',
    'studentType': (row['student_type'] as String?)?.trim() ?? 'Student',
    'gender': (row['gender'] as String?)?.trim() ?? 'Not set',
    'role': (row['role'] as String?)?.trim() ?? 'student',
    'verified': row['is_verified'] == true,
    'createdAt': row['created_at']?.toString(),
  };
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _campusController = TextEditingController();
  final _levelController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _studentNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  late Future<Map<String, dynamic>> _profileFuture;
  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;
  String? _photoUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _departmentController.dispose();
    _campusController.dispose();
    _levelController.dispose();
    _nicknameController.dispose();
    _studentNumberController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _populateControllers(Map<String, dynamic> profile) async {
    _nameController.text = profile['name']?.toString() ?? '';
    _surnameController.text = profile['surname']?.toString() ?? '';
    _departmentController.text = profile['department']?.toString() == 'Not set'
        ? ''
        : profile['department']?.toString() ?? '';
    _campusController.text = profile['campus']?.toString() == 'Not set'
        ? ''
        : profile['campus']?.toString() ?? '';
    _levelController.text = profile['level']?.toString() == 'Not set'
        ? ''
        : profile['level']?.toString() ?? '';
    _photoUrl = profile['photoUrl']?.toString();
    _nicknameController.text = profile['nickname']?.toString() ?? '';
    _studentNumberController.text = profile['studentNumber']?.toString() ?? '';
    _phoneController.text = profile['phone']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) {
      final fallback = {
        'fullName': 'Student',
        'name': '',
        'surname': '',
        'department': 'Not set',
        'campus': 'Not set',
        'level': 'Not set',
        'photoUrl': '',
        'email': '',
        'nickname': '',
        'studentNumber': '',
        'phone': '',
        'studentType': 'Student',
        'gender': 'Not set',
        'role': 'student',
        'verified': false,
        'createdAt': null,
      };
      await _populateControllers(fallback);
      return fallback;
    }

    Map<String, dynamic>? response;
    try {
      response = await OfflineData.instance.client
          .from('profiles')
          .select(
            'name, surname, nickname, campus, department, level, photo_url, '
            'email, student_number, phone, student_type, gender, role, '
            'is_verified, created_at',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (response != null) {
        unawaited(
          OfflineCacheService.writeList('own_profile', <Map<String, dynamic>>[
            response,
          ], maxRecords: 1),
        );
      }
    } catch (_) {
      final cached = await OfflineCacheService.readList('own_profile');
      response = cached.isEmpty ? null : cached.first;
    }

    if (response == null) {
      final fallback = {
        'fullName':
            user.userMetadata?['full_name']?.toString() ??
            user.email?.split('@').first ??
            'Student',
        'name': '',
        'surname': '',
        'department': 'Not set',
        'campus': 'Not set',
        'level': 'Not set',
        'photoUrl': '',
        'email': user.email ?? '',
        'nickname': user.userMetadata?['nickname']?.toString() ?? '',
        'studentNumber': user.userMetadata?['student_number']?.toString() ?? '',
        'phone': user.phone ?? '',
        'studentType': 'Student',
        'gender': 'Not set',
        'role': 'student',
        'verified': user.emailConfirmedAt != null,
        'createdAt': user.createdAt,
      };
      await _populateControllers(fallback);
      return fallback;
    }

    final profile = mapProfileRowToUiProfile(
      Map<String, dynamic>.from(response),
    );
    await _populateControllers(profile);
    return profile;
  }

  Future<void> _pickProfileImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageMimeType = picked.mimeType ?? 'image/jpeg';
      });
    } catch (_) {
      // ignore image picker errors
    }
  }

  Future<void> _saveProfile() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      String? photoUrl;
      if (_selectedImageBytes != null) {
        final mimeType = _selectedImageMimeType ?? 'image/jpeg';
        final extension = mimeType.contains('png') ? 'png' : 'jpg';
        final fileName =
            '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
        await OfflineData.instance.client.storage
            .from('profile_images')
            .uploadBinary(
              fileName,
              _selectedImageBytes!,
              fileOptions: OfflineFileOptions(
                upsert: true,
                contentType: mimeType,
              ),
            );

        photoUrl = OfflineData.instance.client.storage
            .from('profile_images')
            .getPublicUrl(fileName);
      }

      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'department': _departmentController.text.trim(),
        'campus': _campusController.text.trim(),
        'level': _levelController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'student_number': _studentNumberController.text.trim(),
        'phone': _phoneController.text.trim(),
      };
      if (photoUrl != null) {
        updateData['photo_url'] = photoUrl;
      }

      final updated = await OfflineData.instance.client
          .from('profiles')
          .update(updateData)
          .eq('id', user.id)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        await OfflineData.instance.client.from('profiles').insert({
          'id': user.id,
          'email': user.email ?? '',
          ...updateData,
          'student_type': 'Student',
          'gender': 'Not set',
        });
      }
      await OfflineData.instance.client.auth.updateUser(
        OfflineUserAttributes(
          data: {
            ...?user.userMetadata,
            'nickname': _nicknameController.text.trim(),
            if (photoUrl != null) 'avatar_url': photoUrl,
          },
        ),
      );

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        if (photoUrl != null) {
          _photoUrl = photoUrl;
          _selectedImageBytes = null;
          _selectedImageMimeType = null;
        }
        _profileFuture = _loadProfile();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (error, stackTrace) {
      unawaited(
        DiagnosticsService.record(
          'upload_failed_profile',
          metadata: {'error_type': error.runtimeType.toString()},
        ),
      );
      debugPrint('Profile save error: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save profile. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        leading: Navigator.canPop(context) ? const BackButton() : null,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildShimmerState();
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  const Text('We could not load your profile right now.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _profileFuture = _loadProfile();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return _buildProfile(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildProfile(Map<String, dynamic> profile) {
    final fullName = profile['nickname']?.toString().trim().isNotEmpty == true
        ? profile['nickname'].toString().trim()
        : 'OG Vibester';
    final email = profile['email']?.toString() ?? '';
    final photoUrl = _selectedImageBytes != null
        ? null
        : _photoUrl ?? profile['photoUrl']?.toString();
    final verified =
        profile['verified'] == true ||
        OfflineData.instance.client.auth.currentUser?.emailConfirmedAt != null;

    return SafeArea(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
            children: [
              _buildHeader(fullName, email, photoUrl, verified),
              const SizedBox(height: 16),
              _buildPostsShortcut(),
              const SizedBox(height: 24),
              _sectionCard(
                title: 'About you',
                subtitle: 'The details students see on your profile',
                icon: Icons.person_outline_rounded,
                index: '01',
                children: [
                  _buildEditableField(
                    _nameController,
                    'First name',
                    'Enter your first name',
                    true,
                  ),
                  _buildEditableField(
                    _surnameController,
                    'Surname',
                    'Enter your surname',
                    false,
                  ),
                  _buildEditableField(
                    _nicknameController,
                    'Nickname',
                    'Your public OG Vibes name',
                    true,
                  ),
                  _buildEditableField(
                    _phoneController,
                    'Phone number',
                    'Optional contact number',
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Academic profile',
                subtitle: 'Your campus and study details',
                icon: Icons.school_outlined,
                index: '02',
                children: [
                  _buildEditableField(
                    _studentNumberController,
                    'Student number',
                    'Your college student number',
                    false,
                  ),
                  _buildEditableField(
                    _departmentController,
                    'Course or department',
                    'Your programme',
                    false,
                  ),
                  _buildEditableField(
                    _campusController,
                    'Campus',
                    'Your campus',
                    false,
                  ),
                  _buildEditableField(
                    _levelController,
                    'Academic level',
                    'Your current level',
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildAccountCard(email, profile, verified),
              const SizedBox(height: 24),
              SizedBox(
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: AppColors.deepBlue.withValues(alpha: .22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _isSaving ? 'Saving profile…' : 'Save changes',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your profile details stay up to date across OG Vibes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostsShortcut() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const MyPostsScreen())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.outline.withValues(alpha: .8)),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlue.withValues(alpha: .035),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.dynamic_feed_rounded,
                  color: AppColors.primaryAction,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My posts',
                      style: TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage posts and replies',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: AppColors.deepBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    String fullName,
    String email,
    String? photoUrl,
    bool verified,
  ) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.midnightInk,
            AppColors.deepBlue,
            AppColors.vibeBlue,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -62,
            right: -40,
            child: Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .08),
                  width: 26,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 19, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'YOUR PROFILE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    _pill(
                      verified ? 'Verified' : 'Pending',
                      verified ? AppColors.successLight : AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _pickProfileImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.ogGold,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 39,
                              backgroundColor: Colors.white.withValues(
                                alpha: .15,
                              ),
                              backgroundImage: _selectedImageBytes != null
                                  ? MemoryImage(_selectedImageBytes!)
                                  : photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child:
                                  _selectedImageBytes == null &&
                                      (photoUrl == null || photoUrl.isEmpty)
                                  ? const Icon(
                                      Icons.person_rounded,
                                      color: Colors.white,
                                      size: 38,
                                    )
                                  : null,
                            ),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.ogGold,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: AppColors.midnightInk,
                              size: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            email.isNotEmpty ? email : 'No email connected yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 11),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .16),
                              ),
                            ),
                            child: const Text(
                              'OG VIBES STUDENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.ogGold,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Tap your photo to update it',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
    TextEditingController controller,
    String label,
    String hint,
    bool required,
  ) {
    final prefixIcon = switch (label) {
      'First name' => Icons.person_outline_rounded,
      'Surname' => Icons.badge_outlined,
      'Nickname' => Icons.alternate_email_rounded,
      'Phone number' => Icons.phone_outlined,
      'Student number' => Icons.numbers_rounded,
      'Course or department' => Icons.menu_book_outlined,
      'Campus' => Icons.location_on_outlined,
      'Academic level' => Icons.stairs_rounded,
      _ => Icons.edit_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: TextFormField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        keyboardType: label == 'Phone number'
            ? TextInputType.phone
            : TextInputType.text,
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'This field is required.';
                }
                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(prefixIcon, size: 20),
          filled: true,
          fillColor: AppColors.surfaceSoft,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE7EDF7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primaryAction,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.dangerLight),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.dangerLight,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String index,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline.withValues(alpha: .78)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBlue,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppColors.primaryAction, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                index,
                style: const TextStyle(
                  color: AppColors.ogGold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    String email,
    Map<String, dynamic> profile,
    bool verified,
  ) {
    final createdAt = DateTime.tryParse(profile['createdAt']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline.withValues(alpha: .78)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.warningText,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account',
                      style: TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Sign-in and membership details',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: Color(0xFFE9EEF7)),
          const SizedBox(height: 14),
          _detailRow(
            Icons.alternate_email_rounded,
            'Email',
            email.isNotEmpty ? email : 'Not connected',
          ),
          const SizedBox(height: 14),
          _detailRow(
            Icons.verified_user_outlined,
            'Account status',
            verified ? 'Verified' : 'Pending verification',
          ),
          const SizedBox(height: 14),
          _detailRow(
            Icons.groups_2_outlined,
            'Student type',
            profile['studentType']?.toString() ?? 'Student',
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 14),
            _detailRow(
              Icons.calendar_month_outlined,
              'Member since',
              '${createdAt.year}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.primaryAction, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.midnightInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, Color color) {
    final foreground = color == AppColors.successLight
        ? const Color(0xFF0C6241)
        : AppColors.warningText;
    final background = color == AppColors.successLight
        ? AppColors.successSurface
        : AppColors.warningSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildShimmerState() {
    return Container(
      color: const Color(0xFFF7F9FD),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade100,
          child: Column(
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
