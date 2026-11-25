/// What happened when a post was sent: published with its extras, or refused.
sealed class PublishOutcome {
  const PublishOutcome();
}

class Published extends PublishOutcome {
  const Published({
    required this.postId,
    required this.typingTime,
    required this.similarPeople,
    required this.showSimilar,
    required this.firstPhrases,
    required this.writingDays,
    required this.followUnlocked,
  });

  factory Published.fromJson(Map<String, dynamic> j) {
    final similar = j['similar'] as Map<String, dynamic>;
    return Published(
      postId: j['id'] as String,
      typingTime: Duration(milliseconds: (j['typingMs'] as num).toInt()),
      similarPeople: (similar['people'] as num).toInt(),
      showSimilar: similar['show'] as bool,
      firstPhrases: (j['firstPhrases'] as List).cast<String>(),
      writingDays: (j['writingDays'] as num).toInt(),
      followUnlocked: j['followUnlocked'] as bool,
    );
  }

  final String postId;
  final Duration typingTime;

  /// Other people who wrote something close in meaning.
  final int similarPeople;

  /// False under three people; the count is then not shown.
  final bool showSimilar;

  /// Phrases this post was the first in the app to use, at most three.
  final List<String> firstPhrases;

  final int writingDays;
  final bool followUnlocked;
}

enum RejectReason { tooShort, tooLong, notHuman, blocked, locked, notFound, network }

class Rejected extends PublishOutcome {
  const Rejected(this.reason, {this.blockedFor});

  /// Maps a server error body to a reason.
  factory Rejected.fromJson(int status, Map<String, dynamic> j) {
    switch (j['error']) {
      case 'invalid_length':
        return Rejected(j['verdict'] == 'too_long' ? RejectReason.tooLong : RejectReason.tooShort);
      case 'not_human':
        return const Rejected(RejectReason.notHuman);
      case 'blocked':
        return Rejected(RejectReason.blocked, blockedFor: j['reason'] as String?);
      case 'locked':
        return const Rejected(RejectReason.locked);
      case 'not_found':
        return const Rejected(RejectReason.notFound);
    }
    return const Rejected(RejectReason.network);
  }

  final RejectReason reason;

  /// The content filter's reason when [reason] is [RejectReason.blocked].
  final String? blockedFor;

  /// What to tell the writer. The draft stays, so they can rewrite it.
  String get message => switch (reason) {
    RejectReason.tooShort => '조금 더 써주세요. 한국어 40자, 영어 15단어 정도부터 올릴 수 있어요.',
    RejectReason.tooLong => '조금 줄여주세요. 한국어 200자, 영어 70단어 정도까지 올릴 수 있어요.',
    RejectReason.notHuman => '사람이 직접 입력한 기록으로 확인되지 않았어요. 다시 써주세요.',
    RejectReason.locked => '공감을 받은 글은 수정할 수 없어요.',
    RejectReason.notFound => '글을 찾을 수 없어요. 이미 삭제됐을 수 있어요.',
    RejectReason.network => '연결이 불안정해요. 잠시 후 다시 시도해주세요.',
    RejectReason.blocked => switch (blockedFor) {
      'profanity' => '욕설이나 비하 표현이 있어 올리지 않았어요.',
      'sexual' => '성적인 내용이 있어 올리지 않았어요.',
      'crime' => '범죄와 관련된 내용이 있어 올리지 않았어요.',
      'spam' => '광고나 홍보로 보여 올리지 않았어요.',
      'not_a_thought' => '생각이나 느낌을 담은 글로 보이지 않아 올리지 않았어요.',
      _ => '검토가 필요한 글이라 지금은 올리지 않았어요.',
    },
  };
}
