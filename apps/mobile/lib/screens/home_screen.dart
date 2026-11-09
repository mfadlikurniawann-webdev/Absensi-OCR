import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'admin_dashboard_screen.dart';
import 'admin_login_screen.dart';
import 'attendance_result_screen.dart';
import 'face_capture_screen.dart';
import 'register_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Timer _clock;
  DateTime _now = DateTime.now();
  bool? _serverOnline; // null = sedang dicek

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
    AppSettings.instance.addListener(_checkServer);
    _checkServer();
  }

  @override
  void dispose() {
    _clock.cancel();
    AppSettings.instance.removeListener(_checkServer);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() => _serverOnline = null);
    try {
      await AppSettings.instance.api().health();
      if (mounted) setState(() => _serverOnline = true);
    } on ApiException {
      if (mounted) setState(() => _serverOnline = false);
    }
  }

  Future<void> _startAttendance() async {
    while (true) {
      if (!mounted) return;
      final jpeg = await FaceCaptureScreen.open(context, title: 'Absen');
      if (jpeg == null || !mounted) return;

      AttendanceResult? result;
      String? error;
      try {
        result = await runWithProgress(
          context,
          'Mencocokkan wajah...',
          () => AppSettings.instance.api().submitAttendance(jpeg),
        );
      } on ApiException catch (e) {
        error = e.message;
      }
      if (!mounted) return;

      final retry = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AttendanceResultScreen(result: result, error: error),
        ),
      );
      if (retry != true) return;
    }
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openAdmin() => _push(
    AppSettings.instance.isAdminLoggedIn
        ? const AdminDashboardScreen()
        : const AdminLoginScreen(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const _Wordmark(),
                        const Spacer(),
                        RoundIconButton(
                          icon: Icons.tune,
                          tooltip: 'Server',
                          onPressed: () => _push(const SettingsScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _serverPill(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      formatJam(_now).substring(0, 5),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 96,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatTanggal(_now).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 32),
                    _ScanCard(onTap: _startAttendance),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniCard(
                            color: AppColors.lilac,
                            icon: Icons.person_add_alt_1_outlined,
                            label: 'Daftar\nwajah',
                            onTap: () => _push(const RegisterScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniCard(
                            color: AppColors.peach,
                            icon: Icons.insights_outlined,
                            label: 'Rekap\nadmin',
                            onTap: _openAdmin,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _serverPill() => switch (_serverOnline) {
    true => const StatusPill(label: 'server online', dotColor: Colors.green),
    false => StatusPill(
      label: 'server offline · ketuk untuk cek',
      dotColor: AppColors.danger,
      onTap: _checkServer,
    ),
    null => const StatusPill(label: 'menghubungkan...', dotColor: Colors.grey),
  };
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'absensi',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1,
          ),
        ),
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(left: 3, bottom: 2),
          decoration: const BoxDecoration(
            color: AppColors.lime,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      color: AppColors.ink,
      height: 196,
      onTap: onTap,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.face_outlined,
                  color: AppColors.lime,
                  size: 26,
                ),
              ),
              const Spacer(),
              const ArrowBadge(
                background: AppColors.lime,
                foreground: AppColors.ink,
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Scan wajah',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'kedip sekali, beres.',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      color: color,
      height: 148,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 26),
              const Spacer(),
              const Icon(Icons.arrow_outward, size: 20),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
