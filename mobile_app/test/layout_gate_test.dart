import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:object_detector/core/ffi/native_structs.dart';

void main() {
  test('Dart FFI Layout Gate: YoloDetectionBox must be exactly 40 bytes', () {
    final size = sizeOf<YoloDetectionBox>();
    // ignore: avoid_print
    print('Dart sizeOf<YoloDetectionBox>() = $size');
    expect(size, equals(40));
  });

  test('Dart FFI Layout Gate: YoloFrameResult must be exactly 4024 bytes', () {
    final size = sizeOf<YoloFrameResult>();
    // ignore: avoid_print
    print('Dart sizeOf<YoloFrameResult>() = $size');
    expect(size, equals(4024));
  });
}
