import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'admin_login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _searchCtrl = TextEditingController();

  AdminSummary? _summary;
  List<AttendanceRecord> _records = const [];
  List<RegisteredUser> _users = const [];
  DateTime? _date = DateTime.now();
  int _tab = 0; // 0 = absensi, 1 = pengguna
  bool _loading = true;
  String? _error;

  ApiService get _api => AppSettings.instance.api();
  String? get _query =>
      _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim();
  String? get _dateParam => _date == null ? null : isoDate(_date!);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- data

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _api;
      final results = await Future.wait([
        api.summary(),
        api.attendance(date: _dateParam, query: _query),
        api.users(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as AdminSummary;
        _records = results[1] as List<AttendanceRecord>;
        _users = results[2] as List<RegisteredUser>;
      });
    } on ApiException catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAttendance() async {
    try {
      final records = await _api.attendance(date: _dateParam, query: _query);
      if (mounted) setState(() => _records = records);
    } on ApiException catch (e) {
      _handleError(e);
    }
  }

  Future<void> _handleError(ApiException e) async {
    if (!mounted) return;
    if (e.isUnauthorized) {
      await AppSettings.instance.clearAdminToken();
      if (!mounted) return;
      showSnack(context, 'Sesi habis, silakan masuk lagi.', error: true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      );
      return;
    }
    setState(() => _error = e.message);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    _loadAttendance();
  }

  Future<void> _deleteUser(RegisteredUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus ${user.name}?',
      message: 'Data wajah dan riwayat absensinya ikut terhapus.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await runWithProgress(
        context,
        'Menghapus...',
        () => _api.deleteUser(user.id),
      );
      _loadAll();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        _handleError(e);
      } else {
        showSnack(context, e.message, error: true);
      }
    }
  }

  Future<void> _exportCsv(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final bytes = await runWithProgress(
        context,
        'Menyiapkan CSV...',
        () => _api.exportCsv(date: _dateParam, query: _query),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/absensi_${_dateParam ?? 'semua'}.csv');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Absensi ${_dateParam ?? ''}'.trim(),
          sharePositionOrigin: origin,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        _handleError(e);
      } else {
        showSnack(context, e.message, error: true);
      }
    } on FileSystemException catch (e) {
      if (mounted) showSnack(context, 'Gagal menyimpan file: ${e.message}');
    }
  }

  Future<void> _logout() async {
    await AppSettings.instance.clearAdminToken();
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rekap'),
        actions: [
          Builder(
            builder: (btnContext) => RoundIconButton(
              icon: Icons.ios_share,
              tooltip: 'Export CSV',
              onPressed: () => _exportCsv(btnContext),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: RoundIconButton(
              icon: Icons.logout,
              tooltip: 'Keluar',
              onPressed: _logout,
            ),
          ),
        ],
      ),
      body: _loading && _summary == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (_error != null) _buildError(),
                  if (_summary != null) _buildStats(_summary!),
                  const SizedBox(height: 16),
                  _SegmentedPill(
                    labels: const ['Absensi', 'Pengguna'],
                    selected: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 0) ..._attendanceItems() else ..._userItems(),
                ],
              ),
            ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StatusPill(
        label: '${_error!} · ketuk untuk muat ulang',
        dotColor: AppColors.danger,
        onTap: _loadAll,
      ),
    );
  }

  Widget _buildStats(AdminSummary summary) {
    return Row(
      children: [
        Expanded(
          child: BentoCard(
            color: AppColors.ink,
            height: 124,
            child: _StatContent(
              value: '${summary.presentToday}/${summary.totalUsers}',
              label: 'hadir hari ini',
              valueColor: AppColors.lime,
              labelColor: Colors.white60,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BentoCard(
            color: AppColors.lilac,
            height: 124,
            child: _StatContent(
              value: '${summary.totalAttendance}',
              label: 'total absensi',
              valueColor: AppColors.ink,
              labelColor: AppColors.ink.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _attendanceItems() {
    return [
      TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadAttendance(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Cari nama atau NPM',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    _loadAttendance();
                  },
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(_date == null ? 'Semua tanggal' : formatTanggal(_date!)),
          onPressed: _pickDate,
          onDeleted: _date == null
              ? null
              : () {
                  setState(() => _date = null);
                  _loadAttendance();
                },
        ),
      ),
      const SizedBox(height: 10),
      if (_records.isEmpty)
        const _Empty(text: 'Belum ada yang absen')
      else
        for (final r in _records)
          _RowCard(
            title: r.name,
            subtitle: r.npm,
            trailing: _TimeTag(
              _date == null
                  ? formatWaktuServer(r.waktu)
                  : formatJamServer(r.waktu),
            ),
          ),
    ];
  }

  List<Widget> _userItems() {
    if (_users.isEmpty) return const [_Empty(text: 'Belum ada pengguna')];
    return [
      for (final u in _users)
        _RowCard(
          title: u.name,
          subtitle: '${u.npm}  ·  ${u.totalAttendance}x absen',
          trailing: RoundIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Hapus',
            background: AppColors.bg,
            size: 40,
            onPressed: () => _deleteUser(u),
          ),
        ),
    ];
  }
}

class _StatContent extends StatelessWidget {
  const _StatContent({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.labelColor,
  });

  final String value;
  final String label;
  final Color valueColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        FittedBox(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
      ],
    );
  }
}

/// Tab berbentuk pill dengan pilihan aktif berwarna hitam.
class _SegmentedPill extends StatelessWidget {
  const _SegmentedPill({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: AppColors.card,
        shape: StadiumBorder(),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: ShapeDecoration(
                    color: i == selected ? AppColors.ink : Colors.transparent,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: i == selected ? Colors.white : AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _TimeTag extends StatelessWidget {
  const _TimeTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const ShapeDecoration(
        color: AppColors.lime,
        shape: StadiumBorder(),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
    );
  }
}
