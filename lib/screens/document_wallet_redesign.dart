import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class DocumentWalletScreen extends StatefulWidget {
  const DocumentWalletScreen({super.key});

  @override
  State<DocumentWalletScreen> createState() => _DocumentWalletScreenState();
}

class _DocumentWalletScreenState extends State<DocumentWalletScreen> {
  static const capacity = 500 * 1024 * 1024;
  static const maxFileSize = 50 * 1024 * 1024;
  static const folders = <String>[
    'Personal',
    'Academic',
    'Certificates',
    'Applications',
    'Finance',
  ];

  final documents = <WalletDocument>[];
  final uploads = <UploadTask>[];
  final selected = <String>{};
  bool loading = true;
  bool refreshing = false;
  bool grid = true;
  bool dragging = false;
  String? error;

  SupabaseClient get db => Supabase.instance.client;
  User? get user => db.auth.currentUser;
  bool get selecting => selected.isNotEmpty;
  int get used =>
      documents.fold(0, (total, document) => total + document.fileSize);
  List<WalletDocument> get selectedDocuments =>
      documents.where((document) => selected.contains(document.id)).toList();

  @override
  void initState() {
    super.initState();
    unawaited(loadDocuments());
  }

  Future<void> loadDocuments({bool showLoader = true}) async {
    final currentUser = user;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Sign in to access your private Document Wallet.';
      });
      return;
    }
    if (mounted) {
      setState(() {
        if (showLoader) loading = true;
        if (!showLoader) refreshing = true;
        error = null;
      });
    }
    try {
      final data = await db
          .from('student_documents')
          .select(
            'id, title, description, file_name, file_url, file_type, '
            'storage_path, file_size, mime_type, folder, uploaded_at',
          )
          .eq('user_id', currentUser.id)
          .order('uploaded_at', ascending: false);
      if (!mounted) return;
      setState(() {
        documents
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(
              data as List<dynamic>,
            ).map(WalletDocument.fromRow),
          );
        selected.removeWhere(
          (id) => !documents.any((document) => document.id == id),
        );
        loading = false;
        refreshing = false;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
        error = friendlyError(caught);
      });
    }
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final files = <PendingFile>[];
    for (final file in result.files) {
      final bytes =
          file.bytes ??
          (!kIsWeb && file.path != null
              ? await File(file.path!).readAsBytes()
              : Uint8List(0));
      files.add(
        PendingFile(
          name: file.name,
          bytes: bytes,
          mimeType: mimeFor(file.name),
        ),
      );
    }
    await queueFiles(files);
  }

  Future<void> acceptDrop(DropDoneDetails details) async {
    final files = <PendingFile>[];
    for (final file in details.files) {
      files.add(
        PendingFile(
          name: file.name,
          bytes: await file.readAsBytes(),
          mimeType: file.mimeType ?? mimeFor(file.name),
        ),
      );
    }
    await queueFiles(files);
  }

  Future<void> queueFiles(List<PendingFile> files) async {
    var rejected = 0;
    final accepted = <UploadTask>[];
    for (final file in files) {
      if (file.bytes.isEmpty || file.bytes.length > maxFileSize) {
        rejected++;
      } else {
        accepted.add(UploadTask(file));
      }
    }
    if (accepted.isNotEmpty && mounted) {
      setState(() => uploads.addAll(accepted));
      HapticFeedback.mediumImpact();
    }
    if (rejected > 0) {
      message(
        '$rejected file${rejected == 1 ? '' : 's'} skipped. The limit is 50 MB per file.',
        isError: true,
      );
    }
    for (final task in accepted) {
      await uploadTask(task);
    }
  }

  Future<void> uploadTask(UploadTask task) async {
    final currentUser = user;
    if (currentUser == null || task.uploading) return;
    setState(() {
      task
        ..uploading = true
        ..failed = false
        ..error = null
        ..progress = .08;
    });
    String? path;
    try {
      path =
          '${currentUser.id}/${DateTime.now().microsecondsSinceEpoch}_${safeName(task.file.name)}';
      setState(() => task.progress = .25);
      await db.storage
          .from('documents')
          .uploadBinary(
            path,
            task.file.bytes,
            fileOptions: FileOptions(
              contentType: task.file.mimeType,
              upsert: false,
            ),
          );
      if (mounted) setState(() => task.progress = .76);
      await db.from('student_documents').insert(<String, dynamic>{
        'user_id': currentUser.id,
        'title': titleFromName(task.file.name),
        'description': 'Uploaded to OG Document Wallet.',
        'file_name': task.file.name,
        'file_type': extensionOf(task.file.name),
        'storage_path': path,
        'file_size': task.file.bytes.length,
        'mime_type': task.file.mimeType,
        'folder': 'Personal',
      });
      if (!mounted) return;
      setState(() {
        task
          ..progress = 1
          ..uploading = false
          ..complete = true;
      });
      HapticFeedback.mediumImpact();
      await loadDocuments(showLoader: false);
    } catch (caught) {
      if (path != null) {
        try {
          await db.storage.from('documents').remove(<String>[path]);
        } catch (_) {
          // Keep the original failure visible.
        }
      }
      if (!mounted) return;
      setState(() {
        task
          ..uploading = false
          ..failed = true
          ..progress = 0
          ..error = friendlyError(caught);
      });
    }
  }

  Future<String> signedUrl(WalletDocument document) {
    if (document.storagePath.isEmpty) {
      if (document.legacyUrl.isNotEmpty) {
        return Future<String>.value(document.legacyUrl);
      }
      throw StateError('Missing storage path');
    }
    return db.storage
        .from('documents')
        .createSignedUrl(document.storagePath, 300);
  }

  Future<void> previewDocument(WalletDocument document) async {
    try {
      final url = await signedUrl(document);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PreviewSheet(
          document: document,
          url: url,
          loadText: () async {
            final bytes = await db.storage
                .from('documents')
                .download(document.storagePath);
            return utf8.decode(bytes, allowMalformed: true);
          },
          onDownload: () => downloadDocument(document),
        ),
      );
    } catch (caught) {
      message(friendlyError(caught), isError: true);
    }
  }

  Future<void> downloadDocument(WalletDocument document) async {
    try {
      if (kIsWeb) {
        final url = await signedUrl(document);
        final separator = url.contains('?') ? '&' : '?';
        final downloadUrl =
            '$url${separator}download=${Uri.encodeComponent(document.fileName)}';
        final opened = await launchUrl(
          Uri.parse(downloadUrl),
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        if (!opened) throw StateError('Download blocked');
      } else {
        final bytes = await db.storage
            .from('documents')
            .download(document.storagePath);
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/${document.fileName}');
        await file.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles(<XFile>[
          XFile(file.path, mimeType: document.mimeType),
        ], text: document.title);
      }
      HapticFeedback.mediumImpact();
      message('Download prepared for ${document.fileName}.');
    } catch (caught) {
      message(friendlyError(caught), isError: true);
    }
  }

  Future<void> renameDocument(WalletDocument document) async {
    final title = TextEditingController(text: document.title);
    final name = TextEditingController(text: document.fileName);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.drive_file_rename_outline_rounded),
        title: const Text('Rename document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Display title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Download name'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isNotEmpty && name.text.trim().isNotEmpty) {
                Navigator.pop(context, (title.text.trim(), name.text.trim()));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    title.dispose();
    name.dispose();
    if (result == null) return;
    try {
      await db
          .from('student_documents')
          .update(<String, dynamic>{
            'title': result.$1,
            'file_name': result.$2,
            'file_type': extensionOf(result.$2),
          })
          .eq('id', document.id);
      await loadDocuments(showLoader: false);
      message('Document renamed.');
    } catch (caught) {
      message(friendlyError(caught), isError: true);
    }
  }

  Future<void> moveDocuments(List<WalletDocument> items) async {
    if (items.isEmpty) return;
    final custom = TextEditingController();
    var chosen = folders.contains(items.first.folder)
        ? items.first.folder
        : folders.first;
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.drive_file_move_rounded),
          title: const Text('Move to folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: chosen,
                decoration: const InputDecoration(labelText: 'Folder'),
                items: folders
                    .map(
                      (folder) =>
                          DropdownMenuItem(value: folder, child: Text(folder)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => chosen = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: custom,
                decoration: const InputDecoration(
                  labelText: 'Or create a folder',
                  hintText: 'Optional',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                custom.text.trim().isEmpty ? chosen : custom.text.trim(),
              ),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
    custom.dispose();
    if (folder == null || folder.isEmpty) return;
    try {
      await db
          .from('student_documents')
          .update(<String, dynamic>{'folder': folder})
          .inFilter('id', items.map((item) => item.id).toList());
      setState(selected.clear);
      await loadDocuments(showLoader: false);
      message('${items.length} file${items.length == 1 ? '' : 's'} moved.');
    } catch (caught) {
      message(friendlyError(caught), isError: true);
    }
  }

  Future<void> duplicateDocument(WalletDocument document) async {
    final currentUser = user;
    if (currentUser == null) return;
    String? newPath;
    try {
      final bytes = await db.storage
          .from('documents')
          .download(document.storagePath);
      newPath =
          '${currentUser.id}/${DateTime.now().microsecondsSinceEpoch}_${safeName(document.fileName)}';
      await db.storage
          .from('documents')
          .uploadBinary(
            newPath,
            bytes,
            fileOptions: FileOptions(
              contentType: document.mimeType,
              upsert: false,
            ),
          );
      await db.from('student_documents').insert(<String, dynamic>{
        'user_id': currentUser.id,
        'title': '${document.title} (Copy)',
        'description': document.description,
        'file_name': document.fileName,
        'file_type': document.extension,
        'storage_path': newPath,
        'file_size': bytes.length,
        'mime_type': document.mimeType,
        'folder': document.folder,
      });
      await loadDocuments(showLoader: false);
      message('Private copy created.');
    } catch (caught) {
      if (newPath != null) {
        try {
          await db.storage.from('documents').remove(<String>[newPath]);
        } catch (_) {
          // Preserve the original duplication failure.
        }
      }
      message(friendlyError(caught), isError: true);
    }
  }

  Future<void> deleteDocuments(List<WalletDocument> items) async {
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: Text(
          'Delete ${items.length} document${items.length == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'The selected private files will be permanently removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final paths = items
          .map((item) => item.storagePath)
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList();
      if (paths.isNotEmpty) {
        await db.storage.from('documents').remove(paths);
      }
      await db
          .from('student_documents')
          .delete()
          .inFilter('id', items.map((item) => item.id).toList());
      setState(selected.clear);
      HapticFeedback.heavyImpact();
      await loadDocuments(showLoader: false);
      message('Selected documents deleted.');
    } catch (caught) {
      message(friendlyError(caught), isError: true);
    }
  }

  Future<void> downloadSelected() async {
    for (final document in selectedDocuments) {
      await downloadDocument(document);
    }
    if (mounted) setState(selected.clear);
  }

  void toggleSelection(WalletDocument document) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!selected.add(document.id)) selected.remove(document.id);
    });
  }

  void message(String value, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(value),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? AppColors.danger : AppColors.midnightInk,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: selecting
            ? IconButton(
                tooltip: 'Clear selection',
                onPressed: () => setState(selected.clear),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${selected.length} selected' : 'Document Wallet',
        ),
        actions: <Widget>[
          if (refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: grid ? 'Use list view' : 'Use grid view',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => grid = !grid);
            },
            icon: Icon(
              grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: pickFiles,
              backgroundColor: AppColors.vibeBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Upload files'),
            ),
      bottomNavigationBar: selecting
          ? BulkActionBar(
              count: selected.length,
              onDownload: downloadSelected,
              onMove: () => moveDocuments(selectedDocuments),
              onDelete: () => deleteDocuments(selectedDocuments),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && documents.isEmpty
          ? WalletError(message: error!, onRetry: loadDocuments)
          : DropTarget(
              onDragEntered: (_) => setState(() => dragging = true),
              onDragExited: (_) => setState(() => dragging = false),
              onDragDone: (details) {
                setState(() => dragging = false);
                unawaited(acceptDrop(details));
              },
              child: RefreshIndicator(
                onRefresh: () => loadDocuments(showLoader: false),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      sliver: SliverToBoxAdapter(child: buildHero()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(child: buildDropZone()),
                    ),
                    if (uploads.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverToBoxAdapter(child: buildUploadQueue()),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                      sliver: SliverToBoxAdapter(child: buildSectionHeader()),
                    ),
                    if (documents.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: WalletEmpty(onUpload: pickFiles),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                        sliver: grid
                            ? buildDocumentGrid()
                            : buildDocumentList(),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget buildSectionHeader() => Row(
    children: <Widget>[
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'My files',
              style: TextStyle(
                color: AppColors.midnightInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Long-press any file to select multiple.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      SoftPill(icon: Icons.lock_rounded, label: '${documents.length} private'),
    ],
  );

  Widget buildHero() {
    final progress = (used / capacity).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.vibeBlue.withValues(alpha: .24),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.electricCyan.withValues(alpha: .15),
              borderRadius: AppStyles.pillRadius,
            ),
            child: const Text(
              'OG VAULT • PRIVATE STORAGE',
              style: TextStyle(
                color: AppColors.electricCyan,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Your documents.\nAlways within reach.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.04,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: <Widget>[
              HeroStat(
                icon: Icons.description_rounded,
                value: '${documents.length}',
                label: 'Files',
              ),
              const SizedBox(width: 10),
              HeroStat(
                icon: Icons.cloud_done_rounded,
                value: formatBytes(used),
                label: 'Used',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: AppStyles.pillRadius,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    color: AppColors.electricCyan,
                    backgroundColor: Colors.white.withValues(alpha: .14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(progress * 100).round()}% of 500 MB',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: .06, end: 0);
  }

  Widget buildDropZone() => Semantics(
    button: true,
    label: 'Upload files. Tap to browse or drag files here.',
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: pickFiles,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: dragging
              ? AppColors.vibeBlue.withValues(alpha: .13)
              : Colors.white.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dragging ? AppColors.vibeBlue : AppColors.glassBorder,
            width: dragging ? 2 : 1.2,
          ),
          boxShadow: AppStyles.softShadow,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              dragging
                  ? Icons.file_download_done_rounded
                  : Icons.cloud_upload_outlined,
              color: AppColors.vibeBlue,
              size: 34,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    dragging ? 'Release to upload' : 'Drop files here',
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'Or tap to select multiple files • 50 MB each',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.add_circle_rounded, color: AppColors.vibeBlue),
          ],
        ),
      ),
    ),
  );

  Widget buildUploadQueue() => GlassCard(
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.sync_rounded, color: AppColors.vibeBlue),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Upload activity',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => uploads.removeWhere((task) => task.complete)),
              child: const Text('Clear finished'),
            ),
          ],
        ),
        ...uploads.map(
          (task) => UploadTile(task: task, onRetry: () => uploadTask(task)),
        ),
      ],
    ),
  );

  SliverGrid buildDocumentGrid() => SliverGrid(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 285,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: .78,
    ),
    delegate: SliverChildBuilderDelegate((context, index) {
      final document = documents[index];
      return DocumentCard(
        document: document,
        grid: true,
        selected: selected.contains(document.id),
        selecting: selecting,
        onTap: selecting
            ? () => toggleSelection(document)
            : () => previewDocument(document),
        onLongPress: () => toggleSelection(document),
        actions: actionsFor(document),
      ).animate(delay: (35 * index).ms).fadeIn(duration: 260.ms);
    }, childCount: documents.length),
  );

  SliverList buildDocumentList() => SliverList.separated(
    itemCount: documents.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      final document = documents[index];
      return DocumentCard(
        document: document,
        grid: false,
        selected: selected.contains(document.id),
        selecting: selecting,
        onTap: selecting
            ? () => toggleSelection(document)
            : () => previewDocument(document),
        onLongPress: () => toggleSelection(document),
        actions: actionsFor(document),
      );
    },
  );

  DocumentActions actionsFor(WalletDocument document) => DocumentActions(
    download: () => downloadDocument(document),
    rename: () => renameDocument(document),
    move: () => moveDocuments(<WalletDocument>[document]),
    duplicate: () => duplicateDocument(document),
    delete: () => deleteDocuments(<WalletDocument>[document]),
  );
}

