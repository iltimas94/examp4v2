// ==================== CBT Alternatif Family Link — Klien REST ====================
// Porting Flutter dari web CBT (Kode.txt + Index.txt). Semua pemanggilan
// google.script.run pada web dipindah ke POST JSON lewat doPost() di Apps Script.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// URL deployment Web App Apps Script (berakhiran /exec) — milik proyek CBT
/// (backend Google Sheets `13OMSRrPXKfUt7MaNw-HnVqHWoKaPWiwJ7CujSo1gGe0`) yang
/// sudah memuat `doPost()` (lihat Kode.txt).
///
/// URL di bawah ini sudah DIISI dan permanen. Bila suatu saat deployment
/// berganti: cukup ganti nilai konstanta ini lalu rebuild APK — atau biarkan
/// kosong agar URL terdeteksi otomatis dari kolom "link" pada Daftar Ujian
/// (lihat deteksiUrlApiDariLink).
const String kCbtApiUrl =
    'https://script.google.com/macros/s/AKfycbyZZTiWMClqOPcRg4vtohaL7cX1gnmuhDjqS7lSfZB0Hj62GUQ9MF9-rdTxhOvCbtc/exec';

/// URL hasil deteksi otomatis dari link ujian di Daftar Ujian.
String _urlTerdeteksi = '';

/// URL yang benar-benar dipakai: konstanta di atas diutamakan, kalau kosong
/// pakai hasil deteksi otomatis dari link ujian.
String get kCbtUrlEfektif =>
    kCbtApiUrl.trim().isNotEmpty ? kCbtApiUrl.trim() : _urlTerdeteksi;

/// Tarik URL deployment /exec dari sebuah link ujian (kolom CSV Daftar Ujian
/// biasanya berisi URL Web App yang sama dengan endpoint doPost).
/// Mengembalikan true bila URL berhasil tersimpan/diubah.
bool deteksiUrlApiDariLink(String link) {
  final m = RegExp(r'https://script\.google\.com/macros/s/[A-Za-z0-9_\-]+/exec')
      .firstMatch(link);
  if (m == null) return false;
  final url = m.group(0)!;
  if (url == _urlTerdeteksi) return false;
  _urlTerdeteksi = url;
  return true;
}

/// URL yang tersimpan dari hasil deteksi terakhir (dipakai juga saat pengujian).
String get urlApiTerdeteksi => _urlTerdeteksi;

/// Penanda kartu ujian NATIVE di Daftar Ujian (bukan URL web).
const String kCbtNativeLink = 'native://cbt';

/// Nama kartu paten di Daftar Ujian.
const String kCbtNamaPaten = 'CBT Alternatif Family Link';

/// Kegagalan memanggil API (jaringan / respons tidak valid / konfigurasi).
class CbtApiException implements Exception {
  final String message;
  CbtApiException(this.message);
  @override
  String toString() => message;
}

/// Pembatas konkurensi FIFO. Google Apps Script hanya melayani sekitar 30
/// eksekusi bersamaan; membatasi permintaan dari sisi aplikasi mencegah satu
/// perangkat memborbardir server (autosave + retry + refresh sekaligus) dan
/// membuat perangkat lain tetap terlayani saat 900 siswa ujian serentak.
class CbtSemaphore {
  CbtSemaphore(this.maks);

  final int maks;
  int _aktif = 0;
  final List<Completer<void>> _tunggu = <Completer<void>>[];

  /// Jumlah permintaan yang sedang berjalan.
  int get aktif => _aktif;

  /// Jumlah permintaan yang mengantre.
  int get menunggu => _tunggu.length;

  /// Ambil satu slot; selesai (Future) berarti slot sudah didapat.
  Future<void> masuk() {
    if (_aktif < maks) {
      _aktif++;
      return Future<void>.value();
    }
    final c = Completer<void>();
    _tunggu.add(c);
    return c.future;
  }

  /// Lepas satu slot; slot langsung diberikan ke antrean berikutnya.
  void keluar() {
    if (_tunggu.isNotEmpty) {
      _tunggu.removeAt(0).complete();
      return;
    }
    if (_aktif > 0) _aktif--;
  }
}

class CbtApi {
  CbtApi._();

  static final Random _rng = Random();
  static const Duration _httpTimeout = Duration(seconds: 30);

  /// Batas permintaan bersamaan PER PERANGKAT. Google Apps Script hanya
  /// melayani sekitar 30 eksekusi bersamaan (kuota GLOBAL, bukan per akun),
  /// jadi setiap perangkat wajib menahan diri. Sisa bebannya dijaga oleh cache
  /// data login, autosave berkelompok, jitter, dan backoff bertingkat.
  static const int batasBersamaan = 30;

