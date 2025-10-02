import 'dart:async'; // Import untuk StreamController
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http; // Ditambahkan untuk HTTP requests

// --- SERVICE UNTUK FITUR NATIVE ---
class NativeSecureFlagService {
  // ... (tetap sama)
  static const platform = MethodChannel('com.example.exam_browser/secure_flag');

  static Future<void> setSecureFlag() async {
    try {
      await platform.invokeMethod('setSecureFlag');
      debugPrint("Native secure flag set successfully");
    } on PlatformException catch (e) {
      debugPrint("Failed to set native secure flag: '${e.message}'.");
    }
  }

  static Future<void> clearSecureFlag() async {
    try {
      await platform.invokeMethod('clearSecureFlag');
      debugPrint("Native secure flag cleared successfully");
    } on PlatformException catch (e) {
      debugPrint("Failed to clear native secure flag: '${e.message}'.");
    }
  }
}

class ActivityMonitorService {
  static const _platform = MethodChannel('com.example.exam_browser/activity_monitor');
  static final _lockAppController = StreamController<String?>.broadcast();
  static Stream<String?> get lockReasonStream => _lockAppController.stream;

  static Future<void> initializeMonitoring() async {
    _platform.setMethodCallHandler(_handleNativeCall);
    try {
      await _platform.invokeMethod('startMonitoring');
      debugPrint("Activity monitoring initialized");
    } on PlatformException catch (e) {
      debugPrint("Failed to initialize activity monitoring: '${e.message}'.");
    }
  }

  static Future<void> stopMonitoring() async {
    try {
      await _platform.invokeMethod('stopMonitoring');
      debugPrint("Activity monitoring stopped");
    } on PlatformException catch (e) {
      debugPrint("Failed to stop activity monitoring: '${e.message}'.");
    }
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'lockApp':
        final String? reason = call.arguments as String?;
        _lockAppController.add(reason ?? "Aktivitas mencurigakan terdeteksi.");
        debugPrint("Native requested app lock. Reason: $reason");
        break;
      case 'unlockApp':
        _lockAppController.add(null);
        debugPrint("Native requested app unlock.");
        break;
      default:
        debugPrint('Unknown method ${call.method}');
    }
  }

  static void requestUnlock() {
    _lockAppController.add(null);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamBrowserApp());
}

class ExamBrowserApp extends StatelessWidget {
  const ExamBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exam Browser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      debugShowCheckedModeBanner: false,
      home: const TokenScreen(),
    );
  }
}

// --- WIDGET BARU UNTUK LAYAR TOKEN ---
class TokenScreen extends StatefulWidget {
  const TokenScreen({super.key});

  @override
  State<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<TokenScreen> {
  final TextEditingController _tokenController = TextEditingController();
  String? _correctExamToken; // Diubah untuk mengambil dari online
  String _tokenError = "";
  bool _isLoadingToken = true;
  String _fetchError = "";

  @override
  void initState() {
    super.initState();
    _fetchExamToken();
  }

  Future<void> _fetchExamToken() async {
    setState(() {
      _isLoadingToken = true;
      _fetchError = "";
      _tokenError = ""; // Reset token validation error
    });
    try {
      // Pastikan spreadsheet Anda "public on the web" atau "anyone with the link can view"
      // Spreadsheet URL: https://docs.google.com/spreadsheets/d/1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ/edit?gid=0#gid=0
      // URL untuk CSV export:
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '0';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Asumsi token ada di sel A1 dan merupakan satu-satunya konten, atau baris pertama.
        // Hapus whitespace atau newline yang mungkin ada.
        String fetchedToken = response.body.trim();
        // Jika CSV memiliki header, Anda mungkin perlu memprosesnya lebih lanjut
        // Contoh: jika token ada di baris kedua setelah header:
        // final lines = response.body.split('\n');
        // if (lines.length > 1) fetchedToken = lines[1].trim(); else fetchedToken = "";

        if (fetchedToken.isNotEmpty) {
          // Anda bisa menambahkan validasi format token di sini jika perlu
          // Misalnya, jika token seharusnya hanya angka atau memiliki panjang tertentu.
          // Untuk saat ini, kita anggap token yang diambil dari sheet adalah benar.
          final potentialToken = fetchedToken.split(',')[0].trim(); // Ambil kolom pertama jika ada beberapa kolom

          if (potentialToken.isNotEmpty) {
             _correctExamToken = potentialToken;
             debugPrint("Token berhasil diambil: $_correctExamToken");
          } else {
            _fetchError = "Format token di spreadsheet tidak valid atau kosong.";
             debugPrint("Token kosong setelah parsing dari CSV.");
          }
        } else {
          _fetchError = "Token tidak ditemukan di spreadsheet (konten kosong).";
          debugPrint("Respon CSV kosong.");
        }
      } else {
        _fetchError = "Gagal mengambil token (Status: ${response.statusCode}). Pastikan spreadsheet dapat diakses publik.";
        debugPrint("Gagal fetch token: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      _fetchError = "Error mengambil token: $e. Periksa koneksi internet Anda.";
      debugPrint("Exception saat fetch token: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingToken = false;
        });
      }
    }
  }

