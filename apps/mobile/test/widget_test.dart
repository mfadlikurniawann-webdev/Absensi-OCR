import 'package:absensi_wajah/models/models.dart';
import 'package:absensi_wajah/services/app_settings.dart';
import 'package:absensi_wajah/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings.normalizeUrl', () {
    test('menambah http:// dan membuang slash akhir', () {
      expect(
        AppSettings.normalizeUrl(' 192.168.1.10:5000/ '),
        'http://192.168.1.10:5000',
      );
      expect(
        AppSettings.normalizeUrl('https://absensi.id//'),
        'https://absensi.id',
      );
      expect(AppSettings.normalizeUrl('HTTP://Host:5000'), 'HTTP://Host:5000');
      expect(AppSettings.normalizeUrl('   '), '');
    });
  });

  group('format tanggal', () {
    test('formatTanggal & formatJam', () {
      final d = DateTime(2026, 11, 9, 8, 5, 3);
      expect(formatTanggal(d), 'Senin, 9 November 2026');
      expect(formatJam(d), '08:05:03');
      expect(isoDate(d), '2026-11-09');
    });

    test('formatWaktuServer', () {
      expect(
        formatWaktuServer('2025-09-29 11:15:57'),
        '29 September 2025, 11:15',
      );
      expect(formatWaktuServer(null), '-');
      expect(formatWaktuServer('bukan tanggal'), 'bukan tanggal');
    });

    test('initials', () {
      expect(initials('Muhamad Hibban Ramadhan'), 'MH');
      expect(initials('desta'), 'D');
      expect(initials('  '), '?');
    });
  });

  group('parsing respons API', () {
    test('AttendanceResult dikenali', () {
      final r = AttendanceResult.fromJson({
        'recognized': true,
        'already_recorded': false,
        'name': 'Desta',
        'npm': '2315061006',
        'waktu': '2026-11-09 08:00:00',
        'message': 'Absensi berhasil dicatat untuk Desta.',
      });
      expect(r.recognized, isTrue);
      expect(r.alreadyRecorded, isFalse);
      expect(r.name, 'Desta');
    });

    test('AttendanceResult tidak dikenali', () {
      final r = AttendanceResult.fromJson({
        'recognized': false,
        'message': 'Wajah tidak dikenali.',
      });
      expect(r.recognized, isFalse);
      expect(r.name, isNull);
    });

    test('AdminSummary & RegisteredUser', () {
      final s = AdminSummary.fromJson({
        'date': '2026-11-09',
        'total_users': 2,
        'total_attendance': 46,
        'attendance_today': 3,
        'present_today': 2,
      });
      expect(s.presentToday, 2);
      final u = RegisteredUser.fromJson({
        'id': 12,
        'name': 'Radhit',
        'npm': '2315061002',
        'total_attendance': 5,
      });
      expect(u.lastAttendance, isNull);
      expect(u.totalAttendance, 5);
    });
  });
}
