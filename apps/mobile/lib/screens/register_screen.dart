import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'face_capture_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _npmCtrl = TextEditingController();
  Uint8List? _photo;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _npmCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    FocusScope.of(context).unfocus();
    final jpeg = await FaceCaptureScreen.open(
      context,
      title: 'Foto wajah',
      requireBlink: false,
    );
    if (jpeg != null && mounted) setState(() => _photo = jpeg);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final photo = _photo;
    if (photo == null) {
      showSnack(context, 'Ambil foto wajah dulu.', error: true);
      return;
    }
    try {
      await runWithProgress(
        context,
        'Mendaftarkan...',
        () => AppSettings.instance.api().registerFace(
          name: _nameCtrl.text.trim(),
          npm: _npmCtrl.text.trim(),
          jpeg: photo,
        ),
      );
      if (!mounted) return;
      showSnack(context, '${_nameCtrl.text.trim()} terdaftar.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Foto tanpa wajah (422) perlu diambil ulang.
      if (e.statusCode == 422) setState(() => _photo = null);
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar wajah')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _PhotoCard(photo: _photo, onTap: _takePhoto),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
                decoration: const InputDecoration(labelText: 'Nama'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _npmCtrl,
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(50)],
                decoration: const InputDecoration(labelText: 'NPM'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 28),
              FilledButton(onPressed: _submit, child: const Text('Daftar')),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.photo, required this.onTap});

  final Uint8List? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null;
    return BentoCard(
      color: hasPhoto ? AppColors.lime : AppColors.lilac,
      onTap: onTap,
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: 72,
              height: 72,
              color: Colors.white.withValues(alpha: 0.6),
              child: hasPhoto
                  ? Image.memory(photo!, fit: BoxFit.cover)
                  : const Icon(Icons.face_outlined, size: 34),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPhoto ? 'Foto siap' : 'Foto wajah',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  hasPhoto ? 'ketuk untuk ulangi' : 'ketuk untuk ambil',
                  style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          const ArrowBadge(),
        ],
      ),
    );
  }
}
