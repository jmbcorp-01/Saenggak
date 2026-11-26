import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';

/// The public site with the terms, privacy policy and support pages. The web
/// app uses wherever it is served from; mobile builds can set SITE_URL.
///
/// English readers get the English pages, which sit under /en/.
Uri siteUri(String page) {
  if (AppLang.instance.value == 'en') page = 'en/$page';
  const site = String.fromEnvironment('SITE_URL', defaultValue: 'https://saenggak.app');
  return kIsWeb ? Uri.base.resolve('/$page') : Uri.parse('$site/$page');
}

Future<void> openPage(String page) => launchUrl(siteUri(page), mode: LaunchMode.externalApplication);

/// A link that opens one post in the app. On the web it is this site.
Uri postLink(String postId) {
  const site = String.fromEnvironment('SITE_URL', defaultValue: 'https://saenggak.app');
  final base = kIsWeb ? Uri.base.resolve('/') : Uri.parse('$site/');
  return base.replace(queryParameters: {'post': postId});
}

/// The post a link asked for, when the web app was opened from one.
String? linkedPostId([Uri? at]) {
  final uri = at ?? (kIsWeb ? Uri.base : null);
  final id = uri?.queryParameters['post'];
  return id != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ? id : null;
}
