import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtrl = TextEditingController(
    text: AppSettings.instance.baseUrl,
  );
  bool _testing = false;
  bool? _testOk;
  String? _testMessage;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = AppSettings.normalizeUrl(_urlCtrl.text);
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _testOk = null;
    });
    try {
      await ApiService(baseUrl: url).health();
      _testOk = true;
      _testMessage = 'terhubung';
    } on ApiException catch (e) {
      _testOk = false;
      _testMessage = e.message;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = AppSettings.normalizeUrl(_urlCtrl.text);
    if (url.isEmpty) {
      showSnack(context, 'Alamat server wajib diisi.', error: true);
      return;
    }
    if (url != AppSettings.instance.baseUrl) {
      // Token admin milik server lama tidak berlaku di server baru.
      await AppSettings.instance.clearAdminToken();
    }
    await AppSettings.instance.setBaseUrl(url);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _testOk;
    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Alamat server',
                hintText: 'http://192.168.1.10:5000',
              ),
            ),
            if (ok != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: _testMessage ?? '',
                  dotColor: ok ? Colors.green : AppColors.danger,
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(onPressed: _save, child: const Text('Simpan')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _testing ? null : _test,
              child: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tes koneksi'),
            ),
          ],
        ),
      ),
    );
  }
}
