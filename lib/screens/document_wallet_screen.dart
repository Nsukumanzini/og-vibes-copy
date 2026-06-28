// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class DocumentWalletScreen extends StatefulWidget {
  const DocumentWalletScreen({super.key});

  @override
  State<DocumentWalletScreen> createState() => _DocumentWalletScreenState();
}

class _DocumentWalletScreenState extends State<DocumentWalletScreen> {
  final List<WalletDocument> _documents = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please sign in to view your document wallet.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('student_documents')
          .select('id, title, description, file_name, file_url, file_type, uploaded_at')
          .eq('user_id', user.id)
          .order('uploaded_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(response as List<dynamic>);
      if (!mounted) return;
      setState(() {
        _documents
          ..clear()
          ..addAll(rows.map(mapDocumentRowToWalletDocument));
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load your documents right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Document Wallet')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDocumentSheet,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF2962FF), Color(0xFF6A5AE0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2962FF).withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your personal cloud drive for student documents.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Upload images or files with a name, description and download them anytime.',
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Color(0xFF2962FF)),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _loadDocuments,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _documents.isEmpty
                        ? _buildEmptyState()
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 120, top: 8),
                              itemCount: _documents.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final document = _documents[index];
                                return _DocumentCard(
                                  document: document,
                                  onView: () => _openDocumentPreview(document),
                                  onDownload: () => _downloadDocument(document),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.folder_open_rounded, size: 72, color: Color(0xFF2962FF)),
            SizedBox(height: 14),
            Text(
              'No documents yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10),
            Text(
              'Tap upload to save your proof of registration, ID, or any school document for quick access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF607D8B), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDocumentSheet() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    PlatformFile? selectedFile;
    Uint8List? previewBytes;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Upload Document',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          allowMultiple: false,
                          withData: true,
                        );
                        if (result == null || result.files.isEmpty) return;
                        final file = result.files.first;
                        setState(() {
                          selectedFile = file;
                          previewBytes = file.bytes;
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE3EAF2)),
                          color: const Color(0xFFF4F7FB),
                        ),
                        child: selectedFile == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.cloud_upload_outlined, color: Color(0xFF2962FF), size: 36),
                                  SizedBox(height: 12),
                                  Text('Tap to select an image or file'),
                                ],
                              )
                            : previewBytes != null && selectedFile!.extension != null && ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(selectedFile!.extension!.toLowerCase())
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Image.memory(previewBytes!, fit: BoxFit.cover, width: double.infinity, height: 160),
                                  )
                                : Center(
                                    child: Text(
                                      selectedFile!.name,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Document name',
                        hintText: 'My proof of registration',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'My Gert Sibande College proof of registration for 2026',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedFile == null
                            ? null
                            : () async {
                                final user = Supabase.instance.client.auth.currentUser;
                                if (user == null) {
                                  if (!mounted) return;
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please sign in to upload documents.')),
                                  );
                                  return;
                                }

                                final title = titleController.text.trim().isEmpty ? selectedFile!.name : titleController.text.trim();
                                final description = descriptionController.text.trim().isEmpty
                                    ? 'Student document saved for quick access.'
                                    : descriptionController.text.trim();
                                final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}_${selectedFile!.name}';

                                try {
                                  await Supabase.instance.client.storage.from('documents').uploadBinary(fileName, selectedFile!.bytes ?? Uint8List(0));
                                  final publicUrl = await Supabase.instance.client.storage.from('documents').createSignedUrl(fileName, 60 * 60 * 24 * 365);

                                  await Supabase.instance.client.from('student_documents').insert({
                                    'user_id': user.id,
                                    'title': title,
                                    'description': description,
                                    'file_name': selectedFile!.name,
                                    'file_url': publicUrl,
                                    'file_type': selectedFile!.extension ?? '',
                                  });

                                  if (!mounted) return;
                                  await _loadDocuments();
                                  if (!mounted) return;
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Document added to your wallet.')),
                                  );
                                } catch (error) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to upload document: $error')),
                                  );
                                }
                              },
                        child: const Text('Save Document'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  void _openDocumentPreview(WalletDocument document) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        document.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      document.fileExtension.toUpperCase(),
                      style: const TextStyle(color: Color(0xFF607D8B), fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(document.description, style: const TextStyle(color: Color(0xFF607D8B), height: 1.4)),
                const SizedBox(height: 16),
                if (document.fileBytes.isNotEmpty && ['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(document.fileExtension.toLowerCase()))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(document.fileBytes, fit: BoxFit.contain, width: double.infinity),
                  )
                else
                  Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE3EAF2)),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined, size: 48, color: Color(0xFF2962FF)),
                        const SizedBox(height: 10),
                        Text(document.fileName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _downloadDocument(document);
                        },
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadDocument(WalletDocument document) async {
    if (kIsWeb) {
      await Share.shareXFiles([
        XFile.fromData(document.fileBytes, name: document.fileName)],
        text: 'Download ${document.title}');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final target = File('${tempDir.path}/${document.fileName}');
    await target.writeAsBytes(document.fileBytes);

    await Share.shareXFiles([XFile(target.path)], text: 'Download ${document.title}');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download ready: ${target.path}')),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onView,
    required this.onDownload,
  });

  final WalletDocument document;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EAF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2962FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.description_outlined, color: Color(0xFF2962FF)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      document.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF607D8B), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WalletDocument {
  WalletDocument({
    required this.title,
    required this.description,
    required this.fileName,
    required this.fileBytes,
    required this.fileExtension,
    required this.uploadedAt,
  });

  final String title;
  final String description;
  final String fileName;
  final Uint8List fileBytes;
  final String fileExtension;
  final DateTime uploadedAt;
}

WalletDocument mapDocumentRowToWalletDocument(Map<String, dynamic> row) {
  final fileName = (row['file_name'] ?? '').toString();
  final extension = (row['file_type'] ?? '').toString();
  final uploadedAt = DateTime.tryParse((row['uploaded_at'] ?? '').toString()) ?? DateTime.now();

  return WalletDocument(
    title: (row['title'] ?? '').toString().isEmpty ? fileName : (row['title'] ?? '').toString(),
    description: (row['description'] ?? '').toString().isEmpty ? 'Saved document' : (row['description'] ?? '').toString(),
    fileName: fileName.isEmpty ? 'document' : fileName,
    fileBytes: Uint8List(0),
    fileExtension: extension.isEmpty ? (fileName.split('.').lastOrNull ?? '') : extension,
    uploadedAt: uploadedAt,
  );
}
