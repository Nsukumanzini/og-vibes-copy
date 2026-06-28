import 'dart:io' as io;
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:liquid_progress_indicator_v2/liquid_progress_indicator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:og_vibes_student/src/platform_file.dart' as platform_file;

class ResourceCard extends StatefulWidget {
  const ResourceCard({
    super.key,
    required this.subject,
    required this.year,
    required this.qpUrl,
    required this.memoUrl,
    required this.sizeMb,
    this.description,
    this.onSavedToBackpack,
    this.onOpenFile,
  });

  final String subject;
  final String year;
  final String qpUrl;
  final String memoUrl;
  final double sizeMb;
  final String? description;
  final ValueChanged<io.File>? onSavedToBackpack;
  final ValueChanged<io.File>? onOpenFile;

  @override
  State<ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends State<ResourceCard> {
  final Dio _dio = Dio();
  late final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(milliseconds: 900),
  );

  bool _isMemo = false;
  bool _isDownloading = false;
  double _progress = 0;
  String? _localPath;

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  String _getFileUrl() => !_isMemo ? widget.qpUrl : widget.memoUrl;

  Future<void> _downloadFile() async {
    if (_isDownloading) return;
    if (kIsWeb) {
      await _downloadFileWeb();
      return;
    }

    if (!await _ensurePermissions()) return;

    setState(() {
      _isDownloading = true;
      _progress = 0;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final sanitizedSubject = widget.subject.replaceAll(
        RegExp(r'[^a-zA-Z0-9]+'),
        '_',
      );
      final modeLabel = _isMemo ? 'memo' : 'qp';
      final filename = '${widget.year}_${sanitizedSubject}_$modeLabel.pdf';
      final savePath = p.join(dir.path, filename);

      await _dio.download(
        _getFileUrl(),
        savePath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          final percent = (received / total).clamp(0.0, 1.0);
          setState(() => _progress = percent);
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _progress = 1;
        _localPath = savePath;
      });

      final savedFile = platform_file.fileFromPath(savePath);
      if (savedFile != null) {
        widget.onSavedToBackpack?.call(savedFile);
      }
      _confettiController.play();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Added to My Backpack')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _progress = 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $error')));
    }
  }

  Future<bool> _ensurePermissions() async {
    if (io.Platform.isIOS) {
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted) return true;
    } else {
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;
    }

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Storage permission is required.')),
    );
    return false;
  }

  void _openLocalFile() {
    if (_localPath == null) return;
    final file = platform_file.fileFromPath(_localPath!);
    if (file != null) {
      widget.onOpenFile?.call(file);
    }
  }

  /// Web download: Opens the file URL in a new browser tab.
  /// Browser will handle the download via native download mechanism.
  Future<void> _downloadFileWeb() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.5;
    });

    try {
      final fileUrl = _getFileUrl();
      final uri = Uri.parse(fileUrl);

      // Verify URL is valid
      if (fileUrl.isEmpty) {
        throw 'File URL is empty';
      }

      // Launch in external browser/tab
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _confettiController.play();
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _progress = 1;
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening download in your browser...'),
            ),
          );
        }
      } else {
        throw 'Cannot open file URL';
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _progress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showLiquid = _progress > 0 && _progress < 1;
    final bool isDownloaded = _localPath != null && _progress >= 1;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF030615), Color(0xFF0F1C3A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDownloaded ? Colors.greenAccent : Colors.white24,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subject,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.description ?? 'Vault Card',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.year,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _isMemo ? 'Memo' : 'Question Paper',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Switch.adaptive(
                      value: !_isMemo,
                      activeTrackColor: Colors.lightBlueAccent,
                      onChanged: (value) => setState(() => _isMemo = !value),
                    ),
                  ),
                  Text(
                    '${widget.sizeMb.toStringAsFixed(1)} MB',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (showLiquid)
                SizedBox(
                  height: 48,
                  child: LiquidLinearProgressIndicator(
                    value: _progress,
                    valueColor: const AlwaysStoppedAnimation(Colors.blue),
                    backgroundColor: Colors.white,
                    borderRadius: 16,
                    center: Text(
                      '${(_progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isDownloaded
                      ? Row(
                          key: const ValueKey('downloaded'),
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.greenAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _openLocalFile,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Open in Backpack'),
                              ),
                            ),
                          ],
                        )
                      : FilledButton.icon(
                          key: const ValueKey('download'),
                          onPressed: _downloadFile,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Save to My Backpack'),
                        ),
                ),
            ],
          ),
        ),
        Positioned(
          top: -8,
          right: 24,
          child: SizedBox(
            height: 60,
            width: 60,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 18,
              maxBlastForce: 12,
              minBlastForce: 6,
              emissionFrequency: 0.01,
              gravity: 0.3,
              colors: const [
                Colors.greenAccent,
                Colors.lightBlueAccent,
                Colors.white,
              ],
              createParticlePath: (size) {
                final path = Path();
                final angle = 2 * pi / 5;
                const radius = 6.0;
                path.moveTo(radius, 0);
                for (int i = 1; i < 5; i++) {
                  final x = radius * cos(angle * i);
                  final y = radius * sin(angle * i);
                  path.lineTo(radius + x, y);
                }
                return path;
              },
            ),
          ),
        ),
      ],
    );
  }
}
