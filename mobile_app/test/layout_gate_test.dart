import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:object_detector/core/ffi/native_structs.dart';

void main() {
  test('Dart FFI Layout Gate: YoloDetectionBox must be exactly 40 bytes', () {
    final size = sizeOf<YoloDetectionBox>();
    expect(size, equals(40));
  });

  test('Dart FFI Layout Gate: YoloFrameResult must be exactly 4024 bytes', () {
    final size = sizeOf<YoloFrameResult>();
    expect(size, equals(4024));
  });

  test('Dart FFI Layout Gate: MultiTaskHeader must be exactly 28 bytes', () {
    final size = sizeOf<MultiTaskHeader>();
    expect(size, equals(28));
  });

  test('Dart FFI Layout Gate: YoloSegmentationResult must be exactly 8792 bytes', () {
    final size = sizeOf<YoloSegmentationResult>();
    expect(size, equals(8792));
  });

  test('Dart FFI Layout Gate: YoloPoseResult must be exactly 4592 bytes', () {
    final size = sizeOf<YoloPoseResult>();
    expect(size, equals(4592));
  });

  test('Dart FFI Layout Gate: YoloClassificationResult must be exactly 72 bytes', () {
    final size = sizeOf<YoloClassificationResult>();
    expect(size, equals(72));
  });

  test('Dart FFI Layout Gate: YoloObbResult must be exactly 3232 bytes', () {
    final size = sizeOf<YoloObbResult>();
    expect(size, equals(3232));
  });

  test('Dart FFI Layout Gate: enforceLayoutGate() must pass without throwing', () {
    expect(() => enforceLayoutGate(), returnsNormally);
  });
}
