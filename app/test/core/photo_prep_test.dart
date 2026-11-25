import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saenggak/core/photo_prep.dart';

void main() {
  test('crops a capture to a centered square JPEG of the upload size', () {
    // A wide frame: red on the left and right edges, green in the middle.
    final frame = img.Image(width: 1280, height: 720);
    img.fill(frame, color: img.ColorRgb8(255, 0, 0));
    img.fillRect(frame, x1: 280, y1: 0, x2: 1000, y2: 720, color: img.ColorRgb8(0, 255, 0));
    final out = preparePhoto(img.encodeJpg(frame))!;

    expect(out.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    final photo = img.decodeJpg(out)!;
    expect([photo.width, photo.height], [photoSize, photoSize]);
    // The red edges were cropped away.
    final corner = photo.getPixel(2, 2);
    expect(corner.g, greaterThan(200));
    expect(corner.r, lessThan(60));
    expect(out.length, lessThan(2 * 1024 * 1024));
  });

  test('keeps a small capture at its own size', () {
    final out = preparePhoto(img.encodeJpg(img.Image(width: 300, height: 400)))!;
    final photo = img.decodeJpg(out)!;
    expect([photo.width, photo.height], [300, 300]);
  });

  test('mirrors a front-camera capture', () {
    final frame = img.Image(width: 100, height: 100);
    img.fillRect(frame, x1: 0, y1: 0, x2: 30, y2: 100, color: img.ColorRgb8(255, 255, 255));
    final photo = img.decodeJpg(preparePhoto(img.encodeJpg(frame), mirror: true)!)!;
    expect(photo.getPixel(95, 50).r, greaterThan(200));
    expect(photo.getPixel(5, 50).r, lessThan(60));
  });

  test('rejects bytes that are not an image', () {
    expect(preparePhoto(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('has a message for every reason the server gives', () {
    for (final code in ['no_face', 'many_faces', 'unclear', 'inappropriate', 'bad_image']) {
      expect(photoProblemMessage(code), isNot(photoProblemMessage('unknown')));
    }
  });
}
