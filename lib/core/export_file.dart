import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

/// Saves an exported file where the user can find it.
///
/// Web: the browser's Downloads folder. Phone: the system "Save to…" picker,
/// so the user chooses the place (e.g. Downloads). A plain save on Android
/// goes to the app's private folder, which the Files app does not show.
///
/// Returns where it went, for the confirmation message, or null when the
/// user cancelled the picker.
Future<String?> saveExport({
  required String name,
  required Uint8List bytes,
  required String extension,
  required MimeType mimeType,
}) async {
  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: extension,
      mimeType: mimeType,
    );
    return 'Downloads';
  }
  final path = await FileSaver.instance.saveAs(
    name: name,
    bytes: bytes,
    fileExtension: extension,
    mimeType: mimeType,
  );
  if (path == null || path.isEmpty) return null;
  return 'the folder you chose';
}
