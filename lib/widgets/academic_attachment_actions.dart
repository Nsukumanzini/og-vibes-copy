import 'package:flutter/material.dart';
import '../services/offline_data_adapter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/pdf_viewer_screen.dart';

/// Reads only attachment metadata; normal table and Storage RLS still apply.
class AcademicAttachmentActions extends StatefulWidget {
  const AcademicAttachmentActions({super.key, required this.table, required this.recordId});
  final String table;
  final String recordId;
  @override
  State<AcademicAttachmentActions> createState() => _AcademicAttachmentActionsState();
}

class _AcademicAttachmentActionsState extends State<AcademicAttachmentActions> {
  late Future<Map<String, dynamic>?> _file;
  bool _busy = false;
  @override
  void initState() { super.initState(); _file = _load(); }
  @override
  void didUpdateWidget(covariant AcademicAttachmentActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId || oldWidget.table != widget.table) _file = _load();
  }
  Future<Map<String, dynamic>?> _load() async {
    if (!{'quizzes', 'quiz_questions'}.contains(widget.table) || widget.recordId.isEmpty) return null;
    return OfflineData.instance.client.from(widget.table)
      .select('attachment_storage_path,attachment_file_name')
      .eq('id', widget.recordId).maybeSingle();
  }
  Future<void> _open(Map<String, dynamic> file, bool download) async {
    setState(() => _busy = true);
    try {
      final path = file['attachment_storage_path'].toString();
      final name = file['attachment_file_name']?.toString() ?? path.split('/').last;
      final url = await OfflineData.instance.client.storage.from('academic-content').createSignedUrl(path, 600);
      if (!mounted) return;
      if (!download && name.toLowerCase().endsWith('.pdf')) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PdfViewerScreen(url: url, title: name)));
      } else {
        final uri = Uri.parse(url);
        final target = download ? uri.replace(queryParameters: {...uri.queryParameters, 'download': name}) : uri;
        if (!await launchUrl(target, mode: LaunchMode.externalApplication)) throw Exception('Unable to open file');
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the attachment. Please try again.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _file,
    builder: (context, snapshot) {
      if (snapshot.hasError) return TextButton.icon(onPressed: () => setState(() => _file = _load()), icon: const Icon(Icons.refresh), label: const Text('Retry loading attachment'));
      final file = snapshot.data;
      if (file == null || (file['attachment_storage_path']?.toString() ?? '').isEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(file['attachment_file_name']?.toString() ?? 'Supporting material', style: const TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 12, children: [
          OutlinedButton.icon(onPressed: _busy ? null : () => _open(file, false), icon: const Icon(Icons.visibility_outlined), label: const Text('View file')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _open(file, true), icon: const Icon(Icons.download_outlined), label: const Text('Download')),
        ]),
      ]));
    },
  );
}
