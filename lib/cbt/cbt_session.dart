// ==================== Sesi CBT (state + penyimpanan lokal) ====================
// Porting `state` + localStorage Index.txt ke Dart/SharedPreferences.
// Skema kunci identik web: cbt_sesi_/cbt_login_/cbt_pending_/cbt_final_.
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'cbt_models.dart';

class CbtSession {
  // ---------- mirror `state` di Index.txt ----------
  String nisn = '';
  String kodeUjian = '';
  List<SoalCbt> soalList = [];
  int idx = 0;
  int durasiUjianMenit = 60;
  int sisaDetik = 0;
  int? startTime; // epoch ms; null = belum mulai
  Map<String, String> jawabanTerpilih = {}; // noSoal -> 'A' / 'A|C' / ''
  Map<String, bool> raguRagu = {};
  List<int> urutanSoal = []; // indeks soal (acak bila acakSoal)
  Map<String, List<String>> urutanOpsi = {}; // noSoal -> urutan huruf A-E
  bool selesai = false;
  bool tampilNilai = true;
  bool acakSoal = true;
  bool acakOpsi = true;
  String siswaNama = '';
  String siswaKelas = '';
  String mapel = '';
  int percobaanRemedi = 0;
  bool sedangRemedi = false;
  RemediInfo? remediInfo;

  // Status kirim akhir (belum|ok|gagal|basi) — sumber teks "boleh menutup".
  String statusKirimFinal = 'belum';
  int kirimFinalGen = 0; // naik 1x saat sesi di-reset (remedi/kembali login)

  // Autosave
  bool modeOffline = false;
  bool adaPerubahan = false;
  final Set<String> dirtySet = {}; // noSoal (string) belum tersinkron

  final Random _rng = Random();

  // ---------- kunci penyimpanan (pola identik Index.txt) ----------
  static String keySesi(String nisn, String kode) => 'cbt_sesi_${nisn}_$kode';
  static String keyLogin(String nisn, String kode) => 'cbt_login_${nisn}_$kode';
  static String keyPending(String nisn, String kode) => 'cbt_pending_${nisn}_$kode';
  static String keyFinal(String nisn, String kode) => 'cbt_final_${nisn}_$kode';

  // ---------- acak & urutan (porting acakArray/pastikanUrutan*) ----------
  List<int> acakArray(List<int> arr) {
    final a = List<int>.from(arr);
    for (var i = a.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
    return a;
  }

  List<String> _acakHuruf() {
    final a = <String>['A', 'B', 'C', 'D', 'E'];
    for (var i = a.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
    return a;
  }

  /// Urutan lama yang masih valid DIPERTAHANKAN (pindah layar tidak mengacak ulang).
  void pastikanUrutanSoal() {
    final indeksSemua = List<int>.generate(soalList.length, (i) => i);
    if (urutanSoal.length == soalList.length) {
      final terurut = List<int>.from(urutanSoal)..sort();
      var sama = true;
      for (var i = 0; i < terurut.length; i++) {
        if (terurut[i] != indeksSemua[i]) {
          sama = false;
          break;
        }
      }
      if (sama) return;
    }
    urutanSoal = acakSoal ? acakArray(indeksSemua) : indeksSemua;
    urutanOpsi = {}; // bangun ulang sesuai setting acakOpsi aktif
  }

  void pastikanUrutanOpsi() {
    for (final s in soalList) {
      urutanOpsi[s.noSoal] ??= acakOpsi ? _acakHuruf() : <String>['A', 'B', 'C', 'D', 'E'];
    }
  }

  SoalCbt soalPadaPosisi(int i) => soalList[urutanSoal[i]];

  bool isTanpaBatas() => durasiUjianMenit <= 0;

  void hitungSisaDari() {
    if (isTanpaBatas()) {
      sisaDetik = -1;
      return;
    }
    final totalDetik = durasiUjianMenit * 60;
    if (startTime != null) {
      final sudahBerjalan =
          ((DateTime.now().millisecondsSinceEpoch - startTime!) / 1000).floor();
      sisaDetik = totalDetik - sudahBerjalan;
    } else {
      sisaDetik = totalDetik;
    }
  }

  /// Termasuk nilai '' — persis Object.keys() di JS.
  int get jumlahTerjawab => jawabanTerpilih.length;

  /// Kembali ke halaman login (kembaliKeLogin): hapus 4 kunci lokal + reset
  /// seluruh state per-ujian agar tidak bocor ke ujian berikutnya.
  Future<void> kembaliKeLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySesi(nisn, kodeUjian));
    await prefs.remove(keyLogin(nisn, kodeUjian));
    await prefs.remove(keyPending(nisn, kodeUjian));
    await prefs.remove(keyFinal(nisn, kodeUjian));
    batalkanKirimFinal();
    selesai = false;
    jawabanTerpilih = {};
    raguRagu = {};
    soalList = [];
    urutanSoal = [];
    urutanOpsi = {};
    idx = 0;
    startTime = null;
    durasiUjianMenit = 60;
    tampilNilai = true;
    acakSoal = true;
    acakOpsi = true;
    dirtySet.clear();
    adaPerubahan = false;
    modeOffline = false;
    statusKirimFinal = 'belum';
    sedangRemedi = false;
    remediInfo = null;
    siswaNama = '';
    siswaKelas = '';
    mapel = '';
    percobaanRemedi = 0;
  }

