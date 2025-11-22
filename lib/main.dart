import 'dart:async'; // Import untuk StreamController
import 'dart:io'; // Import untuk Platform
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http; // Ditambahkan untuk HTTP requests

// --- MODELS ---
class Exam {
  final String image;
  final String mapel;
  final String waktu;
  final String link;

  Exam({required this.image, required this.mapel, required this.waktu, required this.link});
}

// --- SERVICE UNTUK FITUR NATIVE ---
class NativeSecureFlagService {
  static const platform = MethodChannel('com.example.exam_browser/secure_flag');

  static Future<void> setSecureFlag() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await platform.invokeMethod('setSecureFlag');
      debugPrint("Native secure flag set successfully");
    } on PlatformException catch (e) {
      debugPrint("Failed to set native secure flag: '${e.message}'.");
    }
  }

  static Future<void> clearSecureFlag() async {
    if (kIsWeb || !Platform.isAndroid) return;
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
    if (kIsWeb || !Platform.isAndroid) return;
    _platform.setMethodCallHandler(_handleNativeCall);
    try {
      await _platform.invokeMethod('startMonitoring');
      debugPrint("Activity monitoring initialized");
    } on PlatformException catch (e) {
      debugPrint("Failed to initialize activity monitoring: '${e.message}'.");
    }
  }

  static Future<void> stopMonitoring() async {
    if (kIsWeb || !Platform.isAndroid) return;
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
        scaffoldBackgroundColor: Colors.grey[100],
        cardTheme: CardThemeData(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white, // Menentukan warna teks dan ikon di dalam tombol
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
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
  String? _correctExamToken;
  String _tokenError = "";
  bool _isLoadingToken = true;
  String _fetchError = "";
  String _examNote = "";
  bool _isNoteLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    await _fetchExamToken();
    await _fetchExamNote();
  }

  Future<void> _fetchExamNote() async {
    try {
      setState(() => _isNoteLoading = true);
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1478015243';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));
      if (response.statusCode == 200) {
        String note = response.body.trim();
        if (note.startsWith('"') && note.endsWith('"')) {
          note = note.substring(1, note.length - 1);
        }
        if (mounted) {
          setState(() {
            _examNote = note.replaceAll('""', '"');
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _examNote = "Gagal memuat catatan.";
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch note: $e");
      if (mounted) {
        setState(() {
          _examNote = "Gagal memuat catatan.";
        });
      }
    } finally {
      if(mounted) {
        setState(() => _isNoteLoading = false);
      }
    }
  }

  Future<void> _fetchExamToken() async {
    setState(() {
      _isLoadingToken = true;
      _fetchError = "";
      _tokenError = "";
    });
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '0';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        String fetchedToken = response.body.trim();
        if (fetchedToken.isNotEmpty) {
          final potentialToken = fetchedToken.split(',')[0].trim();
          if (potentialToken.isNotEmpty) {
             _correctExamToken = potentialToken;
          } else {
            _fetchError = "Format token di spreadsheet tidak valid atau kosong.";
          }
        } else {
          _fetchError = "Token tidak ditemukan di spreadsheet (konten kosong).";
        }
      } else {
        _fetchError = "Gagal mengambil token (Status: ${response.statusCode}). Pastikan spreadsheet dapat diakses publik.";
      }
    } catch (e) {
      _fetchError = "Error mengambil token: $e. Periksa koneksi internet Anda.";
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
          MaterialPageRoute(builder: (context) => const ExamListScreen()),
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
        body: const Center(child: CircularProgressIndicator()),
        floatingActionButton: FloatingActionButton(
          onPressed: _refreshData,
          child: const Icon(Icons.refresh),
        ),
      );
    }

    if (_fetchError.isNotEmpty && _correctExamToken == null) {
      return Scaffold(
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
                  onPressed: _refreshData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshData,
        child: const Icon(Icons.refresh),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.asset('assets/images/logo_baru_sekolah.png', height: 180),
              const SizedBox(height: 20),
              Text(
                'Selamat Datang',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
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
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onSubmitted: (_) => _validateToken(),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: (_correctExamToken == null || _correctExamToken!.isEmpty) ? null : _validateToken,
                        child: const Text('Masuk'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_isNoteLoading)
                const Center(child: CircularProgressIndicator())
              else if (_examNote.isNotEmpty)
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                   child: Text(
                      _examNote,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.black54,
                      ),
                    ),
                 ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- WIDGET BARU UNTUK DAFTAR UJIAN ---
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
    try {
      setState(() => _isLoading = true);
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '2003099256';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';

      final response = await http.get(Uri.parse(csvUrl));

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
        setState(() {
          _exams = exams;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              ExamContentScreen(examUrl: exam.link),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Image.network(
                            exam.image,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => const Icon(
                              Icons.error,
                              size: 40,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exam.mapel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
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

// --- PISAHKAN LAYAR EXAM MENJADI EXAMCONTENTSCREEN ---
class ExamContentScreen extends StatefulWidget {
  final String examUrl;
  const ExamContentScreen({super.key, required this.examUrl});

  @override
  State<ExamContentScreen> createState() => _ExamContentScreenState();
}

class _ExamContentScreenState extends State<ExamContentScreen> {
  WebViewController? _controller;
  String? _lockReason;
  StreamSubscription? _lockReasonSubscription;

  final TextEditingController _adminCodeController = TextEditingController();
  String? _correctAdminCode;
  String _adminCodeError = "";

  bool get _isWebViewSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchAdminCode();

    if (_isWebViewSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {},
            onPageStarted: (String url) {},
            onPageFinished: (String url) {},
            onWebResourceError: (WebResourceError error) {},
            onNavigationRequest: (NavigationRequest request) {
              if (_lockReason != null) return NavigationDecision.prevent;
              if (!request.url.startsWith(widget.examUrl)) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.examUrl));
    }

    _lockReasonSubscription = ActivityMonitorService.lockReasonStream.listen((reason) {
      if (mounted) {
        setState(() {
          _lockReason = reason;
          if (reason == null) {
            _adminCodeController.clear();
            _adminCodeError = "";
          }
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeExamMode();
  }

  Future<void> _fetchAdminCode() async {
    try {
      const String spreadsheetId = '1RHsYTWrJtcxtjHwb-jb7Faq_EG7hHyTgihiU2WzjsbQ';
      const String gid = '1460373020';
      const String csvUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv&gid=$gid';
      final response = await http.get(Uri.parse(csvUrl));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _correctAdminCode = response.body.trim();
          });
        }
      }
    } catch (e) {
      // Handled
    }
  }


  Future<void> _initializeExamMode() async {
    if (!_isWebViewSupported) return;
    await NativeSecureFlagService.setSecureFlag();
    await ActivityMonitorService.initializeMonitoring();
  }

  Future<void> _exitExamMode() async {
    if (!_isWebViewSupported) return;
    await ActivityMonitorService.stopMonitoring();
    await NativeSecureFlagService.clearSecureFlag();
  }

  void _attemptUnlock() {
    if (_correctAdminCode == null) return;
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
        final bool? shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Kembali ke Daftar Ujian?'),
            content: const Text('Apakah Anda yakin ingin keluar dari ujian ini?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yakin'),
              ),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ujian'),
          actions: [
            if(_isWebViewSupported)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _controller?.reload(),
              ),
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () async {
                final bool? shouldPop = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Kembali ke Halaman Awal?'),
                    content: const Text('Apakah Anda yakin ingin keluar dari sesi ujian dan kembali ke halaman token?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Yakin'),
                      ),
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
            if (_isWebViewSupported && _controller != null)
              WebViewWidget(controller: _controller!)
            else
              const Center(
                child: Text('Fitur ujian tidak didukung di platform ini.'),
              ),
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
                            onPressed: _attemptUnlock,
                            child: const Text("Buka Kunci"),
                          ),
                           const SizedBox(height: 20),
                           if (_lockReason != null)
                             Padding(
                               padding: const EdgeInsets.only(top: 15.0),
                               child: Text(
                                 _lockReason!,
                                 textAlign: TextAlign.center,
                                 style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontStyle: FontStyle.italic),
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
