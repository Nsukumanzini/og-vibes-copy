import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/academic_file_service.dart';

class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.url,
    this.title = 'Document',
  });

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = title.toLowerCase().endsWith('.pdf') ? title : '$title.pdf';
      final saved = await AcademicFileService.download(url, name);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Document saved or sent to your browser downloads.'
                : 'Download cancelled.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not download this document. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid URL')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open URL')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Download document',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _download(context),
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openInBrowser(context),
          ),
        ],
      ),
      body: SfPdfViewer.network(url, enableDoubleTapZooming: true),
    );
  }
}
