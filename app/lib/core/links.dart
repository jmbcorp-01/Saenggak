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
