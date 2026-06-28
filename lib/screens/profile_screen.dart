import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

Map<String, dynamic> mapProfileRowToUiProfile(Map<String, dynamic> row) {
  final name = ((row['name'] ?? '') as String).trim();
  final surname = ((row['surname'] ?? '') as String).trim();
  final department = ((row['department'] ?? '') as String).trim();
  final campus = ((row['campus'] ?? '') as String).trim();
  final level = ((row['level'] ?? '') as String).trim();
  final photoUrl = ((row['photo_url'] ?? '') as String).trim();

  final fullNameParts = [if (name.isNotEmpty) name, if (surname.isNotEmpty) surname];

  return {
    'fullName': fullNameParts.isNotEmpty ? fullNameParts.join(' ') : 'Student',
    'name': name,
    'surname': surname,
    'department': department.isNotEmpty ? department : 'Not set',
    'campus': campus.isNotEmpty ? campus : 'Not set',
    'level': level.isNotEmpty ? level : 'Not set',
    'photoUrl': photoUrl,
    'email': (row['email'] as String?)?.trim() ?? '',
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
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
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
      };
      await _populateControllers(fallback);
      return fallback;
    }

    final response = await Supabase.instance.client
        .from('profiles')
        .select('name, surname, campus, department, level, photo_url, email')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) {
      final fallback = {
        'fullName': user.userMetadata?['full_name']?.toString() ?? user.email?.split('@').first ?? 'Student',
        'name': '',
        'surname': '',
        'department': 'Not set',
        'campus': 'Not set',
        'level': 'Not set',
        'photoUrl': '',
        'email': user.email ?? '',
      };
      await _populateControllers(fallback);
      return fallback;
    }

    final profile = mapProfileRowToUiProfile(Map<String, dynamic>.from(response));
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

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      String? photoUrl;
      if (_selectedImageBytes != null) {
        final mimeType = _selectedImageMimeType ?? 'image/jpeg';
        final fileName = '${user.id}.jpg';
        await Supabase.instance.client.storage
            .from('profile_images')
            .uploadBinary(
              fileName,
              _selectedImageBytes!,
              fileOptions: FileOptions(
                upsert: true,
                contentType: mimeType,
              ),
            );

        photoUrl = Supabase.instance.client.storage
            .from('profile_images')
            .getPublicUrl(fileName);
      }

      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'department': _departmentController.text.trim(),
        'campus': _campusController.text.trim(),
        'level': _levelController.text.trim(),
      };
      if (photoUrl != null) {
        updateData['photo_url'] = photoUrl;
      }

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        ...updateData,
      });

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

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully.')));
    } catch (error, stackTrace) {
      debugPrint('Profile save error: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to save profile. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
    final fullName = profile['fullName']?.toString() ?? 'Student';
    final email = profile['email']?.toString() ?? '';
    final photoUrl = _selectedImageBytes != null ? null : _photoUrl ?? profile['photoUrl']?.toString();

    return SafeArea(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            children: [
              _buildHeader(fullName, email, photoUrl),
              const SizedBox(height: 18),
              _buildEditableField(_nameController, 'First Name', 'Enter your first name', true),
              const SizedBox(height: 12),
              _buildEditableField(_surnameController, 'Surname', 'Enter your surname', false),
              const SizedBox(height: 12),
              _buildEditableField(_departmentController, 'Department', 'Enter your department', false),
              const SizedBox(height: 12),
              _buildEditableField(_campusController, 'Campus', 'Enter your campus', false),
              const SizedBox(height: 12),
              _buildEditableField(_levelController, 'Level', 'Enter your academic level', false),
              const SizedBox(height: 18),
              _buildAccountCard(email),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Save changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String fullName, String email, String? photoUrl) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2962FF)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickProfileImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white.withOpacity(0.14),
                  backgroundImage: _selectedImageBytes != null
                      ? MemoryImage(_selectedImageBytes!) as ImageProvider
                      : photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                  child: _selectedImageBytes == null && (photoUrl == null || photoUrl.isEmpty)
                      ? Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : 'S',
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
                        )
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, size: 20, color: Color(0xFF2962FF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            email.isNotEmpty ? email : 'No email connected yet',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 14),
          const Text(
            'Tap the image to upload a new profile picture.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(TextEditingController controller, String label, String hint, bool required) {
    return TextFormField(
      controller: controller,
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
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _buildAccountCard(String email) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F4C81)),
          ),
          const SizedBox(height: 10),
          Text(
            email.isNotEmpty ? email : 'No email connected yet.',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your profile information is pulled from your Supabase profile record.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF2962FF), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == const Color(0xFFB9E8FF) ? const Color(0xFF0F4C81) : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildShimmerState() {
    return Container(
      color: const Color(0xFFF5F7FA),
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
