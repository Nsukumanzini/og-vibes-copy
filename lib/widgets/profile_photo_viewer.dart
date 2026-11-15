import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ProfilePhotoButton extends StatelessWidget {
  const ProfilePhotoButton({
    super.key,
    required this.url,
    required this.name,
    required this.child,
  });
  final String? url;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final photo = url?.trim() ?? '';
    if (photo.isEmpty) return child;
    return Semantics(
      button: true,
      label: 'View $name’s profile picture',
      child: Tooltip(
        message: 'View profile picture',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfilePhotoViewer(url: photo, name: name),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class ProfilePhotoViewer extends StatefulWidget {
  const ProfilePhotoViewer({super.key, required this.url, required this.name});
  final String url;
  final String name;

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  final _transform = TransformationController();
  int _attempt = 0;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      5.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.name),
      actions: [
        IconButton(
          tooltip: 'Zoom out',
          onPressed: () => _zoom(0.8),
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          tooltip: 'Zoom in',
          onPressed: () => _zoom(1.25),
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: 'Reset zoom',
          onPressed: () => _transform.value = Matrix4.identity(),
          icon: const Icon(Icons.fit_screen),
        ),
      ],
    ),
    body: SafeArea(
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: CachedNetworkImage(
            key: ValueKey(_attempt),
            imageUrl: widget.url,
            fit: BoxFit.contain,
            imageBuilder: (_, image) => Image(
              image: image,
              fit: BoxFit.contain,
              semanticLabel: '${widget.name}’s profile picture',
            ),
            placeholder: (_, _) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (_, _, _) => Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load this picture.',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _attempt++),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
