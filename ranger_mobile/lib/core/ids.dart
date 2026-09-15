import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Single place every entity constructor calls for a new id, so swapping
/// id generation strategy (e.g. to match a future Supabase default) only
/// touches one file.
String newId() => _uuid.v4();
