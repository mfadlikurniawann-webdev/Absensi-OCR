import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../app_theme.dart';
import '../services/face_image_utils.dart';
import '../widgets/face_guide_painter.dart';
import '../widgets/ui.dart';

/// Kamera depan dengan deteksi wajah real-time (Google ML Kit, on-device).
///
/// - [requireBlink] = true  : setelah wajah pas di oval, pengguna harus
///   berkedip (cek liveness sederhana), lalu foto diambil otomatis.
/// - [requireBlink] = false : tombol shutter aktif ketika wajah pas.
///
/// Mengembalikan JPEG lewat `Navigator.pop`, atau null bila batal.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({
    super.key,
    required this.title,
    this.requireBlink = true,
  });

  final String title;
  final bool requireBlink;

  static Future<Uint8List?> open(
    BuildContext context, {
    required String title,
    bool requireBlink = true,
  }) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) =>
            FaceCaptureScreen(title: title, requireBlink: requireBlink),
      ),
    );
  }

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

enum _Stage { starting, searching, adjusting, blink, ready, capturing }

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with WidgetsBindingObserver {
  // Ambang posisi wajah, relatif terhadap ukuran gambar tegak. Acuan tengahnya
  // (0.5, 0.5) sama dengan pusat oval di preview.
  static const _minFaceWidth = 0.30;
  static const _maxFaceWidth = 0.80;
  static const _maxCenterOffset = 0.12;
  static const _maxYaw = 15.0;
  static const _maxRoll = 15.0;
  static const _maxPitch = 20.0;
  static const _stableFramesNeeded = 4;
  static const _eyeClosedThreshold = 0.25;
  static const _eyeOpenThreshold = 0.65;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // probabilitas mata terbuka (deteksi kedip)
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  CameraController? _controller;
  CameraDescription? _camera;
  bool _initializing = false;
  bool _processing = false;
  bool _capturing = false;
  String? _error;

  _Stage _stage = _Stage.starting;
  String _message = '';
  int _stableFrames = 0;
  bool _eyesClosedSeen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera(rebuild: false);
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Dialog izin kamera membuat app "inactive"; abaikan selama inisialisasi.
    if (_initializing || _capturing) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _error == null) {
      _initCamera();
    }
  }

  // ------------------------------------------------------------------ kamera

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('Kamera tidak ditemukan.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      // Simpan segera agar ikut di-dispose bila inisialisasi gagal.
      _camera = camera;
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await _disposeCamera(rebuild: false);
        return;
      }
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException {
        // Tidak semua perangkat mendukung; foto tetap ditegakkan lewat EXIF.
      }
      _resetLiveness();
      await controller.startImageStream(_onFrame);
      _update(_Stage.searching, 'Arahkan wajah ke kamera');
    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.code} ${e.description}');
      await _disposeCamera(rebuild: false);
      _setError(_cameraErrorMessage(e.code, e.description));
    } on PlatformException catch (e) {
      debugPrint('PlatformException kamera: ${e.code} ${e.message}');
      await _disposeCamera(rebuild: false);
      _setError(_cameraErrorMessage(e.code, e.message));
    } catch (e) {
      debugPrint('Kamera gagal dibuka: $e');
      await _disposeCamera(rebuild: false);
      _setError(_cameraErrorMessage('unknown', null));
    } finally {
      _initializing = false;
    }
  }

  Future<void> _disposeCamera({bool rebuild = true}) async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (rebuild && mounted) setState(() {});
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    try {
      // dispose() melempar ulang error bila initialize() sebelumnya gagal.
      await controller.dispose();
    } catch (e) {
      debugPrint('Gagal menutup kamera: $e');
    }
  }

  String _cameraErrorMessage(String code, String? description) {
    final lowerCode = code.toLowerCase();
    if (lowerCode.contains('denied') ||
        lowerCode.contains('permission') ||
        lowerCode.contains('restricted')) {
      return 'Izin kamera ditolak. Aktifkan di pengaturan HP.';
    }
    if ((description ?? '').contains('Available cameras: 0')) {
      return 'Kamera tidak ditemukan.';
    }
    return 'Kamera tidak bisa dibuka. Tutup aplikasi lain yang memakai kamera.';
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  // ----------------------------------------------------------- deteksi wajah

  void _onFrame(CameraImage image) {
    if (_processing || _capturing) return;
    _processing = true;
    _processFrame(image).whenComplete(() => _processing = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    final controller = _controller;
    final camera = _camera;
    if (controller == null || camera == null) return;
    final input = cameraImageToInputImage(
      image,
      camera,
      controller.value.deviceOrientation,
    );
    if (input == null || input.metadata == null) return;
    final List<Face> faces;
    try {
      faces = await _detector.processImage(input);
    } catch (e) {
      debugPrint('Deteksi wajah gagal: $e');
      return;
    }
    if (!mounted || _capturing) return;
    _evaluate(faces, uprightImageSize(input.metadata!));
  }

  void _evaluate(List<Face> faces, Size imageSize) {
    if (faces.isEmpty) {
      _resetLiveness();
      _update(_Stage.searching, 'Arahkan wajah ke kamera');
      return;
    }
    if (faces.length > 1) {
      _resetLiveness();
      _update(_Stage.adjusting, 'Pastikan hanya satu wajah');
      return;
    }

    final face = faces.first;
    final box = face.boundingBox;
    final widthRatio = box.width / imageSize.width;
    final dx = (box.center.dx / imageSize.width - 0.5).abs();
    final dy = (box.center.dy / imageSize.height - 0.5).abs();
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final roll = (face.headEulerAngleZ ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();

    String? problem;
    if (widthRatio < _minFaceWidth) {
      problem = 'Dekatkan wajah';
    } else if (widthRatio > _maxFaceWidth) {
      problem = 'Mundur sedikit';
    } else if (dx > _maxCenterOffset || dy > _maxCenterOffset) {
      problem = 'Posisikan wajah di tengah';
    } else if (yaw > _maxYaw || roll > _maxRoll || pitch > _maxPitch) {
      problem = 'Hadap lurus ke kamera';
    }
    if (problem != null) {
      _resetLiveness();
      _update(_Stage.adjusting, problem);
      return;
    }

    _stableFrames++;
    if (_stableFrames < _stableFramesNeeded) {
      _update(_Stage.adjusting, 'Tahan posisi');
      return;
    }

    if (!widget.requireBlink) {
      _update(_Stage.ready, 'Wajah siap');
      return;
    }

    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) {
      _update(_Stage.blink, 'Kedipkan mata');
      return;
    }
    if (!_eyesClosedSeen) {
      if (left < _eyeClosedThreshold && right < _eyeClosedThreshold) {
        _eyesClosedSeen = true;
      }
      _update(_Stage.blink, 'Kedipkan mata');
    } else if (left > _eyeOpenThreshold && right > _eyeOpenThreshold) {
      _capture(); // mata tertutup lalu terbuka lagi = kedip terdeteksi
    }
  }

  void _resetLiveness() {
    _stableFrames = 0;
    _eyesClosedSeen = false;
  }

  void _update(_Stage stage, String message) {
    if (!mounted || (_stage == stage && _message == message)) return;
    setState(() {
      _stage = stage;
      _message = message;
    });
  }

  // ------------------------------------------------------------- ambil foto

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || controller == null) return;
    _capturing = true;
    _update(_Stage.capturing, 'Memproses...');
    HapticFeedback.mediumImpact();
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      final raw = await file.readAsBytes();
      final jpeg = await compute(prepareFaceJpeg, raw);
      unawaited(File(file.path).delete().then((_) {}, onError: (_) {}));
      if (!mounted) return;
      Navigator.of(context).pop(jpeg);
    } catch (e) {
      debugPrint('Gagal mengambil foto: $e');
      _capturing = false;
      _resetLiveness();
      _update(_Stage.searching, 'Gagal mengambil foto, coba lagi');
      try {
        if (!controller.value.isStreamingImages) {
          await controller.startImageStream(_onFrame);
        }
      } catch (_) {}
    }
  }

  // --------------------------------------------------------------------- UI

  bool get _positive =>
      _stage == _Stage.blink ||
      _stage == _Stage.ready ||
      _stage == _Stage.capturing;

  Color get _guideColor => _positive ? AppColors.lime : Colors.white;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        appBar: AppBar(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: Text(
            widget.title,
            style: const TextStyle(
              fontFamily: appFont,
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: RoundIconButton(
                icon: Icons.close,
                tooltip: 'Tutup',
                background: Colors.white12,
                foreground: Colors.white,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _error != null ? _buildError() : _buildCamera(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.lime,
                foregroundColor: AppColors.ink,
                minimumSize: const Size(160, 52),
              ),
              onPressed: () {
                setState(() => _error = null);
                _initCamera();
              },
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: ready
                  ? _buildPreview(controller)
                  : const CircularProgressIndicator(color: AppColors.lime),
            ),
          ),
        ),
        const SizedBox(height: 20),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: _positive ? AppColors.lime : Colors.white,
          ),
          child: Text(
            _message.isEmpty ? 'Menyiapkan kamera...' : _message,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (!widget.requireBlink) ...[
          const SizedBox(height: 20),
          _ShutterButton(enabled: _stage == _Stage.ready, onPressed: _capture),
        ],
        const SizedBox(height: 28),
      ],
    );
  }

  /// Preview utuh (tanpa crop) di tengah, dengan oval di pusat preview.
  Widget _buildPreview(CameraController controller) {
    // aspectRatio kamera berorientasi landscape; di portrait dibalik.
    return AspectRatio(
      aspectRatio: 1 / controller.value.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),
            CustomPaint(painter: FaceGuidePainter(color: _guideColor)),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 78,
        height: 78,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? Colors.white : Colors.white24,
            width: 3,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? AppColors.lime : Colors.white24,
          ),
        ),
      ),
    );
  }
}
