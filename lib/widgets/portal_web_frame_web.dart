// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

class PortalWebFrame extends StatelessWidget {
  PortalWebFrame({super.key, required this.url}) {
    viewType = 'og-portal-${url.hashCode}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (_) => html.IFrameElement()
      ..src = url
      ..title = 'Gert Sibande TVET College portal'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%');
  }
  final String url;
  late final String viewType;
  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: viewType);
}
