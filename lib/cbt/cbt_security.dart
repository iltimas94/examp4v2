// ==================== Keamanan alur CBT (anti-cheat ExBrowser) ====================
// Pre-locking, FLAG_SECURE, monitor fokus jendela (lock overlay + kode admin),
// dan brightness — mengikuti pola ExamContentScreen pada main.dart.
import 'dart:async';

import 'package:examp4/main.dart' show ActivityMonitorService, NativeSecureFlagService;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cbt_api.dart' show kCbtNativeLink;

/// Satu kontroler untuk SELURUH alur CBT native (login -> info -> ujian ->
/// selesai). Dipanggil `mulai()` di initState layar login; `akhiriSesi()` hanya
/// saat siswa benar-benar keluar dari alur CBT kembali ke Daftar Ujian.
class CbtSecurityController {
  CbtSecurityController._();
  static final CbtSecurityController instance = CbtSecurityController._();

  static const String _spreadsheetId = '1vSlsnJlmJZCzPnyb6Qp13J4ie-5wplng6ZysreGTsaY';
  static const String _gidSesi = '1494571347';
  static const String _gidLockStatus = '522874477';
  static const String _gidKodeAdmin = '1460373020';
  static const brightnessChannel =
      MethodChannel('com.example.exam_browser/brightness');

  bool lockEnabled = false;
  String? lockReason;
  int lockCount = 0;
  String? adminCode;
  bool fetchingAdmin = false;
  String adminError = '';
  final TextEditingController adminController = TextEditingController();

  /// Listen utk rebuild overlay kunci (setState dari layar mana pun).
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool _mulai = false;
  StreamSubscription? _sub;

  Future<void> _setBrightness(double brightness) async {
    try {
      await brightnessChannel.invokeMethod(
          'setBrightness', {'brightness': brightness});
    } catch (e) {
      debugPrint('Gagal atur brightness: $e');
    }
  }

  /// Dipanggil sekali saat masuk alur CBT (initState CbtLoginScreen).
  Future<void> mulai() async {
    if (_mulai) return;
    _mulai = true;
    lockEnabled = await _fetchLockSystemStatus();
    await fetchAdminCode();
    await _simpanSessionId();
    final prefs = await SharedPreferences.getInstance();
    lockCount = prefs.getInt('lockCount') ?? 0;
    if (lockEnabled) {
      await prefs.setBool('isAppLocked', true);
      await prefs.setString('lastExamUrl', kCbtNativeLink);
      await prefs.setString(
          'lastLockReason', 'Aplikasi ditutup tidak wajar saat sesi ujian.');
      debugPrint('PRE-LOCKING CBT NATIVE AKTIF.');
    }
    await NativeSecureFlagService.setSecureFlag();
    await _setBrightness(0.4);
    await ActivityMonitorService.initializeMonitoring();
    _sub = ActivityMonitorService.lockReasonStream.listen(_onLock);
  }