  /// Pembatas konkurensi untuk SEMUA aksi (login, soal, autosave, submit).
  static final CbtSemaphore semaphore = CbtSemaphore(batasBersamaan);

  /// POST ke endpoint Apps Script lalu ikuti 302-nya DENGAN GET TANPA header
  /// kustom dan TANPA body (RESEP TERVERIFIKASI terhadap deployment langsung):
  /// 1) POST /exec (+ Content-Type JSON, body JSON) -> 302 ke
  ///    script.googleusercontent.com/macros/echo?user_content_key=...
  /// 2) GET ke Location polos -> echo mengeksekusi request tersimpan dan
  ///    mengembalikan JSON hasil doPost (HTTP 200).
  /// KESALAHAN LAMA (jangan dikembalikan): re-POST body ke echo = 405, dan
  /// GET sambil membawa Content-Type JSON = di-bounce 302 balik ke /exec.
  /// SATU `http.Client` dipakai ulang untuk SEMUA request CBT (login, soal,
  /// autosave, submit). Ini penghemat terbesar dibanding `http.post()` /
  /// `http.get()` top-level: fungsi top-level membuka **koneksi TLS baru tiap
  /// request** (handshake ~200-800 ms di jaringan seluler), sedangkan client
  /// yang dipakai ulang memanfaatkan keep-alive sehingga request kedua dan
  /// seterusnya nyaris tanpa handshake — persis seperti web yang koneksinya
  /// sudah hangat.
  static http.Client? _client;

  /// Klien HTTP bersama; dibuat on-demand dan **dibuat ulang otomatis** bila
  /// sudah pernah ditutup lewat [tutupKlien]. `http.Client` yang sudah
  /// `close()` tidak boleh dipakai lagi — tanpa rekreasi ini, satu panggilan
  /// `tutupKlien()` akan mematikan SEMUA request CBT selamanya.
  static http.Client get client => _client ??= http.Client();

  /// Opsional: tutup koneksi bersama (dipakai pada test / kebersihan akhir
  /// sesi). Permintaan berikutnya membuka klien baru secara otomatis — aman
  /// dipanggil kapan pun.
  static void tutupKlien() {
    _client?.close();
    _client = null;
  }

  static Future<http.Response> _postIkutiRedirect(Uri uri, String body) async {
    const hdrs = {'Content-Type': 'application/json; charset=utf-8'};
    final resp = await client.post(uri, headers: hdrs, body: body);
    if (!{301, 302, 303, 307, 308}.contains(resp.statusCode)) return resp;
    final loc = resp.headers['location'];
    if (loc == null || loc.isEmpty) return resp;
    // Ikuti maksimal 3 hop dengan GET polos (tanpa header kustom / body).
    var next = Uri.parse(loc);
    for (var hop = 0; hop < 3; hop++) {
      final r2 = await client.get(next);
      if (!{301, 302, 303, 307, 308}.contains(r2.statusCode)) return r2;
      final l2 = r2.headers['location'];
      if (l2 == null || l2.isEmpty) return r2;
      next = Uri.parse(l2);
    }
    return client.get(next);
  }

  /// POST dengan retry meniru callServer() di Index.txt:
  /// - error "concurrent / too many / rate limit / exceeded / timeout" -> maksimal 5x;
  /// - error generik -> maksimal 2x;
  /// - backoff eksponensial 1s..10s + jitter acak (mengurai request serentak).
  /// Respons {success:false, error:...} dari server BUKAN kegagalan (dikembalikan
  /// apa adanya) — sama seperti withSuccessHandler pada web.
  static Future<Map<String, dynamic>> post(
    String action, {
    Map<String, dynamic> params = const {},
    int maxRetries = 5,
  }) async {
    final String baseUrl = kCbtUrlEfektif;
    if (baseUrl.isEmpty) {
      throw CbtApiException(
        'URL API CBT belum tersedia. Isi konstanta kCbtApiUrl di '
        'lib/cbt/cbt_api.dart dengan URL Web App Apps Script (berakhiran /exec), '
        'atau muat Daftar Ujian sekali agar URL terdeteksi otomatis.',
      );
    }
    final body = jsonEncode(<String, dynamic>{'action': action, ...params});
    final uri = Uri.parse(baseUrl);
    // Batas konkurensi PERANGKAT: satu perangkat tidak boleh punya lebih dari
    // [batasBersamaan] permintaan in-flight (autosave + retry + refresh
    // sekaligus) agar server tetap sanggup melayani 900 siswa serentak.
    // Slot SELALU dilepas lewat `finally`, termasuk saat rethrow.
    await semaphore.masuk();
    try {
      return await _postLoop(uri, body, maxRetries);
    } finally {
      semaphore.keluar();
    }
  }