  void _validateToken() {
    if (_isLoadingToken) {
      setState(() {
        _tokenError = "Token sedang dimuat, harap tunggu.";
      });
      return;
    }

    if (_correctExamToken == null || _correctExamToken!.isEmpty) {
      setState(() {
        _tokenError = "Tidak dapat memvalidasi. $_fetchError";
      });
      return;
    }

    setState(() {
      if (_tokenController.text == _correctExamToken) {
        _tokenError = "";
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ExamContentScreen()),
        );
      } else {
        _tokenError = "Token ujian salah.";
        _tokenController.clear();
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingToken) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_fetchError.isNotEmpty && _correctExamToken == null) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.error_outline, color: Colors.red[700], size: 80),
                const SizedBox(height: 20),
                Text(
                  'Gagal Memuat Konfigurasi',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[800],
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  _fetchError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700], fontSize: 16),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onPressed: _fetchExamToken,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Coba Lagi',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.vpn_key, size: 80, color: Colors.blue[700]),
              const SizedBox(height: 20),
              Text(
                'Masukkan Token',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _tokenController,
                obscureText: false, // Diubah menjadi false
                keyboardType: TextInputType.text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Token',
                  errorText: _tokenError.isNotEmpty ? _tokenError : null,
                  errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onSubmitted: (_) => _validateToken(), // Memungkinkan submit dengan enter
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                // Tombol dinonaktifkan jika token belum siap atau ada error fetch
                onPressed: (_correctExamToken == null || _correctExamToken!.isEmpty) ? null : _validateToken,
                child: const Text(
                  'Masuk Ujian',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- PISAHKAN LAYAR EXAM MENJADI EXAMCONTENTSCREEN ---
// Ini adalah ExamScreen yang lama, tapi kita beri nama baru agar tidak bingung
// dengan screen yang mungkin masih ada di cache navigasi.
class ExamContentScreen extends StatefulWidget {
  const ExamContentScreen({super.key});

  @override
  State<ExamContentScreen> createState() => _ExamContentScreenState();
}

class _ExamContentScreenState extends State<ExamContentScreen> {
  late final WebViewController _controller;
  final String examUrl = "https://exam.sidigs.com";
  String? _lockReason;
  StreamSubscription? _lockReasonSubscription;

  final TextEditingController _adminCodeController = TextEditingController();
  final String _correctAdminCode = "1234"; // TODO: Amankan kode admin ini
  String _adminCodeError = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeExamMode();
    });

    _lockReasonSubscription = ActivityMonitorService.lockReasonStream.listen((reason) {
      if (mounted) {
        setState(() {
          _lockReason = reason;
          if (reason == null) {
            _adminCodeController.clear();
            _adminCodeError = "";
          }
        });
        if (reason != null) {
          debugPrint("APP LOCKED. Reason: $reason");
        }
      }
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress : $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
Page resource error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_lockReason != null) return NavigationDecision.prevent;
            if (!request.url.startsWith('https://exam.sidigs.com')) {
              debugPrint('blocking navigation to ${request.url}');
              return NavigationDecision.prevent;
            }
            debugPrint('allowing navigation to ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(examUrl));
  }

  Future<void> _initializeExamMode() async {
    if (mounted && Theme.of(context).platform == TargetPlatform.android) {
      await NativeSecureFlagService.setSecureFlag();
      await ActivityMonitorService.initializeMonitoring();
      debugPrint("Exam mode fully initialized on ExamContentScreen");
    }
  }

  Future<void> _exitExamMode() async {
    if (mounted && Theme.of(context).platform == TargetPlatform.android) {
      await ActivityMonitorService.stopMonitoring();
      await NativeSecureFlagService.clearSecureFlag();
    }
  }

  void _attemptUnlock() {
    setState(() {
      if (_adminCodeController.text == _correctAdminCode) {
        ActivityMonitorService.requestUnlock();
      } else {
        _adminCodeError = "Kode admin salah.";
        _adminCodeController.clear();
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
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
        if (isActuallyLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aplikasi terkunci: $_lockReason. Masukkan kode admin.')),
          );
          return false;
        }

        if (await _controller.canGoBack()) {
          _controller.goBack();
          return false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat kembali saat ujian berlangsung.')),
        );
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),

            if (isActuallyLocked)
              GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
                },
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
                          const Text(
                            'Aplikasi Terkunci!',
                            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            _lockReason ?? 'Aktivitas mencurigakan terdeteksi.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontStyle: FontStyle.italic),
                          ),
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
                              controller: _adminCodeController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                              decoration: InputDecoration(
                                labelText: 'Kode Admin',
                                labelStyle: const TextStyle(color: Colors.white70),
                                enabledBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                                errorText: _adminCodeError.isNotEmpty ? _adminCodeError : null,
                                errorStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            ),
                            onPressed: _attemptUnlock,
                            child: const Text(
                              "Buka Kunci",
                              style: TextStyle(fontSize: 18, color: Colors.white),
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
