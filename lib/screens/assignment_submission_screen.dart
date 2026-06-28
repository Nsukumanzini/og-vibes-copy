// ignore_for_file: unused_field

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AssignmentSubmissionScreen extends StatefulWidget {
  const AssignmentSubmissionScreen({super.key});

  @override
  State<AssignmentSubmissionScreen> createState() =>
      _AssignmentSubmissionScreenState();
}

class _AssignmentSubmissionScreenState
    extends State<AssignmentSubmissionScreen> {
  static const _levelOptions = ['Level 2', 'Level 3', 'Level 4'];
  String _selectedLevel = _levelOptions.first;
  bool _isLoading = true;
  String? _errorMessage;
  final List<_SubmissionItem> _submissions = [];

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be signed in to view submissions.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final raw = await Supabase.instance.client
          .from('assignment_submissions')
          .select(
            'id, user_id, level, title, subject, due_date, status, storage_path, document_url, submitted_at, grade, feedback, created_at',
          )
          .eq('user_id', user.id)
          .order('submitted_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(raw as List<dynamic>? ?? []);
      final loaded = rows.map(_SubmissionItem.fromRow).toList();

      if (!mounted) return;
      setState(() {
        _submissions
          ..clear()
          ..addAll(loaded);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _refreshSubmissions() async {
    await _loadSubmissions();
  }

  List<_SubmissionItem> get _pendingSubmissions {
    return _filteredByLevel.where((item) => item.status == 'pending').toList();
  }

  List<_SubmissionItem> get _submittedSubmissions {
    return _filteredByLevel.where((item) => item.status == 'submitted').toList();
  }

  List<_SubmissionItem> get _gradedSubmissions {
    return _filteredByLevel.where((item) => item.status == 'graded').toList();
  }

  List<_SubmissionItem> get _filteredByLevel {
    return _submissions.where((item) => item.level == _selectedLevel).toList();
  }

  Future<void> _showUploadDialog() async {
    final titleController = TextEditingController();
    final subjectController = TextEditingController();
    final dueDateController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Upload assessment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Assignment title'),
              ),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              TextField(
                controller: dueDateController,
                decoration: const InputDecoration(labelText: 'Due date (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty ||
                    subjectController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (result != true) {
      return;
    }

    await _pickAndUpload(
      title: titleController.text.trim(),
      subject: subjectController.text.trim(),
      dueDate: dueDateController.text.trim().isEmpty
          ? null
          : dueDateController.text.trim(),
    );
  }

  Future<void> _pickAndUpload({
    required String title,
    required String subject,
    String? dueDate,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first.')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    if (file.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read selected file.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final fileName =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await Supabase.instance.client.storage
          .from('assignment_submissions')
          .uploadBinary(fileName, file.bytes!);

      final signedUrl = await Supabase.instance.client.storage
          .from('assignment_submissions')
          .createSignedUrl(fileName, 60 * 60 * 24 * 365);

      await Supabase.instance.client.from('assignment_submissions').insert({
        'user_id': user.id,
        'level': _selectedLevel,
        'title': title,
        'subject': subject,
        'due_date': dueDate,
        'status': 'submitted',
        'storage_path': fileName,
        'document_url': signedUrl,
        'submitted_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      await _loadSubmissions();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2E7D32),
          content: Text('✅ Submission uploaded successfully.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: VibeScaffold(
        appBar: AppBar(
          title: Text('Assignment & PoE Submission — $_selectedLevel'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refreshSubmissions,
            ),
          ],
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(text: 'Pending'),
              Tab(text: 'Submitted'),
              Tab(text: 'Graded'),
            ],
          ),
        ),
        body: _isLoading
            ? _buildLoadingState()
            : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_errorMessage != null && _submissions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text('Could not load submissions.'),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Try again later.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshSubmissions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _levelOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final level = _levelOptions[index];
                final selected = level == _selectedLevel;
                return ChoiceChip(
                  label: Text(level),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedLevel = level;
                    });
                  },
                  selectedColor: Colors.white,
                  backgroundColor: Colors.white10,
                  labelStyle: TextStyle(
                    color: selected ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            children: <Widget>[
              _buildPendingTab(),
              _buildSubmittedTab(),
              _buildGradedTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingTab() {
    final items = _pendingSubmissions;
    if (items.isEmpty) {
      return _buildEmptyState(
        title: 'No pending submissions yet.',
        actionLabel: 'Upload assignment',
        action: _showUploadDialog,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _SubmissionCard(
          icon: Icons.assignment_late,
          title: item.title,
          subtitleLabel: 'Subject',
          subtitleValue: item.subject,
          statusText: 'Due ${item.dueDate ?? 'TBA'}',
          statusColor: const Color(0xFFC62828),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showUploadDialog,
              icon: const Icon(Icons.file_upload),
              label: const Text('Upload Submission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubmittedTab() {
    final items = _submittedSubmissions;
    if (items.isEmpty) {
      return _buildEmptyState(
        title: 'No submitted assignments yet.',
        actionLabel: 'Upload assignment',
        action: _showUploadDialog,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _SubmissionCard(
          icon: Icons.assignment_turned_in,
          title: item.title,
          subtitleLabel: 'Submitted',
          subtitleValue: item.submittedAtFormatted,
          statusText: 'Awaiting grading',
          statusColor: const Color(0xFFFF8F00),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: item.documentUrl != null
                  ? () => _openDocument(item.documentUrl!)
                  : null,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('View Uploaded File'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF1565C0)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradedTab() {
    final items = _gradedSubmissions;
    if (items.isEmpty) {
      return _buildEmptyState(
        title: 'No graded submissions yet.',
        actionLabel: 'Upload assignment',
        action: _showUploadDialog,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _SubmissionCard(
          icon: Icons.assignment,
          title: item.title,
          subtitleLabel: 'Subject',
          subtitleValue: item.subject,
          statusText: item.grade ?? 'Graded',
          statusColor: const Color(0xFF2E7D32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (item.feedback != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDDE4EE)),
                  ),
                  child: Text(
                    'Lecturer Feedback: ${item.feedback}',
                    style: const TextStyle(
                      color: Color(0xFF37474F),
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: item.documentUrl != null
                    ? () => _openDocument(item.documentUrl!)
                    : null,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('View Uploaded File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String actionLabel,
    required VoidCallback action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined, size: 56, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: action,
              icon: const Icon(Icons.file_upload),
              label: Text(actionLabel),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid document URL.')),
      );
      return;
    }

    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open document.')),
      );
    }
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: <Widget>[
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.icon,
    required this.title,
    required this.subtitleLabel,
    required this.subtitleValue,
    required this.statusText,
    required this.statusColor,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitleLabel;
  final String subtitleValue;
  final String statusText;
  final Color statusColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF1)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF1565C0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF102027),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$subtitleLabel: $subtitleValue',
                      style: const TextStyle(
                        color: Color(0xFF546E7A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SubmissionItem {
  const _SubmissionItem({
    required this.id,
    required this.userId,
    required this.level,
    required this.title,
    required this.subject,
    this.dueDate,
    required this.status,
    this.storagePath,
    this.documentUrl,
    this.submittedAt,
    this.grade,
    this.feedback,
  });

  final String id;
  final String userId;
  final String level;
  final String title;
  final String subject;
  final String? dueDate;
  final String status;
  final String? storagePath;
  final String? documentUrl;
  final DateTime? submittedAt;
  final String? grade;
  final String? feedback;

  String get submittedAtFormatted {
    if (submittedAt == null) return 'Unknown';
    return '${submittedAt!.day.toString().padLeft(2, '0')}/${submittedAt!.month.toString().padLeft(2, '0')} ${submittedAt!.hour.toString().padLeft(2, '0')}:${submittedAt!.minute.toString().padLeft(2, '0')}';
  }

  factory _SubmissionItem.fromRow(Map<String, dynamic> row) {
    final submittedAtValue = row['submitted_at'];
    DateTime? submittedAt;
    if (submittedAtValue is String) {
      submittedAt = DateTime.tryParse(submittedAtValue);
    } else if (submittedAtValue is DateTime) {
      submittedAt = submittedAtValue;
    }

    return _SubmissionItem(
      id: (row['id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      level: (row['level'] ?? '').toString(),
      title: (row['title'] ?? 'Untitled Assignment').toString(),
      subject: (row['subject'] ?? 'Unknown Subject').toString(),
      dueDate: row['due_date']?.toString(),
      status: (row['status'] ?? 'pending').toString(),
      storagePath: row['storage_path']?.toString(),
      documentUrl: row['document_url']?.toString(),
      submittedAt: submittedAt,
      grade: row['grade']?.toString(),
      feedback: row['feedback']?.toString(),
