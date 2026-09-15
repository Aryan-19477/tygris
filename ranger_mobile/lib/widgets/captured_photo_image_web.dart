import 'package:flutter/material.dart';

/// On web, `image_picker`/`camera` hand back a `blob:`/`http(s):` URL
/// rather than a filesystem path (there is no filesystem) — `Image.network`
/// loads those directly.
Widget buildCapturedPhotoImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.network(path, width: width, height: height, fit: fit, errorBuilder: errorBuilder);
}
