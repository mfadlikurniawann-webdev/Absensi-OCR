/// Model data yang dipertukarkan dengan backend Flask (`/api/...`).
library;

String? _str(Object? v) => v?.toString();
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class HealthInfo {
  HealthInfo({
    required this.version,
    required this.publicRegister,
    this.serverTime,
  });

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
    version: _str(j['version']) ?? '-',
    publicRegister: j['public_register'] != false,
    serverTime: _str(j['server_time']),
  );

  final String version;
  final bool publicRegister;
  final String? serverTime;
}

class AttendanceResult {
  AttendanceResult({
    required this.recognized,
    required this.alreadyRecorded,
    required this.message,
    this.name,
    this.npm,
    this.waktu,
  });

  factory AttendanceResult.fromJson(Map<String, dynamic> j) => AttendanceResult(
    recognized: j['recognized'] == true,
    alreadyRecorded: j['already_recorded'] == true,
    message: _str(j['message']) ?? '',
    name: _str(j['name']),
    npm: _str(j['npm']),
    waktu: _str(j['waktu']),
  );

  final bool recognized;
  final bool alreadyRecorded;
  final String message;
  final String? name;
  final String? npm;
  final String? waktu;
}

class AdminLogin {
  AdminLogin({required this.token, required this.expiresIn});

  factory AdminLogin.fromJson(Map<String, dynamic> j) => AdminLogin(
    token: _str(j['token']) ?? '',
    expiresIn: Duration(seconds: _int(j['expires_in'])),
  );

  final String token;
  final Duration expiresIn;
}

class AdminSummary {
  AdminSummary({
    required this.date,
    required this.totalUsers,
    required this.totalAttendance,
    required this.attendanceToday,
    required this.presentToday,
  });

  factory AdminSummary.fromJson(Map<String, dynamic> j) => AdminSummary(
    date: _str(j['date']) ?? '',
    totalUsers: _int(j['total_users']),
    totalAttendance: _int(j['total_attendance']),
    attendanceToday: _int(j['attendance_today']),
    presentToday: _int(j['present_today']),
  );

  final String date;
  final int totalUsers;
  final int totalAttendance;
  final int attendanceToday;
  final int presentToday;
}

class AttendanceRecord {
  AttendanceRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.npm,
    required this.waktu,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    id: _int(j['id']),
    userId: _int(j['user_id']),
    name: _str(j['name']) ?? '-',
    npm: _str(j['npm']) ?? '-',
    waktu: _str(j['waktu']) ?? '',
  );

  final int id;
  final int userId;
  final String name;
  final String npm;
  final String waktu;
}

class RegisteredUser {
  RegisteredUser({
    required this.id,
    required this.name,
    required this.npm,
    required this.totalAttendance,
    this.lastAttendance,
  });

  factory RegisteredUser.fromJson(Map<String, dynamic> j) => RegisteredUser(
    id: _int(j['id']),
    name: _str(j['name']) ?? '-',
    npm: _str(j['npm']) ?? '-',
    totalAttendance: _int(j['total_attendance']),
    lastAttendance: _str(j['last_attendance']),
  );

  final int id;
  final String name;
  final String npm;
  final int totalAttendance;
  final String? lastAttendance;
}