class PreviewSheet extends StatefulWidget {
  const PreviewSheet({
    super.key,
    required this.document,
    required this.url,
    required this.loadText,
    required this.onDownload,
  });

  final WalletDocument document;
  final String url;
  final Future<String> Function() loadText;
  final VoidCallback onDownload;

  @override
  State<PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<PreviewSheet> {
  Future<String>? text;

  @override
  void initState() {
    super.initState();
    if (widget.document.isText) text = widget.loadText();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Container(
      height: MediaQuery.sizeOf(context).height * .92,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
            child: Row(
              children: <Widget>[
                FileIcon(document: document, size: 42),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${document.extension.toUpperCase()} • ${formatBytes(document.fileSize)}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Download',
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_rounded),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(child: buildContent()),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              border: Border(top: BorderSide(color: AppColors.glassBorder)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        document.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${document.folder} • ${relativeDate(document.uploadedAt)}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildContent() {
    if (widget.document.isImage) {
      return InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const PreviewUnavailable(),
          ),
        ),
      );
    }
    if (widget.document.isPdf) return SfPdfViewer.network(widget.url);
    if (widget.document.isText && text != null) {
      return FutureBuilder<String>(
        future: text,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return const PreviewUnavailable();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassCard(
              child: SelectableText(
                snapshot.data ?? '',
                style: const TextStyle(fontFamily: 'monospace', height: 1.5),
              ),
            ),
          );
        },
      );
    }
    return PreviewUnavailable(
      message:
          '${widget.document.extension.toUpperCase()} is securely stored but requires a compatible application. Download it to open the full document.',
    );
  }
}

