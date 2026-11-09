import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

const _orientationDegrees = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Ubah frame kamera menjadi [InputImage] untuk ML Kit.
///
/// Android: frame NV21 (1 plane). iOS: frame BGRA8888 (1 plane).
/// Mengembalikan null bila format frame tidak didukung.
InputImage? cameraImageToInputImage(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation deviceOrientation,
) {
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else {
    var compensation = _orientationDegrees[deviceOrientation];
    if (compensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      compensation = (sensorOrientation + compensation) % 360;
    } else {
      compensation = (sensorOrientation - compensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(compensation);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
  if (format == null) return null;
  if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
  if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
  if (image.planes.length != 1) return null;

  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

/// Ukuran gambar setelah diputar tegak; bounding box ML Kit memakai koordinat ini.
Size uprightImageSize(InputImageMetadata metadata) {
  final rotated =
      metadata.rotation == InputImageRotation.rotation90deg ||
      metadata.rotation == InputImageRotation.rotation270deg;
  return rotated
      ? Size(metadata.size.height, metadata.size.width)
      : metadata.size;
}

/// Tegakkan foto sesuai EXIF, perkecil (sisi terpanjang [maxSide] px), dan
/// encode ulang ke JPEG agar upload ke server ringan.
/// Dijalankan di isolate terpisah lewat `compute(prepareFaceJpeg, bytes)`.
Uint8List prepareFaceJpeg(Uint8List raw, {int maxSide = 960}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  var oriented = img.bakeOrientation(decoded);
  if (oriented.width > maxSide || oriented.height > maxSide) {
    oriented = oriented.width >= oriented.height
        ? img.copyResize(
            oriented,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            oriented,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  return img.encodeJpg(oriented, quality: 88);
}
