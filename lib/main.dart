import 'dart:async'; // Import untuk StreamController
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
      // Ubah home menjadi TokenScreen
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
  final String _correctExamToken = "1234"; // SANGAT TIDAK AMAN
  String _tokenError = "";

  void _validateToken() {
    setState(() { // Untuk update UI jika ada error
      if (_tokenController.text == _correctExamToken) {
        _tokenError = "";
        // Navigasi ke ExamScreen setelah token benar
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
                'Masukkan Token Ujian',
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
                obscureText: true,
                keyboardType: TextInputType.text, // Bisa juga number jika token hanya angka
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
                onPressed: _validateToken,
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
  final String _correctAdminCode = "1234";
  String _adminCodeError = "";

  @override
  void initState() {
    super.initState();
    // Pindahkan _initializeExamMode ke sini, setelah token divalidasi
    // dan layar ini benar-benar ditampilkan
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
      ..loadRequest(Uri.parse(examUrl)); // WebView dimuat di sini
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
    _exitExamMode(); // Penting untuk memanggil ini saat layar konten ujian di-dispose
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
            // Hanya tampilkan WebView jika tidak ada alasan untuk lock
            // (Ini sudah ditangani oleh Stack dan kondisi di bawahnya)
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
                          Icon(Icons.lock, color: Colors.red, size: 80),
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
