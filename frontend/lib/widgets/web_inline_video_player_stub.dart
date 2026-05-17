import 'package:flutter/widgets.dart';

class InlineWebVideoPlayer extends StatelessWidget {
  const InlineWebVideoPlayer({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
