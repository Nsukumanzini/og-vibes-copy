import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

enum _AttachmentType { image, document }

class _PostAttachment {
  _PostAttachment({
    required this.id,
    required this.name,
    required this.type,
    this.bytes,
    this.path,
  });

  final String id;
  final String name;
  final _AttachmentType type;
  final Uint8List? bytes;
  final String? path;
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<_PostAttachment> _attachments = [];
  final List<String> _selectedTags = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }


  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in before posting.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final content = _contentController.text.trim();
      final mediaUrls = <String>[];
      final documentUrls = <String>[];

      for (final attachment in _attachments) {
        if (attachment.bytes == null || attachment.bytes!.isEmpty) {
          continue;
        }

        final safeName = attachment.name
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final fileName =
            'posts/${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

        await Supabase.instance.client.storage
            .from('posts')
            .uploadBinary(fileName, attachment.bytes!);

        final signedUrl = await Supabase.instance.client.storage
            .from('posts')
            .createSignedUrl(fileName, 60 * 60 * 24 * 365);

        if (attachment.type == _AttachmentType.image) {
          mediaUrls.add(signedUrl);
        } else {
          documentUrls.add(signedUrl);
        }
      }

      await Supabase.instance.client.from('posts').insert({
        'user_id': user.id,
        'content': content,
        'images': mediaUrls,
        'documents': documentUrls,
        'tags': _selectedTags,
        'is_deleted': false,
        'is_anonymous': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your post is now live on the news feed.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to publish post: $error')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty) {
      final normalizedTag = tag.startsWith('#') ? tag : '#$tag';
      if (!_selectedTags.contains(normalizedTag)) {
        setState(() {
          _selectedTags.add(normalizedTag);
          _tagController.clear();
        });
      }
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  void _pickMedia() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2962FF)),
              title: const Text('Take a photo'),
              onTap: () async {
                Navigator.pop(context);
                final photo = await _imagePicker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 80,
                );
                if (photo == null) return;
                final bytes = await photo.readAsBytes();
                setState(() {
                  _attachments.add(_PostAttachment(
                    id: 'camera_${DateTime.now().millisecondsSinceEpoch}',
                    name: photo.name,
                    type: _AttachmentType.image,
                    bytes: bytes,
                    path: photo.path,
                  ));
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF2962FF)),
              title: const Text('Pick from gallery'),
              onTap: () async {
                Navigator.pop(context);
                final photo = await _imagePicker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                );
                if (photo == null) return;
                final bytes = await photo.readAsBytes();
                setState(() {
                  _attachments.add(_PostAttachment(
                    id: 'gallery_${DateTime.now().millisecondsSinceEpoch}',
                    name: photo.name,
                    type: _AttachmentType.image,
                    bytes: bytes,
                    path: photo.path,
                  ));
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Color(0xFF2962FF)),
              title: const Text('Upload a file'),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                  allowMultiple: true,
                  withData: true,
                );
                if (result == null) return;
                setState(() {
                  for (final file in result.files) {
                    _attachments.add(_PostAttachment(
                      id: '${file.name}_${DateTime.now().millisecondsSinceEpoch}',
                      name: file.name,
                      type: _isImageFile(file.extension) ? _AttachmentType.image : _AttachmentType.document,
                      bytes: file.bytes,
                      path: file.path,
                    ));
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isImageFile(String? extension) {
    if (extension == null) return false;
    final ext = extension.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'heic', 'webp'].contains(ext);
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create Post',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Share with your campus community. Add tags and media to make your post stand out.',
          style: TextStyle(color: Colors.grey[700], height: 1.5),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Content field
          TextFormField(
            controller: _contentController,
            decoration: InputDecoration(
              labelText: 'What\'s on your mind?',
              hintText: 'Share your thoughts, ask a question, or post an update...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: Colors.white,
            ),
            keyboardType: TextInputType.multiline,
            maxLines: 6,
            validator: (value) {
              final hasText = (value ?? '').trim().isNotEmpty;
              if (!hasText && _attachments.isEmpty) {
                return 'Please add content or at least one attachment before posting.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Tagging section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Tags',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0D47A1),
                        ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration: InputDecoration(
                            hintText: 'e.g., #campus, #study',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addTag,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedTags.map((tag) {
                        return Chip(
                          label: Text(tag),
                          onDeleted: () => _removeTag(tag),
                          backgroundColor: const Color(0xFFE3F2FD),
                          labelStyle: const TextStyle(color: Color(0xFF0D47A1)),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Media upload section
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF2962FF),
                child: Icon(Icons.add_photo_alternate, color: Colors.white),
              ),
              title: const Text('Add Media'),
              subtitle: const Text('Photos, files, or links'),
              trailing: ElevatedButton.icon(
                onPressed: _pickMedia,
                icon: const Icon(Icons.attach_file),
                label: const Text('Select'),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Media preview section
          if (_attachments.isNotEmpty) ...[
            Text(
              'Attachments (${_attachments.length})',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D47A1),
                  ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _attachments.asMap().entries.map((entry) {
                  final index = entry.key;
                  final attachment = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.grey[100],
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: attachment.type == _AttachmentType.image && attachment.bytes != null
                                ? Image.memory(
                                    attachment.bytes!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          attachment.type == _AttachmentType.image
                                              ? Icons.image
                                              : Icons.insert_drive_file,
                                          size: 34,
                                          color: const Color(0xFF2962FF),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          attachment.name,
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _attachments.removeAt(index);
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.red,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      onPressed: _isSubmitting ? null : _submitPost,
      icon: const Icon(Icons.send),
      label: Text(_isSubmitting ? 'Posting...' : 'Publish to News Feed'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildForm(),
            const SizedBox(height: 24),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }
}
