import 'package:material_ui/material_ui.dart';

import '../models/post.dart';
import 'sample_posts.dart';

/// In-memory posts until the AWS backend is connected.
class PostStore extends ChangeNotifier {
  PostStore([List<Post>? initial]) : _posts = [...(initial ?? samplePosts)];

  final List<Post> _posts;

  /// Days with at least one post. Ten unlock following.
  int writingDays = 7;
  static const int daysToFollow = 10;

  List<Post> get posts => List.unmodifiable(_posts);
  List<Post> get mine => _posts.where((p) => p.isMine).toList();

  void toggleEmpathy(String id) {
    final i = _posts.indexWhere((p) => p.id == id);
    if (i < 0 || _posts[i].isMine) return;
    final p = _posts[i];
    _posts[i] = p.copyWith(
      empathizedByMe: !p.empathizedByMe,
      empathyCount: p.empathyCount + (p.empathizedByMe ? -1 : 1),
    );
    notifyListeners();
  }

  void add(Post post) {
    _posts.insert(0, post);
    notifyListeners();
  }
}
