import 'package:flutter/material.dart';

/// Fallback for a target with neither `dart:io` nor `dart:html` — should
/// not normally be hit on Flutter's supported platforms.
Widget buildCapturedPhotoImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return const Icon(Icons.image_not_supported_outlined);
}
