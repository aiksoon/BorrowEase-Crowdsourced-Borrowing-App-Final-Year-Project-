// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> downloadTextFile({
  required String fileName,
  required String content,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return downloadBytesFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'text/plain;charset=utf-8',
  );
}

Future<bool> downloadBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: blobUrl)
    ..download = fileName
    ..style.display = 'none';

  final body = html.document.body;
  if (body == null) return false;

  body.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(blobUrl);
  return true;
}
