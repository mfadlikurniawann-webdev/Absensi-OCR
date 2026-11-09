import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Hasil absen. `Navigator.pop(true)` = coba lagi.
class AttendanceResultScreen extends StatelessWidget {
  const AttendanceResultScreen({super.key, this.result, this.error});

  final AttendanceResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final recognized = error == null && r != null && r.recognized;

    final (Color bg, IconData icon, String title, String detail) = switch (r) {
      _ when error != null => (
        AppColors.peach,
        Icons.close_rounded,
        'Ups, gagal',
        error!,
      ),
      AttendanceResult(recognized: true, alreadyRecorded: true, :final waktu) =>
        (
          AppColors.lilac,
          Icons.done_all_rounded,
          'Udah absen',
          'tercatat jam ${formatJamServer(waktu)}',
        ),
      AttendanceResult(recognized: true, :final waktu) => (
        AppColors.lime,
        Icons.check_rounded,
        'Hadir!',
        'jam ${formatJamServer(waktu)}',
      ),
      _ => (
        AppColors.peach,
        Icons.question_mark_rounded,
        'Belum dikenal',
        'daftarin wajah dulu, ya.',
      ),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: bg, size: 40),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 16),
                if (recognized) ...[
                  Text(
                    r.name ?? '-',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.npm ?? '-'}  ·  $detail',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.ink.withValues(alpha: 0.65),
                    ),
                  ),
                ] else
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 17,
                      color: AppColors.ink.withValues(alpha: 0.7),
                    ),
                  ),
                const Spacer(flex: 2),
                if (recognized)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Selesai'),
                  )
                else ...[
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Coba lagi'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Kembali'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