class DocumentActions {
  const DocumentActions({
    required this.download,
    required this.rename,
    required this.move,
    required this.duplicate,
    required this.delete,
  });

  final VoidCallback download;
  final VoidCallback rename;
  final VoidCallback move;
  final VoidCallback duplicate;
  final VoidCallback delete;
}

enum DocumentAction { download, rename, move, duplicate, delete }

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.grid,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.actions,
  });

  final WalletDocument document;
  final bool grid;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final DocumentActions actions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '${document.title}, ${document.extension}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.vibeBlue.withValues(alpha: .1)
              : Colors.white.withValues(alpha: .78),
          borderRadius: AppStyles.bentoRadius,
          border: Border.all(
            color: selected ? AppColors.vibeBlue : Colors.white,
            width: selected ? 2 : 1,
          ),
          boxShadow: AppStyles.softShadow,
        ),
        child: InkWell(
          borderRadius: AppStyles.bentoRadius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: grid ? buildGrid() : buildList(),
        ),
      ),
    );
  }

  Widget buildGrid() => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            FileIcon(document: document, size: 44),
            const Spacer(),
            trailing(),
          ],
        ),
        const Spacer(),
        Text(
          document.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.midnightInk,
            fontSize: 16,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          document.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const Spacer(),
        Row(
          children: <Widget>[
            TypePill(document.extension),
            const Spacer(),
            Text(
              formatBytes(document.fileSize),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            const Icon(
              Icons.folder_outlined,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                document.folder,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            const Icon(Icons.lock_rounded, size: 13, color: AppColors.success),
          ],
        ),
      ],
    ),
  );

  Widget buildList() => Padding(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: <Widget>[
        FileIcon(document: document, size: 52),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                document.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.midnightInk,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${document.folder} • ${formatBytes(document.fileSize)} • ${relativeDate(document.uploadedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        trailing(),
      ],
    ),
  );

  Widget trailing() {
    if (selecting) {
      return Checkbox(value: selected, onChanged: (_) => onTap());
    }
    return PopupMenuButton<DocumentAction>(
      tooltip: 'Document actions',
      onSelected: (action) {
        switch (action) {
          case DocumentAction.download:
            actions.download();
          case DocumentAction.rename:
            actions.rename();
          case DocumentAction.move:
            actions.move();
          case DocumentAction.duplicate:
            actions.duplicate();
          case DocumentAction.delete:
            actions.delete();
        }
      },
      itemBuilder: (_) => const <PopupMenuEntry<DocumentAction>>[
        PopupMenuItem(value: DocumentAction.download, child: Text('Download')),
        PopupMenuItem(value: DocumentAction.rename, child: Text('Rename')),
        PopupMenuItem(value: DocumentAction.move, child: Text('Move')),
        PopupMenuItem(
          value: DocumentAction.duplicate,
          child: Text('Duplicate'),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: DocumentAction.delete,
          child: Text('Delete', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}

class BulkActionBar extends StatelessWidget {
  const BulkActionBar({
    super.key,
    required this.count,
    required this.onDownload,
    required this.onMove,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onDownload;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.midnightInk,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppStyles.glassShadow,
        ),
        child: Row(
          children: <Widget>[
            Text(
              '$count selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Download selected',
              onPressed: onDownload,
              color: Colors.white,
              icon: const Icon(Icons.download_rounded),
            ),
            IconButton(
              tooltip: 'Move selected',
              onPressed: onMove,
              color: Colors.white,
              icon: const Icon(Icons.drive_file_move_outline),
            ),
            IconButton(
              tooltip: 'Delete selected',
              onPressed: onDelete,
              color: const Color(0xFFFF8092),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class UploadTile extends StatelessWidget {
  const UploadTile({super.key, required this.task, required this.onRetry});

  final UploadTask task;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = task.failed
        ? AppColors.danger
        : task.complete
        ? AppColors.success
        : AppColors.vibeBlue;
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: <Widget>[
          Icon(
            task.failed
                ? Icons.error_outline_rounded
                : task.complete
                ? Icons.check_circle_rounded
                : Icons.cloud_upload_outlined,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 5,
                  borderRadius: AppStyles.pillRadius,
                  color: color,
                  backgroundColor: color.withValues(alpha: .1),
                ),
                if (task.error != null)
                  Text(
                    task.error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (task.failed)
            IconButton(
              tooltip: 'Retry upload',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            )
          else
            Text(
              task.complete ? 'Done' : '${(task.progress * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class FileIcon extends StatelessWidget {
  const FileIcon({super.key, required this.document, required this.size});

  final WalletDocument document;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = fileVisual(document.extension);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.$2.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(visual.$1, color: visual.$2, size: size * .5),
    );
  }
}

class TypePill extends StatelessWidget {
  const TypePill(this.extension, {super.key});

  final String extension;

  @override
  Widget build(BuildContext context) {
    final color = fileVisual(extension).$2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        extension.isEmpty ? 'FILE' : extension.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class HeroStat extends StatelessWidget {
  const HeroStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .65),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SoftPill extends StatelessWidget {
  const SoftPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: .08),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: AppColors.success, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .88)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class PreviewUnavailable extends StatelessWidget {
  const PreviewUnavailable({
    super.key,
    this.message =
        'This file could not be previewed. You can still download it.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.preview_outlined,
              size: 62,
              color: AppColors.vibeBlue,
            ),
            const SizedBox(height: 14),
            const Text(
              'Preview unavailable',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletEmpty extends StatelessWidget {
  const WalletEmpty({super.key, required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.folder_open_rounded,
              size: 58,
              color: AppColors.vibeBlue,
            ),
            const SizedBox(height: 13),
            const Text(
              'Your wallet is ready',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Upload academic, personal, or application documents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Choose files'),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletError extends StatelessWidget {
  const WalletError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: AppColors.vibeBlue,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletDocument {
  const WalletDocument({
    required this.id,
    required this.title,
    required this.description,
    required this.fileName,
    required this.legacyUrl,
    required this.extension,
    required this.storagePath,
    required this.fileSize,
    required this.mimeType,
    required this.folder,
    required this.uploadedAt,
  });

  factory WalletDocument.fromRow(Map<String, dynamic> row) {
    final name = (row['file_name'] ?? 'document').toString();
    final storedType = (row['file_type'] ?? '').toString().toLowerCase();
    final title = (row['title'] ?? '').toString().trim();
    final description = (row['description'] ?? '').toString().trim();
    return WalletDocument(
      id: (row['id'] ?? '').toString(),
      title: title.isEmpty ? name : title,
      description: description.isEmpty
          ? 'Private wallet document'
          : description,
      fileName: name,
      legacyUrl: (row['file_url'] ?? '').toString(),
      extension: storedType.isEmpty ? extensionOf(name) : storedType,
      storagePath: (row['storage_path'] ?? '').toString(),
      fileSize: row['file_size'] is num
          ? (row['file_size'] as num).toInt()
          : int.tryParse((row['file_size'] ?? '0').toString()) ?? 0,
      mimeType: (row['mime_type'] ?? 'application/octet-stream').toString(),
      folder: (row['folder'] ?? 'Personal').toString(),
      uploadedAt:
          DateTime.tryParse((row['uploaded_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  final String id;
  final String title;
  final String description;
  final String fileName;
  final String legacyUrl;
  final String extension;
  final String storagePath;
  final int fileSize;
  final String mimeType;
  final String folder;
  final DateTime uploadedAt;

  bool get isPdf => extension == 'pdf';
  bool get isImage =>
      <String>{'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(extension);
  bool get isText =>
      <String>{'txt', 'md', 'csv', 'json', 'xml', 'log'}.contains(extension);
}

class PendingFile {
  const PendingFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

class UploadTask {
  UploadTask(this.file);

  final PendingFile file;
  double progress = 0;
  bool uploading = false;
  bool complete = false;
  bool failed = false;
  String? error;
}

(IconData, Color) fileVisual(String extension) {
  switch (extension) {
    case 'pdf':
      return (Icons.picture_as_pdf_rounded, const Color(0xFFE5484D));
    case 'doc':
    case 'docx':
      return (Icons.article_rounded, const Color(0xFF2B6FE8));
    case 'xls':
    case 'xlsx':
    case 'csv':
      return (Icons.table_chart_rounded, AppColors.success);
    case 'ppt':
    case 'pptx':
      return (Icons.slideshow_rounded, const Color(0xFFE77817));
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
      return (Icons.image_rounded, const Color(0xFF8C4FE8));
    case 'zip':
    case 'rar':
    case '7z':
      return (Icons.folder_zip_rounded, AppColors.warning);
    default:
      return (Icons.description_rounded, AppColors.vibeBlue);
  }
}

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 || dot == name.length - 1
      ? ''
      : name.substring(dot + 1).toLowerCase();
}

String safeName(String name) {
  final safe = name
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
      .replaceAll(' ', '_');
  return safe.isEmpty ? 'document' : safe;
}

String titleFromName(String name) {
  final dot = name.lastIndexOf('.');
  return (dot > 0 ? name.substring(0, dot) : name)
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
}

String mimeFor(String name) {
  switch (extensionOf(name)) {
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'txt':
    case 'md':
    case 'csv':
      return 'text/plain';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String relativeDate(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inDays > 30) {
    return '${value.day}/${value.month}/${value.year}';
  }
  if (difference.inDays > 0) return '${difference.inDays}d ago';
  if (difference.inHours > 0) return '${difference.inHours}h ago';
  if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
  return 'Just now';
}

String friendlyError(Object error) {
  final value = error.toString();
  if (value.contains('SocketException') ||
      value.contains('Failed host lookup') ||
      value.contains('ClientException')) {
    return 'No connection. Check your internet and try again.';
  }
  if (value.contains('maximum allowed size') ||
      value.contains('Payload too large')) {
    return 'This file is larger than the 50 MB limit.';
  }
  if (value.contains('Missing storage path')) {
    return 'This legacy document is not linked to its stored file.';
  }
  return 'The document action could not be completed. Please try again.';
}
