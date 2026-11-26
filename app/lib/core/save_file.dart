import 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart' as impl;

/// Gives the person a text file. On the web it downloads; elsewhere the text
/// is copied so it can be pasted into a note or an email. Returns true when
/// it downloaded.
Future<bool> saveTextFile(String name, String text) => impl.saveTextFile(name, text);
