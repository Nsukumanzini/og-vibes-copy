import 'dart:async';

import 'package:flutter/material.dart';
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
  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return {
        'fullName': 'Student',
        'department': 'Not set',
        'campus': 'Not set',
        'level': 'Not set',
        'photoUrl': '',
        'email': '',
      };
    }

    final response = await Supabase.instance.client
        .from('profiles')
        .select('name, surname, campus, department, level, photo_url')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) {
      return {
        'fullName': user.userMetadata?['full_name']?.toString() ?? user.email?.split('@').first ?? 'Student',
        'department': 'Not set',
        'campus': 'Not set',
        'level': 'Not set',
        'photoUrl': '',
        'email': user.email ?? '',
      };
    }

    return mapProfileRowToUiProfile(Map<String, dynamic>.from(response));
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
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
    final department = profile['department']?.toString() ?? 'Not set';
    final campus = profile['campus']?.toString() ?? 'Not set';
    final level = profile['level']?.toString() ?? 'Not set';
    final email = profile['email']?.toString() ?? '';
    final photoUrl = profile['photoUrl']?.toString() ?? '';

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          final future = _loadProfile();
          setState(() {
            _profileFuture = future;
          });
          await future;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            _buildHeader(fullName, department, campus, level, email, photoUrl),
            const SizedBox(height: 16),
            _buildInfoCard(department, campus, level),
            const SizedBox(height: 16),
            _buildAccountCard(email),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    String fullName,
    String department,
    String campus,
    String level,
    String email,
    String photoUrl,
  ) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.white.withOpacity(0.16),
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? Text(
                        fullName.isNotEmpty ? fullName[0].toUpperCase() : 'S',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      department,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      campus,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(level, const Color(0xFFB9E8FF)),
              if (email.isNotEmpty) _pill(email, Colors.white.withOpacity(0.16)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String department, String campus, String level) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F4C81)),
          ),
          const SizedBox(height: 12),
          _detailRow(Icons.school_outlined, 'Department', department),
          const SizedBox(height: 10),
          _detailRow(Icons.location_on_outlined, 'Campus', campus),
          const SizedBox(height: 10),
          _detailRow(Icons.auto_awesome_outlined, 'Level', level),
        ],
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