  Future<void> _onLock(String? reason) async {
    if (reason == null) return;
    if (!lockEnabled) {
      debugPrint('Sistem kunci OFF pada sesi ini. Penguncian layar dibatalkan.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    lockCount = (prefs.getInt('lockCount') ?? 0) + 1;
    await prefs.setInt('lockCount', lockCount);
    await prefs.setBool('isAppLocked', true);
    await prefs.setString('lastExamUrl', kCbtNativeLink);
    await prefs.setString('lastLockReason', reason);
    await prefs.setInt(
        'lockTimestamp', DateTime.now().millisecondsSinceEpoch);
    lockReason = reason;
    adminError = '';
    adminController.clear();
    revision.value++;
  }

  Future<bool> _fetchLockSystemStatus() async {
    try {
      final r = await http
          .get(Uri.parse(
              'https://docs.google.com/spreadsheets/d/$_spreadsheetId/export?format=csv&gid=$_gidLockStatus'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) return r.body.trim().toUpperCase() == 'ON';
      return true; // fallback aman: anggap ON
    } catch (e) {
      debugPrint('Gagal ambil status sistem kunci, anggap ON: $e');
      return true;
    }
  }

  Future<void> fetchAdminCode() async {
    fetchingAdmin = true;
    revision.value++;
    try {
      final r = await http.get(Uri.parse(
          'https://docs.google.com/spreadsheets/d/$_spreadsheetId/export?format=csv&gid=$_gidKodeAdmin'));
      if (r.statusCode == 200) adminCode = r.body.trim();
    } catch (e) {
      debugPrint('Failed to fetch admin code: $e');
    } finally {
      fetchingAdmin = false;
      revision.value++;
    }
  }

  Future<void> _simpanSessionId() async {
    try {
      final r = await http.get(Uri.parse(
          'https://docs.google.com/spreadsheets/d/$_spreadsheetId/export?format=csv&gid=$_gidSesi'));
      if (r.statusCode == 200 && r.body.trim().isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lockSessionId', r.body.trim());
      }
    } catch (e) {
      debugPrint('Gagal simpan sessionId: $e');
    }
  }

  /// Bungkus isi layar: saat terkunci, overlay menutupi seluruh layar
  /// (pola isActuallyLocked pada ExamContentScreen).
  Widget wrap(BuildContext context, Widget child) {
    return ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (context, _, __) {
        if (lockReason == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Container(
                color: Colors.black.withValues(alpha: 0.90),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock, color: Colors.red, size: 80),
                        const SizedBox(height: 20),
                        const Text('Aplikasi Terkunci!',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 15),
                        const Text(
                          'Silakan hubungi pengawas atau masukkan kode admin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(height: 30),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40.0),
                          child: TextField(
                            controller: adminController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            style:
                                const TextStyle(color: Colors.white, fontSize: 18),
                            decoration: InputDecoration(
                              labelText: 'Kode Admin',
                              labelStyle:
                                  const TextStyle(color: Colors.white70),
                              enabledBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54)),
                              focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue)),
                              errorText:
                                  adminError.isNotEmpty ? adminError : null,
                              errorStyle: const TextStyle(
                                  color: Colors.orangeAccent, fontSize: 14),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: fetchingAdmin ? null : attemptUnlock,
                              child: fetchingAdmin
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3))
                                  : const Text('Buka Kunci'),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white),
                              onPressed: fetchingAdmin ? null : fetchAdminCode,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(top: 15.0),
                          child: Column(
                            children: [
                              Text(lockReason!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.yellowAccent,
                                      fontSize: 16,
                                      fontStyle: FontStyle.italic)),
                              const SizedBox(height: 10),
                              Text('Pelanggaran Sesi Ini: $lockCount',
                                  style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Kunci untuk dialog konfirmasi keluar: kode admin siap pakai (fetch bila
  /// belum tersedia). Mengembalikan null bila kode tidak bisa didapat —
  /// pemanggil (konfirmasiKunci) lalu jatuh ke konfirmasi tanpa password.
  Future<String?> kodeAdminSiap() async {
    if (adminCode == null || adminCode!.isEmpty) await fetchAdminCode();
    return (adminCode == null || adminCode!.isEmpty) ? null : adminCode;
  }

  /// Coba buka kunci dengan kode admin (porting _attemptUnlock).
  Future<void> attemptUnlock() async {
    if (adminCode == null) {
      await fetchAdminCode();
      if (adminCode == null) {
        adminError = 'Gagal verifikasi. Coba lagi.';
        revision.value++;
        return;
      }
    }
    if (adminController.text == adminCode) {
      await clearLockData();
      ActivityMonitorService.requestUnlock();
      lockReason = null;
      adminError = '';
      adminController.clear();
      revision.value++;
      await Future.delayed(const Duration(milliseconds: 500));
      await ActivityMonitorService.initializeMonitoring();
      debugPrint('Activity Monitoring diinisialisasi ulang setelah unlock.');
    } else {
      adminError = 'Kode admin salah.';
      adminController.clear();
      revision.value++;
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> clearLockData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isAppLocked');
    await prefs.remove('lastExamUrl');
    await prefs.remove('lastLockReason');
    await prefs.remove('lockTimestamp');
    await prefs.remove('lockSessionId');
    // lockCount dipertahankan
  }

  /// Keluar TOTAL dari alur CBT kembali ke Daftar Ujian (_exitExamMode).
  Future<void> akhiriSesi() async {
    await _setBrightness(-1.0);
    await clearLockData();
    await ActivityMonitorService.stopMonitoring();
    await NativeSecureFlagService.clearSecureFlag();
    await _sub?.cancel();
    _sub = null;
    lockReason = null;
    _mulai = false;
    revision.value++;
  }

  void dispose() {
    _sub?.cancel();
    adminController.dispose();
  }
}

