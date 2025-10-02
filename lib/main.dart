import 'dart:async'; // Import untuk StreamController
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

// --- SERVICE UNTUK FITUR NATIVE ---
class NativeSecureFlagService {
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
  static final _lockAppController = StreamController<bool>.broadcast();

  // Stream untuk didengarkan oleh UI jika aplikasi harus dikunci
  static Stream<bool> get lockAppStream => _lockAppController.stream;

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

  // Menerima panggilan dari native ketika aplikasi harus dikunci
  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'lockApp':
        _lockAppController.add(true); // Kirim event untuk mengunci aplikasi
        debugPrint("Native requested app lock.");
        break;
      case 'unlockApp': // Opsional: jika ada cara untuk membuka kunci dari native
        _lockAppController.add(false);
        debugPrint("Native requested app unlock.");
        break;
      default:
        debugPrint('Unknown method ${call.method}');
    }
  }

  // Panggil ini dari Dart jika Anda ingin mencoba membuka kunci (misalnya, setelah validasi)
  static void requestUnlock() {
    _lockAppController.add(false);
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
      debugShowCheckedModeBanner: false, // Opsional: menyembunyikan banner debug
      home: const ExamScreen(),
    );
  }
}

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late final WebViewController _controller;
  final String examUrl = "https://exam.sidigs.com";
  bool _isAppLocked = false;
  StreamSubscription? _lockAppSubscription;

  // Untuk input kode admin
  final TextEditingController _adminCodeController = TextEditingController();
  final String _correctAdminCode = "1234"; // SANGAT TIDAK AMAN, HANYA UNTUK DEMO
  String _adminCodeError = "";


  @override
  void initState() {
    super.initState();
    _initializeExamMode();

    _lockAppSubscription = ActivityMonitorService.lockAppStream.listen((shouldLock) {
      if (mounted) {
        setState(() {
          _isAppLocked = shouldLock;
          if (!shouldLock) {
            _adminCodeController.clear(); // Bersihkan kode saat unlock
            _adminCodeError = ""; // Bersihkan error
          }
        });
        if (shouldLock) {
          debugPrint("APP LOCKED due to suspicious activity!");
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
            if (_isAppLocked) return NavigationDecision.prevent;
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
    if (Theme.of(context).platform == TargetPlatform.android) {
      await NativeSecureFlagService.setSecureFlag();
      await ActivityMonitorService.initializeMonitoring();
    }
  }

  Future<void> _exitExamMode() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      await ActivityMonitorService.stopMonitoring();
      await NativeSecureFlagService.clearSecureFlag();
    }
  }

  void _attemptUnlock() {
    setState(() { // Untuk memperbarui UI jika ada error
      if (_adminCodeController.text == _correctAdminCode) {
        ActivityMonitorService.requestUnlock(); // Kirim permintaan buka kunci
        // _isAppLocked akan diupdate oleh stream listener
      } else {
        _adminCodeError = "Kode admin salah.";
        _adminCodeController.clear();
        // Opsional: bergetar atau umpan balik lainnya
        HapticFeedback.mediumImpact();
      }
    });
  }


  @override
  void dispose() {
    _lockAppSubscription?.cancel();
    _adminCodeController.dispose();
    _exitExamMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isAppLocked) {
          // Jika terkunci, mungkin tampilkan pesan bahwa harus unlock dulu
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aplikasi terkunci. Masukkan kode admin untuk membuka.')),
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
            if (_isAppLocked)
              GestureDetector(
                onTap: () {
                  // Mencegah interaksi dengan WebView di bawahnya
                  // Juga bisa digunakan untuk menutup keyboard jika terbuka
                  FocusScope.of(context).unfocus();
                },
                child: Container(
                  color: Colors.black.withOpacity(0.90),
                  child: Center(
                    child: SingleChildScrollView( // Agar bisa di-scroll jika keyboard muncul
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock, color: Colors.red, size: 80),
                          SizedBox(height: 20),
                          Text(
                            'Aplikasi Terkunci!',
                            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Aktivitas mencurigakan terdeteksi.\nSilakan hubungi pengawas atau masukkan kode admin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          SizedBox(height: 30),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40.0),
                            child: TextField(
                              controller: _adminCodeController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: Colors.white, fontSize: 18),
                              decoration: InputDecoration(
                                labelText: 'Kode Admin',
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                                errorText: _adminCodeError.isNotEmpty ? _adminCodeError : null,
                                errorStyle: TextStyle(color: Colors.yellowAccent, fontSize: 14),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(height: 20),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            ),
                            onPressed: _attemptUnlock,
                            child: Text(
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
