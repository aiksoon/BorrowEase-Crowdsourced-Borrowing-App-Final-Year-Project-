// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class InlineWebVideoPlayer extends StatefulWidget {
  const InlineWebVideoPlayer({super.key, required this.url});

  final String url;

  @override
  State<InlineWebVideoPlayer> createState() => _InlineWebVideoPlayerState();
}

class _InlineWebVideoPlayerState extends State<InlineWebVideoPlayer> {
  late final String _viewType;
  late final html.VideoElement _videoElement;

  @override
  void initState() {
    super.initState();
    _viewType =
        'inline-video-${DateTime.now().microsecondsSinceEpoch}-${widget.url.hashCode}';

    _videoElement = html.VideoElement()
      ..src = widget.url
      ..controls = true
      ..autoplay = false
      ..loop = false
      ..muted = false
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _videoElement,
    );
  }

  @override
  void didUpdateWidget(covariant InlineWebVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _videoElement.src = widget.url;
      _videoElement.load();
    }
  }

  @override
  void dispose() {
    _videoElement.pause();
    _videoElement.removeAttribute('src');
    _videoElement.load();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
