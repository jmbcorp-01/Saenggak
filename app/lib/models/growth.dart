import 'post.dart' show parseServerTime;

/// Whether Saenggak's own accounts and public pages may show the writer's
/// posts. Off until they turn it on.
class SharingSettings {
  const SharingSettings({this.shareOk = false, this.anonymous = false});

  factory SharingSettings.fromJson(Map<String, dynamic> j) =>
      SharingSettings(shareOk: j['shareOk'] as bool? ?? false, anonymous: j['anonymous'] as bool? ?? false);

  final bool shareOk;

  /// Shown without the writer's name.
  final bool anonymous;
}

/// The reader's own invite link.
class Invite {
  const Invite({required this.code, required this.url});

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(code: j['code'] as String, url: j['url'] as String);

  final String code;
  final String url;
}

/// The question above the editor today.
class DailyQuestion {
  const DailyQuestion({required this.ko, required this.en});

  final String ko;
  final String en;

  String text(String lang) => lang == 'ko' ? ko : en;
}

class DashboardDay {
  const DashboardDay({
    required this.day,
    required this.signups,
    required this.posts,
    required this.empathies,
    required this.activePeople,
  });

  factory DashboardDay.fromJson(Map<String, dynamic> j) => DashboardDay(
    day: j['day'] as String,
    signups: (j['signups'] as num).toInt(),
    posts: (j['posts'] as num).toInt(),
    empathies: (j['empathies'] as num).toInt(),
    activePeople: (j['activePeople'] as num).toInt(),
  );

  final String day;
  final int signups;
  final int posts;
  final int empathies;
  final int activePeople;
}

class Retention {
  const Retention({this.rate, this.cohort = 0});

  factory Retention.fromJson(Map<String, dynamic>? j) =>
      Retention(rate: (j?['rate'] as num?)?.toDouble(), cohort: (j?['cohort'] as num? ?? 0).toInt());

  /// 0 to 1, or null with no one old enough yet.
  final double? rate;
  final int cohort;
}

class SourceStat {
  const SourceStat({required this.channel, required this.signups, required this.active7});

  factory SourceStat.fromJson(Map<String, dynamic> j) => SourceStat(
    channel: j['channel'] as String,
    signups: (j['signups'] as num).toInt(),
    active7: (j['active7'] as num).toInt(),
  );

  final String channel;
  final int signups;
  final int active7;
}

class Dashboard {
  const Dashboard({required this.days, required this.d1, required this.d7, required this.d30, required this.sources});

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final r = j['retention'] as Map<String, dynamic>? ?? const {};
    return Dashboard(
      days: (j['days'] as List).cast<Map<String, dynamic>>().map(DashboardDay.fromJson).toList(),
      d1: Retention.fromJson(r['d1'] as Map<String, dynamic>?),
      d7: Retention.fromJson(r['d7'] as Map<String, dynamic>?),
      d30: Retention.fromJson(r['d30'] as Map<String, dynamic>?),
      sources: (j['sources'] as List).cast<Map<String, dynamic>>().map(SourceStat.fromJson).toList(),
    );
  }

  final List<DashboardDay> days;
  final Retention d1;
  final Retention d7;
  final Retention d30;
  final List<SourceStat> sources;
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.targetId,
    required this.at,
    this.adminHandle,
    this.note = '',
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: j['id'] as String,
    adminHandle: j['adminHandle'] as String?,
    action: j['action'] as String,
    targetId: j['targetId'] as String,
    note: j['note'] as String? ?? '',
    at: parseServerTime(j['at'] as String),
  );

  final String id;
  final String? adminHandle;
  final String action;
  final String targetId;
  final String note;
  final DateTime at;
}

/// The featured post, as its writer allows it to be shown.
class PromoPost {
  const PromoPost({
    required this.body,
    required this.lang,
    required this.authorHandle,
    this.authorName,
    this.empathyCount = 0,
    this.typingMs = 0,
  });

  factory PromoPost.fromJson(Map<String, dynamic> j) => PromoPost(
    body: j['body'] as String,
    lang: j['lang'] as String,
    authorHandle: j['authorHandle'] as String,
    authorName: j['authorName'] as String?,
    empathyCount: (j['empathyCount'] as num? ?? 0).toInt(),
    typingMs: (j['typingMs'] as num? ?? 0).toInt(),
  );

  final String body;
  final String lang;
  final String authorHandle;

  /// Null when the writer chose to be shown without their name.
  final String? authorName;
  final int empathyCount;
  final int typingMs;
}

/// One post the promo agent picked for Saenggak's own accounts.
class PromoItem {
  const PromoItem({
    required this.id,
    required this.status,
    required this.caption,
    required this.linkCode,
    this.post,
    this.cardUrl,
    this.scheduledFor,
    this.posted = const {},
    this.error,
    this.clicks = 0,
    this.signups = 0,
  });

  factory PromoItem.fromJson(Map<String, dynamic> j) => PromoItem(
    id: j['id'] as String,
    status: j['status'] as String,
    caption: j['caption'] as String? ?? '',
    linkCode: j['linkCode'] as String,
    post: j['post'] == null ? null : PromoPost.fromJson(j['post'] as Map<String, dynamic>),
    cardUrl: j['cardUrl'] as String?,
    scheduledFor: j['scheduledFor'] == null ? null : parseServerTime(j['scheduledFor'] as String),
    posted: (j['posted'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
    error: j['error'] as String?,
    clicks: (j['clicks'] as num? ?? 0).toInt(),
    signups: (j['signups'] as num? ?? 0).toInt(),
  );

  final String id;

  /// pending, approved, failed, takedown, posted, skipped or withdrawn.
  final String status;
  final String caption;
  final String linkCode;
  final PromoPost? post;
  final String? cardUrl;
  final DateTime? scheduledFor;

  /// Channel to the id of the post there.
  final Map<String, String> posted;
  final String? error;
  final int clicks;
  final int signups;
}

class PromoPage {
  const PromoPage(this.items, this.channels);

  final List<PromoItem> items;

  /// Saenggak's own accounts the agent can post to.
  final List<String> channels;
}

class LinkStat {
  const LinkStat({
    required this.code,
    required this.channel,
    this.label = '',
    this.clicks = 0,
    this.signups = 0,
    this.active7 = 0,
  });

  factory LinkStat.fromJson(Map<String, dynamic> j) => LinkStat(
    code: j['code'] as String,
    channel: j['channel'] as String,
    label: j['label'] as String? ?? '',
    clicks: (j['clicks'] as num? ?? 0).toInt(),
    signups: (j['signups'] as num? ?? 0).toInt(),
    active7: (j['active7'] as num? ?? 0).toInt(),
  );

  /// '*' for the totals of every invite code or every promo post.
  final String code;
  final String channel;
  final String label;
  final int clicks;
  final int signups;

  /// Of those who signed up, still active a week later.
  final int active7;
}

class AdminQuestion {
  const AdminQuestion({required this.day, required this.textKo, required this.textEn, required this.approved});

  factory AdminQuestion.fromJson(Map<String, dynamic> j) => AdminQuestion(
    day: j['day'] as String,
    textKo: j['textKo'] as String,
    textEn: j['textEn'] as String,
    approved: j['status'] == 'approved',
  );

  final String day;
  final String textKo;
  final String textEn;
  final bool approved;
}

/// Channels an admin can make a link code for.
const linkChannels = ['community', 'instagram', 'threads', 'x', 'youtube', 'tiktok', 'press', 'event', 'web', 'other'];
