import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> saveTextFile(String name, String text) async {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: 'application/json'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
