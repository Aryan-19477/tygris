import 'dart:io';

import 'package:flutter/material.dart';

Widget buildCapturedPhotoImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.file(File(path), width: width, height: height, fit: fit, errorBuilder: errorBuilder);
}