  /// Badan retry POST — dipisah dari [post] supaya pelepasan slot semaphore
  /// dijamin oleh blok `finally` di pemanggil (termasuk jalur rethrow).
  static Future<Map<String, dynamic>> _postLoop(
      Uri uri, String body, int maxRetries) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final resp = await _postIkutiRedirect(uri, body).timeout(_httpTimeout);
        if (resp.statusCode == 405) {
          // Netral: jangan menggurui soal deploy — hanya fakta teknis.
          throw CbtApiException(
              'Server CBT menolak permintaan POST (HTTP 405).');
        }
        if (resp.statusCode != 200) {
          throw CbtApiException('Server merespons HTTP ${resp.statusCode}.');
        }
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is Map<String, dynamic>) return decoded;
        throw CbtApiException('Respons server tidak valid.');
      } catch (err) {
        // Error 405/URL belum di-set: langsung rethrow (tidak retry —
        // retry tidak menyelesaikan masalah deploy/konfigurasi).
        if (err is CbtApiException &&
            (err.message.startsWith('URL API CBT') ||
                err.message.startsWith('Server CBT'))) {
          rethrow;
        }
        final msg = err.toString().toLowerCase();
        final isIntensif = msg.contains('concurrent') ||
            msg.contains('too many') ||
            msg.contains('rate limit') ||
            msg.contains('exceeded') ||
            msg.contains('timeout') ||
            msg.contains('timed out') ||
            msg.contains('socket') ||
            // 404/429/5xx umumnya throttle/limit Google — retry penuh (5x).
            msg.contains('http 404') ||
            msg.contains('http 429') ||
            msg.contains('http 5');
        // Error generik juga di-retry tapi lebih sedikit (maks 2x) — pola callServer().
        final maxUntukIni = isIntensif ? maxRetries : min(2, maxRetries);
        if (attempt < maxUntukIni) {
          final delay = min(1000 * (1 << (attempt - 1)), 10000);
          final jitter = _rng.nextInt(delay + 1);
          await Future.delayed(Duration(milliseconds: delay + jitter));
          continue;
        }
        throw CbtApiException(
          'Tidak dapat terhubung ke server. Periksa koneksi internet, lalu coba lagi.',
        );
      }
    }
  }

  // ---------- Aksi (sama seperti fungsi google.script.run di Index.txt) ----------

  /// Data dropdown login: {kelasList, siswa: {kelas: [{nisn,nama}]}, wajibNisn}.
  static Future<Map<String, dynamic>> getDataLogin() => post('getDataLogin');

  /// login(nisn, kodeUjian) -> {success|sudahSelesai, soalList, ujian, ...}.
  static Future<Map<String, dynamic>> login(String nisn, String kodeUjian) =>
      post('login', params: {'nisn': nisn, 'kodeUjian': kodeUjian});

  static Future<Map<String, dynamic>> simpanJawabanBatch({
    required String nisn,
    required String kodeUjian,
    required String jawabanJSON,
    required String terakhir,
    int? startTimeMs,
  }) =>
      post('simpanJawabanBatch', params: {
        'nisn': nisn,
        'kodeUjian': kodeUjian,
        'jawabanJSON': jawabanJSON,
        'terakhir': terakhir,
        'startTimeMs': startTimeMs,
      });

  static Future<Map<String, dynamic>> ambilSoalTerbaru(
          String nisn, String kodeUjian) =>
      post('ambilSoalTerbaru', params: {'nisn': nisn, 'kodeUjian': kodeUjian});

  static Future<Map<String, dynamic>> selesaiUjian({
    required String nisn,
    required String kodeUjian,
    required String jawabanJSON,
    int? startTimeMs,
    int percobaanKlien = 0,
  }) =>
      post(
        'selesaiUjian',
        params: {
          'nisn': nisn,
          'kodeUjian': kodeUjian,
          'jawabanJSON': jawabanJSON,
          'startTimeMs': startTimeMs,
          'percobaanKlien': percobaanKlien,
        },
      );

  static Future<Map<String, dynamic>> mulaiRemedi(
          String nisn, String kodeUjian) =>
      post('mulaiRemedi', params: {'nisn': nisn, 'kodeUjian': kodeUjian});
}
