import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// --- KELAS MODEL ---
class Exam {
  final String image, mapel, waktu, link;
  Exam({required this.image, required this.mapel, required this.waktu, required this.link});
}

// --- WIDGET VISUAL PENGGANTI GAMBAR (Efisien & Cepat) ---
class SubjectThumbnail extends StatelessWidget {
  final String mapel;
  const SubjectThumbnail({super.key, required this.mapel});

  IconData _getIcon() {
    final name = mapel.toLowerCase();
    if (name.contains('matematika')) return Icons.calculate;
    if (name.contains('ipa') || name.contains('biologi') || name.contains('fisika') || name.contains('kimia')) return Icons.science;
    if (name.contains('bahasa')) return Icons.translate;
    if (name.contains('inggris')) return Icons.language;
    if (name.contains('ips') || name.contains('sejarah') || name.contains('geografi') || name.contains('ekonomi')) return Icons.public;
    if (name.contains('agama') || name.contains('budi pekerti')) return Icons.menu_book;
    if (name.contains('olahraga') || name.contains('pjok') || name.contains('jasmani')) return Icons.sports_soccer;
    if (name.contains('seni') || name.contains('prakarya') || name.contains('budaya')) return Icons.palette;
    if (name.contains('tik') || name.contains('informatika') || name.contains('komputer')) return Icons.computer;
    if (name.contains('pkn') || name.contains('pancasila') || name.contains('kewarganegaraan')) return Icons.gavel;
    if (name.contains('bimbingan') || name.contains('bk')) return Icons.psychology;
    return Icons.assignment; // Default icon
  }

  List<Color> _getGradient() {
    final name = mapel.toLowerCase();
    // Gunakan hash dari nama mata pelajaran agar warna unik tapi konsisten
    final int hash = mapel.hashCode.abs();
    
    // Daftar kombinasi warna yang cantik
    final List<List<Color>> gradients = [
      [Colors.blue, Colors.blueAccent],
      [Colors.green, Colors.teal],
      [Colors.orange, Colors.deepOrange],
      [Colors.brown, Colors.blueGrey],
      [Colors.cyan, Colors.tealAccent.shade700],
      [Colors.red, Colors.deepOrangeAccent],
      [Colors.purple, Colors.deepPurple],
      [Colors.indigo, Colors.blueAccent],
      [Colors.pink, Colors.redAccent],
      [Colors.teal, Colors.greenAccent.shade700],
      [Colors.amber.shade700, Colors.orange.shade900],
      [Colors.deepPurple, Colors.indigoAccent],
    ];

    // Jika mapel terdaftar, berikan warna spesifik (Opsional)
    if (name.contains('matematika')) return gradients[0];
    if (name.contains('ipa')) return gradients[1];
    if (name.contains('bahasa')) return gradients[2];
    if (name.contains('ips')) return gradients[3];
    if (name.contains('agama')) return gradients[4];
    if (name.contains('olahraga')) return gradients[5];
    if (name.contains('seni')) return gradients[6];
    if (name.contains('tik')) return gradients[7];
    if (name.contains('pkn')) return gradients[8];

    // Jika tidak terdaftar, pilih gradient berdasarkan hash agar tetap berwarna-warni
    return gradients[hash % gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _getGradient(),
        ),
      ),
      child: Center(
        child: Icon(
          _getIcon(),
          size: 60,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

// --- KELAS-KELAS SERVICE NATIVE ---
class NativeSecureFlagService {
  static const _platform = MethodChannel('com.example.exam_browser/secure_flag');
  static Future<void> setSecureFlag() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('setSecureFlag');
    } on PlatformException catch (e) {
      debugPrint("Failed to set secure flag: ${e.message}");
    }
  }

  static Future<void> clearSecureFlag() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('clearSecureFlag');
    } on PlatformException catch (e) {
      debugPrint("Failed to clear secure flag: ${e.message}");
    }
  }
}

class ActivityMonitorService {
  static const _platform = MethodChannel('com.example.exam_browser/activity_monitor');
  static final _lockAppController = StreamController<String?>.broadcast();
  static Stream<String?> get lockReasonStream => _lockAppController.stream;

  static Future<void> initializeMonitoring() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _platform.setMethodCallHandler(_handleNativeCall);
    try {
      await _platform.invokeMethod('startMonitoring');
    } on PlatformException catch (e) {
      debugPrint("Failed to initialize activity monitoring: ${e.message}");
    }
  }

  static Future<void> stopMonitoring() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('stopMonitoring');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop activity monitoring: ${e.message}");
    }
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'lockApp':
        _lockAppController.add(call.arguments as String? ?? "Aktivitas mencurigakan terdeteksi.");
        break;
      case 'unlockApp':
        _lockAppController.add(null);
        break;
    }
  }

  static void requestUnlock() {
    _lockAppController.add(null);
  }
}

