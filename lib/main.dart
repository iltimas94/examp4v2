import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// --- KELAS MODEL ---
class Exam {
  final String image, mapel, waktu, link;
  Exam({required this.image, required this.mapel, required this.waktu, required this.link});
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
  @override
  void initState() {
    super.initState();
    _checkVersionAndNavigate();
  }

  Future<void> _checkVersionAndNavigate() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final int localVersion = int.parse(info.buildNumber);

    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '85520264';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));

      if (response.statusCode == 200) {
        final int latestVersion = int.parse(response.body.trim());
        if (localVersion < latestVersion) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Update Tersedia'),
                  content: Text('Versi baru aplikasi tersedia. Mohon perbarui aplikasi untuk melanjutkan.'),
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
      // Lanjutkan jika gagal
    }

    _checkLockStatusAndNavigate();
  }

  void _launchPlayStore() async {
    const url = 'https://play.google.com/store/apps/details?id=smpn4.malang.examp4';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _checkLockStatusAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLocked = prefs.getBool('isAppLocked') ?? false;
    final int? lockTimestamp = prefs.getInt('lockTimestamp');

    bool isLockStale = false;
    if (lockTimestamp != null) {
      final lockTime = DateTime.fromMillisecondsSinceEpoch(lockTimestamp);
      if (DateTime.now().difference(lockTime).inHours >= 1) {
        isLockStale = true;
      }
    }

    if (isLocked && !isLockStale) {
      final String? lockReason = prefs.getString('lastLockReason');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => TokenScreen(initialLockReason: lockReason)),
        );
      }
    } else {
      await _clearLockData(prefs);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const TokenScreen()),
        );
      }
    }
  }

  Future<void> _clearLockData(SharedPreferences prefs) async {
    await prefs.remove('isAppLocked');
    await prefs.remove('lastExamUrl');
    await prefs.remove('lastLockReason');
    await prefs.remove('lockTimestamp');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// --- HALAMAN TOKEN ---
class TokenScreen extends StatefulWidget {
  final String? initialLockReason;
  const TokenScreen({super.key, this.initialLockReason});

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
      setState(() => _appVersion = 'Versi ${info.version} (${info.buildNumber})');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
    setState(() => _isLoading = true);
    await _fetchExamToken();
    await _fetchExamNote();
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
      // handle
    }
  }

  Future<void> _fetchExamToken() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '0';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 15));
      if (mounted && response.statusCode == 200) {
        String fetchedToken = response.body.trim();
        if (fetchedToken.isNotEmpty) {
          _correctExamToken = fetchedToken.split(',')[0].trim();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _fetchError = "Error mengambil token. Periksa koneksi internet Anda.");
    }
  }

  void _validateToken() {
    if (_tokenController.text == _correctExamToken) {
      setState(() => _tokenError = "");
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ExamListScreen()),
      );
    } else {
      setState(() => _tokenError = "Token ujian salah.");
      _tokenController.clear();
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _clearLockData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isAppLocked');
    await prefs.remove('lastExamUrl');
    await prefs.remove('lastLockReason');
    await prefs.remove('lockTimestamp');
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
      // handle error
    } finally {
      if (mounted) setState(() => _isFetchingAdminCode = false);
    }
  }

  void _attemptUnlock() async {
    if (_correctAdminCode == null) return;
    if (_adminCodeController.text == _correctAdminCode) {
      await _clearLockData();
      setState(() {
        _lockReason = null;
        _adminCodeError = "";
        _adminCodeController.clear();
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
    return Scaffold(
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
        color: Colors.black.withOpacity(0.90),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (!_isDndPermissionGranted && Platform.isAndroid && !_dndCheckBypassed) {
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
              'Untuk kelancaran ujian, aplikasi ini memerlukan izin untuk mengaktifkan mode \"Jangan Ganggu\".',
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
                      child: const Text('Masuk'),
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

  @override
  void initState() {
    super.initState();
    _fetchExams();
  }

  Future<void> _fetchExams() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '2003099256';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));
      if (mounted) {
        if (response.statusCode == 200) {
          final lines = response.body.split('\r\n').skip(1);
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
          setState(() => _exams = exams);
        } 
      }
    } catch (e) {
      // handle error
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchExams,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => ExamContentScreen(examUrl: exam.link)),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Image.network(
                            exam.image,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => const Icon(Icons.error, size: 40),
                          ),
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
  late final WebViewController _controller;
  String? _lockReason;
  StreamSubscription? _lockReasonSubscription;
  late Timer _timer;
  String _currentTime = '';

  final TextEditingController _adminCodeController = TextEditingController();
  String? _correctAdminCode;
  String _adminCodeError = "";
  bool _isFetchingAdminCode = false;

  bool get _isWebViewSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _lockReason = widget.initialLockReason;

    if (_isWebViewSupported) {
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is AndroidWebViewPlatform) {
        params = AndroidWebViewControllerCreationParams();
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      final WebViewController controller = WebViewController.fromPlatformCreationParams(params);
      
      _controller = controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {},
            onNavigationRequest: (NavigationRequest request) {
              if (_lockReason != null) return NavigationDecision.prevent;
              if (request.url.startsWith(widget.examUrl) || request.url.contains(".google.com")) {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.examUrl));

      if (controller.platform is AndroidWebViewController) {
        (controller.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
      }
    }

    _fetchAdminCode();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());

    _lockReasonSubscription = ActivityMonitorService.lockReasonStream.listen((reason) async {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _lockReason = reason;
        });
        if (reason != null) {
          await prefs.setBool('isAppLocked', true);
          await prefs.setString('lastExamUrl', widget.examUrl);
          await prefs.setString('lastLockReason', reason);
          await prefs.setInt('lockTimestamp', DateTime.now().millisecondsSinceEpoch);
          _fetchAdminCode(); 
        } 
      }
    });
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeExamMode();
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
      // Handled
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
  }
  
  Future<void> _exitExamMode() async {
    if (!_isWebViewSupported) return;
    await _setBrightness(-1.0);
    await _clearLockData();
    await ActivityMonitorService.stopMonitoring();
    await NativeSecureFlagService.clearSecureFlag();
  }

  void _attemptUnlock() async {
    if (_correctAdminCode == null) return;
    if (_adminCodeController.text == _correctAdminCode) {
      await _clearLockData();
      ActivityMonitorService.requestUnlock();
    } else {
      setState(() => _adminCodeError = "Kode admin salah.");
      _adminCodeController.clear();
      HapticFeedback.mediumImpact();
    }
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

    return WillPopScope(
      onWillPop: () async {
        if (isActuallyLocked) return false; 
        final bool? shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Kembali ke Daftar Ujian?'),
            content: const Text('Apakah Anda yakin ingin keluar dari ujian ini?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yakin')),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ujian'),
          actions: [
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
                        TextButton(child: const Text('Batal'), onPressed: () => Navigator.of(context).pop(false)),
                        TextButton(child: const Text('Ya, Refresh'), onPressed: () => Navigator.of(context).pop(true)),
                      ],
                    ),
                  );
                  if (shouldReload ?? false) {
                    _controller.reload();
                  }
                },
              ),
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () async {
                 if (isActuallyLocked) return; 
                final bool? shouldPop = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Kembali ke Halaman Awal?'),
                    content: const Text('Apakah Anda yakin ingin keluar dari sesi ujian dan kembali ke halaman token?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
                      TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yakin')),
                    ],
                  ),
                );
                if (shouldPop ?? false) {
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
              WebViewWidget(controller: _controller)
            else
              const Center(child: Text('Fitur ujian tidak didukung di platform ini.')),
            if (isActuallyLocked)
              GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: Container(
                  color: Colors.black.withOpacity(0.90),
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
                               child: Text(_lockReason!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontStyle: FontStyle.italic)),
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
