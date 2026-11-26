import 'package:flutter/services.dart';

Future<bool> saveTextFile(String name, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  return false;
}