  /// Token generasi: retry final LAMA berhenti setelah sesi di-reset.
  void batalkanKirimFinal() => kirimFinalGen++;

  Map<String, dynamic> _toMap() => {
        'nisn': nisn,
        'kodeUjian': kodeUjian,
        'soalList': soalList.map((s) => s.toJson()).toList(),
        'idx': idx,
        'durasiUjianMenit': durasiUjianMenit,
        'startTime': startTime,
        'jawabanTerpilih': jawabanTerpilih,
        'raguRagu': raguRagu,
        'urutanSoal': urutanSoal,
        'urutanOpsi': urutanOpsi,
        'selesai': selesai,
        'tampilNilai': tampilNilai,
        'acakSoal': acakSoal,
        'acakOpsi': acakOpsi,
        'siswaNama': siswaNama,
        'siswaKelas': siswaKelas,
        'mapel': mapel,
        'percobaanRemedi': percobaanRemedi,
      };

  Future<void> simpanSesi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keySesi(nisn, kodeUjian), jsonEncode(_toMap()));
    } catch (_) {}
  }

  Future<void> simpanLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        keyLogin(nisn, kodeUjian),
        jsonEncode({'nisn': nisn, 'kode': kodeUjian}),
      );
    } catch (_) {}
  }

  /// Muat sesi tersimpan utk nisn+kode ini (porting muatan autoLogin).
  /// true bila ada & valid. Kompatibilitas: acakOpsi non-bool -> ikuti acakSoal.
  Future<bool> muatSesiTersimpan(String n, String k) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keySesi(n, k));
      if (raw == null) return false;
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return false;
      nisn = teksDari(m['nisn']).isNotEmpty ? teksDari(m['nisn']) : n;
      kodeUjian = teksDari(m['kodeUjian']).isNotEmpty ? teksDari(m['kodeUjian']) : k;
      final soalJson = m['soalList'];
      soalList = soalJson is List
          ? soalJson
              .whereType<Map>()
              .map((e) => SoalCbt.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <SoalCbt>[];
      idx = (m['idx'] is num) ? (m['idx'] as num).toInt() : 0;
      durasiUjianMenit =
          (m['durasiUjianMenit'] is num) ? (m['durasiUjianMenit'] as num).toInt() : 60;
      startTime = (m['startTime'] is num) ? (m['startTime'] as num).toInt() : null;
      jawabanTerpilih = m['jawabanTerpilih'] is Map
          ? (m['jawabanTerpilih'] as Map).map((k2, v) => MapEntry(teksDari(k2), teksDari(v)))
          : <String, String>{};
      raguRagu = m['raguRagu'] is Map
          ? (m['raguRagu'] as Map).map((k2, v) => MapEntry(teksDari(k2), v == true))
          : <String, bool>{};
      urutanSoal = m['urutanSoal'] is List
          ? (m['urutanSoal'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : <int>[];
      urutanOpsi = m['urutanOpsi'] is Map
          ? (m['urutanOpsi'] as Map).map((k2, v) => MapEntry(
              teksDari(k2),
              v is List ? v.map(teksDari).toList() : <String>[]))
          : <String, List<String>>{};
      selesai = m['selesai'] == true;
      tampilNilai = m['tampilNilai'] != false;
      acakSoal = m['acakSoal'] != false;
      acakOpsi = (m['acakOpsi'] is bool) ? m['acakOpsi'] as bool : acakSoal;
      siswaNama = teksDari(m['siswaNama']);
      siswaKelas = teksDari(m['siswaKelas']);
      mapel = teksDari(m['mapel']);
      percobaanRemedi =
          (m['percobaanRemedi'] is num) ? (m['percobaanRemedi'] as num).toInt() : 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cari kredensial tersimpan (cbt_login_*) utk auto-login saat layar dibuka.
  static Future<Map<String, String>?> cariKredensialTersimpan() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      if (k.startsWith('cbt_login_')) {
        try {
          final m = jsonDecode(prefs.getString(k) ?? '');
          if (m is Map) {
            return {'nisn': teksDari(m['nisn']), 'kode': teksDari(m['kode'])};
          }
        } catch (_) {}
      }
    }
    return null;
  }

  // ---------- antrian pending (masukPending/ambilPending/hapusPending) ----------
  Future<List<Map<String, dynamic>>> ambilPending() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(keyPending(nisn, kodeUjian)) ?? '[]';
      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> simpanPending(List<Map<String, dynamic>> arr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPending(nisn, kodeUjian), jsonEncode(arr));
  }

  Future<void> hapusPending(String json) async {
    final arr = await ambilPending();
    arr.removeWhere((j) => j['json'] == json);
    await simpanPending(arr);
  }

  // ---------- salinan jawaban akhir (write-through cbt_final_) ----------
  Future<void> simpanFinal(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFinal(nisn, kodeUjian), json);
  }

  Future<String?> ambilFinal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyFinal(nisn, kodeUjian));
  }

  Future<void> hapusFinal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyFinal(nisn, kodeUjian));
  }

  Future<void> hapusSesiDanLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySesi(nisn, kodeUjian));
    await prefs.remove(keyLogin(nisn, kodeUjian));
  }

  // ---------- cache data login (TTL 12 jam, hanya disimpan bila VALID) ----------
  // Daftar kelas/nama praktis tidak berubah, jadi cache dibuat panjang supaya
  // login massal (900 siswa) tidak menghantam server. Saat cache kedaluwarsa,
  // UI tetap memakai cache lebih dulu (stale-while-revalidate) lalu menyegarkan
  // di latar belakang — login tidak pernah menunggu jaringan.
  static const int loginDataTtlMs = 12 * 60 * 60 * 1000;

  /// Baca cache data login. Mengembalikan [CbtCacheLogin] berisi data + umur;
  /// `null` hanya bila cache belum ada / rusak. Data yang sudah kedaluwarsa
  /// TETAP dikembalikan (flag `kedaluwarsa` true) agar UI bisa instan.
  static Future<CbtCacheLogin?> bacaCacheDataLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cbt_datalogin_cache');
      if (raw == null) return null;
      final waktu =
          int.tryParse(prefs.getString('cbt_datalogin_time') ?? '') ?? 0;
      final umur = waktu <= 0
          ? loginDataTtlMs
          : DateTime.now().millisecondsSinceEpoch - waktu;
      return CbtCacheLogin(
        CbtDataLogin.fromJsonValid(jsonDecode(raw)),
        umur >= loginDataTtlMs,
        umur,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> simpanCacheDataLogin(CbtDataLogin dl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cbt_datalogin_cache', jsonEncode(dl.toJson()));
      await prefs.setString(
          'cbt_datalogin_time', DateTime.now().millisecondsSinceEpoch.toString());
    } catch (_) {}
  }
}