// --- FUNGSI MAIN ---
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamBrowserApp());
}

// --- APLIKASI UTAMA ---
class ExamBrowserApp extends StatelessWidget {
  const ExamBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExBrowser 4',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        cardTheme: CardThemeData(elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const StartupScreen(),
    );
  }
}

// --- HALAMAN SPLASH/DISPATCHER ---
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String _loadingStatus = "Menghubungkan ke server...";

  @override
  void initState() {
    super.initState();
    _startStartupProcess();
  }

  Future<void> _startStartupProcess() async {
    setState(() => _loadingStatus = "Memeriksa versi...");
    await _checkVersion();
    
    setState(() => _loadingStatus = "Sinkronisasi data...");
    await _checkLockStatusAndNavigate();
  }

  Future<void> _checkVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final int localVersion = int.parse(info.buildNumber);
    debugPrint("DEBUG_VERSION: Versi Lokal = $localVersion");

    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '85520264';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final int latestVersion = int.parse(response.body.trim());
        debugPrint("DEBUG_VERSION: Versi Server = $latestVersion");
        
        if (localVersion < latestVersion) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Update Tersedia'),
                  content: Text('Versi baru aplikasi tersedia (V$latestVersion). Mohon perbarui aplikasi untuk melanjutkan.'),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('PERBARUI SEKARANG'),
                      onPressed: () => _launchPlayStore(),
                    ),
                  ],
                );
              },
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("DEBUG_VERSION: Gagal cek versi: $e");
    }
  }

  void _launchPlayStore() async {
    const url = 'https://play.google.com/store/apps/details?id=smpn4.malang.examp4';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  // --- FUNGSI BARU: MENGAMBIL TOKEN DARI SERVER ---
  Future<String?> _fetchCurrentToken() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '0';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        String fetchedToken = response.body.trim();
        if (fetchedToken.isNotEmpty) {
          return fetchedToken.split(',')[0].trim();
        }
      }
    } catch (e) {
      debugPrint("Startup: Gagal mengambil token server: $e");
    }
    return null;
  }

  // --- FUNGSI DENGAN LOGIKA SESI YANG DISEMPURNAKAN ---
  Future<void> _checkLockStatusAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLocked = prefs.getBool('isAppLocked') ?? false;

    // Jika tidak ada data kunci sama sekali, cek auto-login token
    if (!isLocked) {
      await _clearLockData(prefs); // Pastikan bersih

      // LOGIKA AUTO-LOGIN TOKEN
      final String? serverToken = await _fetchCurrentToken();
      final String? savedToken = prefs.getString('savedExamToken');

      debugPrint("Auto-Login Check: Server='$serverToken', Saved='$savedToken'");

      if (serverToken != null && savedToken != null && serverToken == savedToken) {
        // Cek Izin DND (Do Not Disturb) - Penting untuk keamanan
        bool dndGranted = false;
        if (kIsWeb || !Platform.isAndroid) {
          dndGranted = true;
        } else {
          const dndChannel = MethodChannel('com.example.exam_browser/dnd');
          try {
            final bool? granted = await dndChannel.invokeMethod('checkDndPermission');
            dndGranted = granted ?? false;
          } catch (_) {}
        }

        if (dndGranted && mounted) {
          debugPrint("Token Cocok & Izin DND Ada => Langsung ke Daftar Ujian.");
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ExamListScreen()),
          );
          return;
        } else {
          debugPrint("Auto-login tertunda: Izin DND belum ada.");
        }
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const TokenScreen()),
        );
      }
      return;
    }

    // --- PERUBAHAN BARU: CEK STATUS SISTEM KUNCI DARI SERVER ---
    // Jika keamanan dimatikan (SAFE OFF), buka kunci otomatis meskipun sesi sama.
    final bool lockSystemEnabled = await _fetchLockSystemStatus();
    if (!lockSystemEnabled) {
      debugPrint("Sistem kunci OFF. Membuka kunci otomatis dan langsung ke halaman token.");
      await _clearLockData(prefs);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const TokenScreen()),
        );
      }
      return;
    }
    // --- AKHIR PERUBAHAN BARU ---

    String? currentSessionId;
    String? savedSessionId = prefs.getString('lockSessionId');

    // Jika terkunci, kita perlu validasi sesi
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1494571347';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));

      if (response.statusCode == 200) {
        currentSessionId = response.body.trim();
        debugPrint("Validasi Sesi: Sesi Tersimpan='$savedSessionId', Sesi Saat Ini='$currentSessionId'");

        // Jika ID sesi berbeda, berarti sesi sudah berakhir atau data sesi lokal tidak valid/lama.
        if (savedSessionId != currentSessionId) {
          debugPrint("Sesi Ujian telah berubah atau tidak valid. Membuka kunci secara otomatis.");
          await _clearLockData(prefs);
          await prefs.remove('lockCount'); // Reset hitungan hanya jika sesi berganti
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const TokenScreen()),
            );
          }
          return; // Hentikan eksekusi lebih lanjut
        }
      }
    } catch (e) {
      debugPrint("Gagal memvalidasi sesi ujian: $e. Kunci akan tetap ditampilkan sebagai fallback.");
    }
    // --- AKHIR LOGIKA VALIDASI SESI ---


    // Jika semua pemeriksaan lolos (sesi sama atau validasi gagal), tampilkan layar kunci.
    final String? lockReason = prefs.getString('lastLockReason');
    
    // Tambahkan hitungan pelanggaran (Tutup Paksa)
    int currentCount = prefs.getInt('lockCount') ?? 0;
    currentCount++;
    await prefs.setInt('lockCount', currentCount);
    debugPrint("Pelanggaran Tutup Paksa Terdeteksi. Total: $currentCount");

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => TokenScreen(
            initialLockReason: lockReason,
            savedSession: savedSessionId,
            currentSession: currentSessionId,
            lockCount: currentCount,
          ),
        ),
      );
    }
  }

  // --- FUNGSI BARU: MENGAMBIL STATUS SISTEM KUNCI DARI SERVER ---
  Future<bool> _fetchLockSystemStatus() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '522874477';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final status = response.body.trim().toUpperCase();
        debugPrint("Status Sistem Kunci (Startup): $status");
        return status == 'ON';
      }
      return true; // Fallback aman: jika gagal, anggap ON agar tidak ada celah
    } catch (e) {
      debugPrint("Gagal mengambil status sistem kunci (Startup), menganggap ON. Error: $e");
      return true; // Fallback aman: jika error, anggap ON agar tidak ada celah
    }
  }

  Future<void> _clearLockData(SharedPreferences prefs) async {
    await prefs.remove('isAppLocked');
    await prefs.remove('lastExamUrl');
    await prefs.remove('lastLockReason');
    await prefs.remove('lockTimestamp');
    await prefs.remove('lockSessionId');
    // lockCount TIDAK dihapus di sini agar tetap berlanjut dalam satu sesi
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _loadingStatus,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// --- HALAMAN TOKEN ---
class TokenScreen extends StatefulWidget {
  final String? initialLockReason;
  final String? savedSession;
  final String? currentSession;
  final int? lockCount;
  final bool bypassAutoLogin;

  const TokenScreen({
    super.key,
    this.initialLockReason,
    this.savedSession,
    this.currentSession,
    this.lockCount,
    this.bypassAutoLogin = false,
  });

  @override
  State<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<TokenScreen> with WidgetsBindingObserver {
  static const dndChannel = MethodChannel('com.example.exam_browser/dnd');
  final TextEditingController _tokenController = TextEditingController();
  String? _correctExamToken;
  String _tokenError = "";
  bool _isLoading = true;
  String _fetchError = "";
  String _examNote = "";
  String _appVersion = "";
  bool _isDndPermissionGranted = false;
  bool _dndCheckBypassed = false;

  String? _lockReason;
  int _lockCount = 0;
  final TextEditingController _adminCodeController = TextEditingController();
  String? _correctAdminCode;
  String _adminCodeError = "";
  bool _isFetchingAdminCode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPackageInfo();

    _lockReason = widget.initialLockReason;
    _lockCount = widget.lockCount ?? 0;
    if (_lockReason != null) {
      _fetchAdminCode();
      _isLoading = false;
    } else {
      _checkPermissionsAndLoad();
    }
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = 'Versi ${info.version} (Build ${info.buildNumber})');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lockReason == null) {
      _checkDndPermission();
    }
  }

  Future<void> _checkPermissionsAndLoad() async {
    await _checkDndPermission();
    if (_isDndPermissionGranted || _dndCheckBypassed) {
      _refreshData();
    }
  }

  Future<void> _checkDndPermission() async {
    if (kIsWeb || !Platform.isAndroid) {
      if (mounted) setState(() => _isDndPermissionGranted = true);
      return;
    }
    try {
      final bool? granted = await dndChannel.invokeMethod('checkDndPermission');
      if (mounted) {
        setState(() {
          _isDndPermissionGranted = granted ?? false;
          if (!_isDndPermissionGranted && !_dndCheckBypassed) {
            _isLoading = false;
          }
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _isDndPermissionGranted = false);
    }
  }

  Future<void> _requestDndPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await dndChannel.invokeMethod('requestDndPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request DND permission: ${e.message}");
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _fetchError = ""; // Reset pesan error setiap kali refresh dimulai
    });
    await _fetchExamToken();
    await _fetchExamNote();
    if (!widget.bypassAutoLogin) {
      await _checkSavedTokenAutoLogin(); // auto-login jika tidak dibypass
    } else {
      debugPrint("Auto-login dibypass karena navigasi dari Home.");
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchExamNote() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1478015243';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));
      if (mounted && response.statusCode == 200) {
        String note = response.body.trim();
        if (note.startsWith('"') && note.endsWith('"')) {
          note = note.substring(1, note.length - 1);
        }
        setState(() => _examNote = note.replaceAll('""', '"'));
      }
    } catch (e) {
      debugPrint("Failed to fetch exam note: $e");
    }
  }

  Future<void> _fetchExamToken() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '0';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 15));
      if (mounted) {
        if (response.statusCode == 200) {
          String fetchedToken = response.body.trim();
          if (fetchedToken.isNotEmpty) {
            _correctExamToken = fetchedToken.split(',')[0].trim();
            setState(() => _fetchError = ""); // Reset error jika sukses
          } else {
            setState(() => _fetchError = "Data token kosong di server.");
          }
        } else {
          setState(() => _fetchError = "Gagal menghubungi server (Status: ${response.statusCode}).");
        }
      }
    } catch (e) {
      if (mounted) setState(() => _fetchError = "Error mengambil token. Periksa koneksi internet Anda.");
      debugPrint("Failed to fetch exam token: $e");
    }
  }

  Future<void> _validateToken() async {
    if (_correctExamToken == null) {
      _refreshData();
      setState(() => _tokenError = "Token belum terambil. Mencoba memuat ulang...");
      return;
    }

    if (_tokenController.text == _correctExamToken) {
      setState(() => _tokenError = "");
      // Simpan token yang tersob sekali ini untuk auto-login di lain waktu.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('savedExamToken', _tokenController.text);
        debugPrint("Token ujian tersimpan untuk auto-login di lain waktu.");
      } catch (e) {
        debugPrint("Gagal menyimpan token: $e");
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ExamListScreen()),
      );
    } else {
      setState(() => _tokenError = "Token ujian salah.");
      _tokenController.clear();
      HapticFeedback.mediumImpact();
    }
  }

  // Auto-login: kalok token terakhir yang dimasukkan sama dengan token
  // terkini dari spreadsheet, langsung masuk tanpa disuruh mengetik.
  // Hanya berlaku mode normal (bukan kunci admin/force-close).
  Future<void> _checkSavedTokenAutoLogin() async {
    if (_lockReason != null || !mounted) return;
    if (_correctExamToken == null || _correctExamToken!.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedToken = prefs.getString('savedExamToken');
      if (savedToken != null &&
          savedToken.isNotEmpty &&
          savedToken == _correctExamToken) {
        debugPrint("Token tersimpan sama dengan server => otomatis masuk.");
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ExamListScreen()),
        );
      }
    } catch (e) {
      debugPrint("Gagal memverifikasikan token tersimpan: $e");
    }
  }

  Future<void> _clearLockData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isAppLocked');
    await prefs.remove('lastExamUrl');
    await prefs.remove('lastLockReason');
    await prefs.remove('lockTimestamp');
    await prefs.remove('lockSessionId');
    // lockCount dipertahankan
  }

  Future<void> _fetchAdminCode() async {
    if (!mounted) return;
    setState(() => _isFetchingAdminCode = true);
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1460373020';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));
      if (mounted && response.statusCode == 200) {
        setState(() => _correctAdminCode = response.body.trim());
      }
    } catch (e) {
      debugPrint("Failed to fetch admin code: $e");
    } finally {
      if (mounted) setState(() => _isFetchingAdminCode = false);
    }
  }

  void _attemptUnlock() async {
    if (_correctAdminCode == null) {
      await _fetchAdminCode();
      if (_correctAdminCode == null) {
        setState(() => _adminCodeError = "Gagal verifikasi. Coba lagi.");
        return;
      }
    }

    if (_adminCodeController.text == _correctAdminCode) {
      await _clearLockData();
      setState(() {
        _lockReason = null;
        _adminCodeError = "";
        _adminCodeController.clear();
        _isLoading = true; // Kembali ke loading untuk memulai flow normal
        _checkPermissionsAndLoad();
      });
    } else {
      setState(() => _adminCodeError = "Kode admin salah.");
      _adminCodeController.clear();
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenController.dispose();
    _adminCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FAB tetap muncul jika terjadi error fetch atau token belum ada, agar user bisa refresh
    final bool showFab = !_isLoading &&
        _lockReason == null &&
        (_isDndPermissionGranted || _dndCheckBypassed) &&
        (_fetchError.isEmpty || _correctExamToken == null);

    return Scaffold(
      floatingActionButton: showFab
          ? FloatingActionButton(
        onPressed: _refreshData,
        tooltip: 'Refresh Data Ujian',
        child: const Icon(Icons.refresh),
      )
          : null,
      body: Stack(
        children: [
          _buildMainContent(),
          if (_lockReason != null) _buildLockScreen(),
        ],
      ),
    );
  }

  Widget _buildLockScreen() {
    return GestureDetector(
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
                const Text('Aplikasi Terkunci!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                const Text(
                    'Aplikasi sebelumnya ditutup paksa saat sesi ujian sedang berjalan. Silakan hubungi pengawas atau masukkan kode admin untuk membuka.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.yellowAccent, fontSize: 16, fontStyle: FontStyle.italic)
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: TextField(
                    controller: _adminCodeController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Kode Admin',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                      errorText: _adminCodeError.isNotEmpty ? _adminCodeError : null,
                      errorStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _isFetchingAdminCode ? null : _attemptUnlock,
                      child: _isFetchingAdminCode
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : const Text("Buka Kunci"),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _isFetchingAdminCode ? null : _fetchAdminCode,
                    ),
                  ],
                ),
                if (widget.savedSession != null || widget.currentSession != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 25.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        children: [
                          const Text('--- INFORMASI SESI ---', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Sesi Tersimpan: ${widget.savedSession ?? "None"}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Sesi Server: ${widget.currentSession ?? "Gagal Memuat"}', style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Total Pelanggaran: $_lockCount', style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_lockReason == null && !_isDndPermissionGranted && Platform.isAndroid && !_dndCheckBypassed) {
      return Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.notifications_off, color: Colors.blue[700], size: 80),
            const SizedBox(height: 20),
            const Text('Izin Diperlukan', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            const Text(
              'Untuk kelancaran ujian, aplikasi ini memerlukan izin untuk mengaktifkan mode "Jangan Ganggu".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _requestDndPermission,
              icon: const Icon(Icons.settings),
              label: const Text('Buka Pengaturan'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                setState(() => _dndCheckBypassed = true);
                _refreshData();
              },
              child: const Text('Lanjutkan Nanti'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_fetchError.isNotEmpty && _correctExamToken == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.error_outline, color: Colors.red[700], size: 80),
              const SizedBox(height: 20),
              const Text('Gagal Memuat Konfigurasi', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 15),
              Text(_fetchError, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 16)),
              const SizedBox(height: 30),
              ElevatedButton.icon(onPressed: _refreshData, icon: const Icon(Icons.refresh), label: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset('assets/images/logo_baru_sekolah.png', height: 180),
            const SizedBox(height: 20),
            Text('Selamat Datang', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _tokenController,
                      keyboardType: TextInputType.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
                      decoration: InputDecoration(
                        hintText: 'Masukkan Token Ujian',
                        errorText: _tokenError.isNotEmpty ? _tokenError : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onSubmitted: (_) => _validateToken(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _validateToken,
                      child: Text(_correctExamToken == null ? 'Ambil Token' : 'Masuk'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_examNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(_examNote, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black54)),
              ),
            const SizedBox(height: 40),
            Text(_appVersion, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class ExamListScreen extends StatefulWidget {
  const ExamListScreen({super.key});
  @override
  State<ExamListScreen> createState() => _ExamListScreenState();
}

class _ExamListScreenState extends State<ExamListScreen> {
  List<Exam> _exams = [];
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _fetchExams();
  }

  Future<void> _fetchExams() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '787301166';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 15));
      
      if (mounted) {
        if (response.statusCode == 200) {
          // Mendukung berbagai format baris baru (\n atau \r\n)
          final lines = response.body.split(RegExp(r'\r\n|\n')).where((line) => line.trim().isNotEmpty).skip(1);
          final List<Exam> exams = [];
          for (final line in lines) {
            final parts = line.split(',');
            if (parts.length >= 4) {
              exams.add(Exam(
                image: parts[0].trim(),
                mapel: parts[1].trim(),
                waktu: parts[2].trim(),
                link: parts[3].trim(),
              ));
            }
          }
          setState(() {
            _exams = exams;
            if (exams.isEmpty) _errorMessage = "Tidak ada ujian tersedia saat ini.";
          });
        } else {
          setState(() => _errorMessage = "Gagal memuat data (Error: ${response.statusCode})");
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch exams: $e");
      if (mounted) {
        setState(() => _errorMessage = "Kendala koneksi atau server. Silakan coba lagi.");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Ujian'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const TokenScreen(bypassAutoLogin: true),
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchExams,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 60),
                    const SizedBox(height: 10),
                    Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 20),
                    ElevatedButton(onPressed: _fetchExams, child: const Text("Coba Lagi")),
                  ],
                ),
              ),
            )
          : GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: _exams.length,
        itemBuilder: (context, index) {
          final exam = _exams[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: InkWell(
              onTap: () async {
                // PRE-LOCKING SEBELUM PINDAH HALAMAN
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isAppLocked', true);
                await prefs.setString('lastExamUrl', exam.link);
                await prefs.setString('lastLockReason', "Aplikasi ditutup tidak wajar saat sesi ujian.");
                // lockCount tidak di-reset di sini, melainkan mengikuti sesi server
                
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => ExamContentScreen(examUrl: exam.link)),
                  );
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SubjectThumbnail(mapel: exam.mapel),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exam.mapel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(exam.waktu, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ExamContentScreen extends StatefulWidget {
  final String examUrl;
  final String? initialLockReason;

  const ExamContentScreen({
    super.key,
    required this.examUrl,
    this.initialLockReason,
  });

  @override
  State<ExamContentScreen> createState() => _ExamContentScreenState();
}

class _ExamContentScreenState extends State<ExamContentScreen> {
  static const brightnessChannel = MethodChannel('com.example.exam_browser/brightness');

  // --- KONFIGURASI WEBVIEW (InAppWebView) ---
  InAppWebViewController? _webViewController;

  String? _lockReason;
  int _lockCount = 0;
  StreamSubscription? _lockReasonSubscription;
  late Timer _timer;
  String _currentTime = '';
  double _loadProgress = 0;

  final TextEditingController _adminCodeController = TextEditingController();
  String? _correctAdminCode;
  String _adminCodeError = "";
  bool _isFetchingAdminCode = false;

  bool _isLockSystemEnabledOnThisSession = false;

  bool get _isWebViewSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _lockReason = widget.initialLockReason;

    _initializeSessionSettings();
    _initializeExamMode();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());

    _lockReasonSubscription = ActivityMonitorService.lockReasonStream.listen((reason) async {
      if (reason == null) return;

      if (!_isLockSystemEnabledOnThisSession) {
        debugPrint("Sistem kunci OFF pada sesi ini. Penguncian layar dibatalkan.");
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        if (_correctAdminCode == null) await _fetchAdminCode();

        int currentCount = (prefs.getInt('lockCount') ?? 0) + 1;
        await prefs.setInt('lockCount', currentCount);

        setState(() {
          _lockReason = reason;
          _lockCount = currentCount;
        });

        await prefs.setBool('isAppLocked', true);
        await prefs.setString('lastExamUrl', widget.examUrl);
        await prefs.setString('lastLockReason', reason);
        await prefs.setInt('lockTimestamp', DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  Future<void> _initializeSessionSettings() async {
    _isLockSystemEnabledOnThisSession = await _fetchLockSystemStatus();
    await _fetchAdminCode();
    
    // --- PERUBAHAN BARU: SIMPAN ID SESI DAN AKTIFKAN PRE-LOCKING SEGERA ---
    await _saveCurrentSessionId();
    
    if (_isLockSystemEnabledOnThisSession) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _lockCount = prefs.getInt('lockCount') ?? 0;
      });
      await prefs.setBool('isAppLocked', true);
      await prefs.setString('lastExamUrl', widget.examUrl);
      await prefs.setString('lastLockReason', "Aplikasi ditutup tidak wajar saat sesi ujian.");
      debugPrint("PRE-LOCKING AKTIF: Status terkunci berhasil disimpan.");
    }
  }

  // --- FUNGSI BARU UNTUK MENYIMPAN ID SESI ---
  Future<void> _saveCurrentSessionId() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1494571347';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));
      if (response.statusCode == 200) {
        final currentSessionId = response.body.trim();
        if (currentSessionId.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('lockSessionId', currentSessionId);
          debugPrint("Sesi Ujian '$currentSessionId' disimpan saat memasuki halaman ujian.");
        }
      }
    } catch (e) {
      debugPrint("Gagal menyimpan ID Sesi saat memasuki halaman ujian: $e");
    }
  }

  Future<bool> _fetchLockSystemStatus() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '522874477';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final status = response.body.trim().toUpperCase();
        debugPrint("Status Sistem Kunci untuk sesi ini: $status");
        return status == 'ON';
      }
      return false;
    } catch (e) {
      debugPrint("Gagal mengambil status sistem kunci, menganggap OFF. Error: $e");
      return false;
    }
  }

  Future<void> _setBrightness(double brightness) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await brightnessChannel.invokeMethod('setBrightness', {'brightness': brightness});
    } on PlatformException catch (e) {
      debugPrint("Failed to set brightness: ${e.message}");
    }
  }

  void _updateTime() {
    if (!mounted) return;
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    });
  }

  Future<void> _fetchAdminCode() async {
    if (!mounted) return;
    setState(() => _isFetchingAdminCode = true);
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1460373020';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));
      if (mounted && response.statusCode == 200) {
        setState(() {
          _correctAdminCode = response.body.trim();
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch admin code: $e");
    } finally {
      if(mounted) {
        setState(() => _isFetchingAdminCode = false);
      }
    }
  }

  Future<void> _initializeExamMode() async {
    if (!_isWebViewSupported) return;
    await _setBrightness(0.4);
    await NativeSecureFlagService.setSecureFlag();
    await ActivityMonitorService.initializeMonitoring();
  }

  Future<void> _clearLockData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isAppLocked');
    await prefs.remove('lastExamUrl');
    await prefs.remove('lastLockReason');
    await prefs.remove('lockTimestamp');
    await prefs.remove('lockSessionId');
    // lockCount dipertahankan
  }

  Future<void> _exitExamMode() async {
    if (!_isWebViewSupported) return;
    await _setBrightness(-1.0);
    await _clearLockData();
    await ActivityMonitorService.stopMonitoring();
    await NativeSecureFlagService.clearSecureFlag();
  }

  void _attemptUnlock() async {
    if (_correctAdminCode == null) {
      await _fetchAdminCode();
      if (_correctAdminCode == null) {
        setState(() => _adminCodeError = "Gagal verifikasi. Coba lagi.");
        return;
      }
    }

    if (_adminCodeController.text == _correctAdminCode) {
      await _clearLockData();
      ActivityMonitorService.requestUnlock();

      if (mounted) {
        setState(() {
          _lockReason = null;
          _adminCodeError = "";
          _adminCodeController.clear();
        });
      }

      await Future.delayed(const Duration(milliseconds: 500));
      await ActivityMonitorService.initializeMonitoring();
      debugPrint("Activity Monitoring diinisialisasi ulang setelah unlock.");

    } else {
      if (mounted) {
        setState(() {
          _adminCodeError = "Kode admin salah.";
          _adminCodeController.clear();
        });
        HapticFeedback.mediumImpact();
      }
    }
  }
  Future<bool> _showAdminAuthDialog({required String title, required String content}) async {
    if (!_isLockSystemEnabledOnThisSession) {
      debugPrint("Sistem kunci OFF pada sesi ini. Otorisasi admin dilewati.");
      return true;
    }

    if (_correctAdminCode == null) await _fetchAdminCode();
    if (!mounted) return false;

    final TextEditingController dialogAdminCodeController = TextEditingController();
    String? dialogError;

    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(content),
                    const SizedBox(height: 20),
                    TextField(
                      controller: dialogAdminCodeController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Kode Admin',
                        errorText: dialogError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (dialogAdminCodeController.text == _correctAdminCode) {
                      Navigator.of(context).pop(true);
                    } else {
                      setDialogState(() {
                        dialogError = 'Kode admin salah.';
                      });
                      dialogAdminCodeController.clear();
                      HapticFeedback.mediumImpact();
                    }
                  },
                  child: const Text('Konfirmasi'),
                ),
              ],
            );
          },
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 100));
    dialogAdminCodeController.dispose();

    return result ?? false;
  }
  @override
  void dispose() {
    _timer.cancel();
    _lockReasonSubscription?.cancel();
    _adminCodeController.dispose();
    _exitExamMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isActuallyLocked = _lockReason != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (isActuallyLocked) return;

        final bool shouldPop = await _showAdminAuthDialog(
          title: 'Kembali ke Daftar Ujian?',
          content: 'Untuk keluar dari ujian ini, masukkan kode admin.',
        );
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: isActuallyLocked
              ? const SizedBox.shrink()
              : IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final bool canPop = await _showAdminAuthDialog(
                title: 'Kembali ke Daftar Ujian?',
                content: 'Untuk keluar dari ujian ini, masukkan kode admin.',
              );
              if (canPop && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: const Text('Ujian'),
          actions: [
            // Indikator Keamanan
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _isLockSystemEnabledOnThisSession ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isLockSystemEnabledOnThisSession ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isLockSystemEnabledOnThisSession ? Icons.security : Icons.security_outlined,
                      size: 14,
                      color: _isLockSystemEnabledOnThisSession ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isLockSystemEnabledOnThisSession ? 'SAFE ON' : 'SAFE OFF',
                      style: TextStyle(
                        color: _isLockSystemEnabledOnThisSession ? Colors.green : Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text(_currentTime, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
            if(_isWebViewSupported)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  final bool? shouldReload = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Refresh Halaman?'),
                      content: const Text('Apakah Anda yakin ingin memuat ulang halaman ujian? Progres yang belum tersimpan mungkin akan hilang.'),
                      actions: <Widget>[
                        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
                        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, Refresh')),
                      ],
                    ),
                  );
                  if (shouldReload ?? false) {
                    _webViewController?.reload();
                  }
                },
              ),
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () async {
                if (isActuallyLocked) return;

                final bool canNavigateHome = await _showAdminAuthDialog(
                  title: 'Kembali ke Halaman Awal?',
                  content: 'Untuk keluar dari sesi ujian dan kembali ke halaman token, masukkan kode admin.',
                );

                if (canNavigateHome && context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const TokenScreen()),
                        (route) => false,
                  );
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_isWebViewSupported)
              InAppWebView(
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  transparentBackground: true,
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  allowFileAccess: true,
                  useHybridComposition: true,
                  thirdPartyCookiesEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  cacheEnabled: true,
                  userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A525F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _loadProgress = progress / 100;
                  });
                },
                onLoadStart: (controller, url) async {
                  if (url != null) {
                    final urlStr = url.toString();
                    // JIKA DI HALAMAN LOGIN GOOGLE: Matikan keamanan agar Autofill/Account Picker sistem bisa muncul
                    // Kita perluas deteksinya ke domain google login yang lain
                    if (urlStr.contains("accounts.google.com") || urlStr.contains("accounts.youtube.com")) {
                      await NativeSecureFlagService.clearSecureFlag();
                      await ActivityMonitorService.stopMonitoring();
                      debugPrint("Login Phase: Security Temporarily Disabled for Autofill support.");
                    } else if (urlStr.startsWith(widget.examUrl) || urlStr.contains("docs.google.com/forms")) {
                      // JIKA KEMBALI KE FORM/DOMAIN UJIAN: Aktifkan kembali keamanan
                      await NativeSecureFlagService.setSecureFlag();
                      await ActivityMonitorService.initializeMonitoring();
                      debugPrint("Exam Phase: Security Re-enabled.");
                    }
                  }
                  debugPrint("Halaman mulai dimuat: ${url?.toString() ?? 'null'}");
                },
                onLoadStop: (controller, url) {
                  debugPrint("Halaman dimuat: ${url?.toString() ?? 'null'}");
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final url = navigationAction.request.url;
                  if (_lockReason != null) return NavigationActionPolicy.CANCEL;
                  final String urlStr = url.toString();
                  // Izinkan navigasi ke domain ujian dan google (termasuk
                  // accounts.google.com untuk login dan accounts.google.com
                  // untuk account picker)
                  if (urlStr.startsWith(widget.examUrl) ||
                      urlStr.contains('.google.com') ||
                      urlStr.contains('googleusercontent.com') ||
                      urlStr.contains('accounts.google.com')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  // Blokir navigasi ke luar domain yang diizinkan
                  return NavigationActionPolicy.CANCEL;
                },
                onCreateWindow: (controller, createWindowRequest) async {
                  // Popup dari Google (mis. login) yang tetap ingin dibuka:
                  // Muat URL popup di WebView utama agar account picker muncul.
                  final reqUrl = createWindowRequest.request.url;
                  if (reqUrl != null) {
                    await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(reqUrl)));
                    return false;
                  }
                  return true;
                },
                onCloseWindow: (controller) {},
                onReceivedError: (controller, request, error) {
                  debugPrint('WebView Error: ${error.description}');
                },
                initialUrlRequest: URLRequest(url: WebUri.uri(Uri.parse(widget.examUrl))),
              )
            else
              const Center(child: Text('Fitur ujian tidak didukung di platform ini.')),
            
            // PROGRESS BAR (Muncul saat loading)
            if (_loadProgress < 1.0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _loadProgress,
                  backgroundColor: Colors.transparent,
                  color: Colors.blue,
                  minHeight: 3,
                ),
              ),
              
            if (isActuallyLocked)
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
                          const Text('Aplikasi Terkunci!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 15),
                          const Text('Silakan hubungi pengawas atau masukkan kode admin.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 30),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40.0),
                            child: TextField(
                              controller: _adminCodeController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                              decoration: InputDecoration(
                                labelText: 'Kode Admin',
                                labelStyle: const TextStyle(color: Colors.white70),
                                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                                errorText: _adminCodeError.isNotEmpty ? _adminCodeError : null,
                                errorStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _isFetchingAdminCode ? null : _attemptUnlock,
                                child: _isFetchingAdminCode
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                    : const Text("Buka Kunci"),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.white),
                                onPressed: _isFetchingAdminCode ? null : _fetchAdminCode,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_lockReason != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 15.0),
                              child: Column(
                                children: [
                                  Text(_lockReason!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontStyle: FontStyle.italic)),
                                  const SizedBox(height: 10),
                                  Text('Pelanggaran Sesi Ini: $_lockCount', style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
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
        ),
      ),
    );
  }
}
