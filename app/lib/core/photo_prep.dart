import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The longest side, in pixels, of the photo sent to the server.
const photoSize = 512;

/// Turns a camera capture into the square JPEG the server takes: upright,
/// cropped to the center, [photoSize] pixels on a side, and well under the
/// server's 2 MB limit. Returns null when the bytes are not an image.
Uint8List? preparePhoto(Uint8List captured, {bool mirror = false}) {
  final decoded = img.decodeImage(captured);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final side = image.width < image.height ? image.width : image.height;
  image = img.copyCrop(image, x: (image.width - side) ~/ 2, y: (image.height - side) ~/ 2, width: side, height: side);
  if (side > photoSize) image = img.copyResize(image, width: photoSize, height: photoSize);
  // The front camera's preview is a mirror; flip so the photo matches what the person saw.
  if (mirror) image = img.flipHorizontal(image);
  return img.encodeJpg(image, quality: 85);
}

/// What to tell the person when the server turns a photo down.
String photoProblemMessage(String code) => switch (code) {
  'no_face' => '얼굴이 보이지 않아요. 얼굴이 화면 가운데 오도록 다시 찍어주세요.',
  'many_faces' => '한 사람의 얼굴만 나오게 찍어주세요.',
  'unclear' => '얼굴이 흐리거나 어둡거나 너무 작아요. 밝은 곳에서 정면으로 다시 찍어주세요.',
  'inappropriate' => '프로필 사진으로 쓸 수 없는 사진이에요.',
  'bad_image' => '사진을 읽지 못했어요. 다시 찍어주세요.',
  'rate_limited' => '잠시 후에 다시 시도해주세요.',
  'profile_required' => '프로필을 먼저 만들어주세요.',
  _ => '사진을 올리지 못했어요. 다시 시도해주세요.',
};
