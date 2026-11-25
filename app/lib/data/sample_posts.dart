import '../models/post.dart';

/// Placeholder posts until the AWS backend is connected.
const samplePosts = <Post>[
  Post(
    id: 'p1',
    authorName: '윤서',
    authorHandle: 'yoonseo',
    authorInitial: '윤',
    avatarColor: 0xFF3B4A42,
    body: '오늘은 아무 말도 하지 않은 시간이 가장 길었다. 그런데 이상하게 그 시간에 나를 가장 많이 들은 것 같다.',
    postedAgo: '2시간',
    typingTime: Duration(minutes: 2, seconds: 18),
    empathyCount: 24,
  ),
  Post(
    id: 'p2',
    authorName: 'Daniel',
    authorHandle: 'daniel.k',
    authorInitial: 'D',
    avatarColor: 0xFFC7B9A5,
    body: '우리는 확신이 있어서 움직이는 게 아니라, 움직이고 나서야 확신을 만든다고 생각한다.',
    postedAgo: '3시간',
    typingTime: Duration(minutes: 1, seconds: 5),
    empathyCount: 9,
    empathizedByMe: true,
    translatedFrom: '영어',
  ),
  Post(
    id: 'p3',
    authorName: '하루',
    authorHandle: 'haru',
    authorInitial: '하',
    avatarColor: 0xFFE4DDD2,
    body: '지하철에서 모르는 사람이 내 어깨에 기대 잠들었다. 깨우지 않았다. 나도 그렇게 기대고 싶었던 날이 있었으니까.',
    postedAgo: '5시간',
    typingTime: Duration(minutes: 3, seconds: 41),
    empathyCount: 51,
  ),
];
