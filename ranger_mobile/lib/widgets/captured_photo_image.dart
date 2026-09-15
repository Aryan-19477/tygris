import 'package:flutter/material.dart';

import 'captured_photo_image_stub.dart'
    if (dart.library.io) 'captured_photo_image_io.dart'
    if (dart.library.html) 'captured_photo_image_web.dart' as impl;

/// Renders a photo captured via `image_picker`/`camera` by its
/// [XFile.path], working on both native (a real file path — `Image.file`)
/// and web (a `blob:` URL — `Image.network`) without either screen needing
/// to know which. Use this everywhere a captured photo thumbnail is shown
/// instead of `Image.file`/`dart:io` directly, which fails to compile for
/// the web target.
Widget capturedPhotoImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return impl.buildCapturedPhotoImage(path, width: width, height: height, fit: fit, errorBuilder: errorBuilder);
}
