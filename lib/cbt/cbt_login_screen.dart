// ==================== Layar Login — CBT Alternatif Family Link ====================
// Porting halaman login Index.txt (dropdown kelas/nama, NISN wajib, kode
// ujian, auto-login sesi tersimpan, muat data login cache/server).
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cbt_api.dart';
import 'cbt_done_screen.dart';
import 'cbt_exam_screen.dart';
import 'cbt_info_screen.dart';
import 'cbt_models.dart';
import 'cbt_security.dart';
import 'cbt_session.dart';
import 'cbt_widgets.dart';

/// Syarat keamanan login CBT: NISN yang diketik WAJIB cocok dengan NISN milik
/// nama yang dipilih di dropdown. Berlaku untuk SEMUA login (tidak peduli flag
/// `wajibNisn` dari server). Mengembalikan null = lolos, atau pesan error.
String? validasiNisnLogin({
  required String diketik,
  required String nisnTerpilih,
  required String namaTerpilih,
}) {
  final bersih = diketik.replaceAll(RegExp(r'\D'), '');
  if (bersih.isEmpty) return 'NISN wajib diketik sesuai nama yang kamu pilih.';
  final a = bersih.padLeft(10, '0');
  final b = nisnTerpilih.padLeft(10, '0');
  if (a != b) {
    return 'NISN yang kamu ketik tidak cocok dengan nama "$namaTerpilih" '
        'yang dipilih. Periksa kembali NISN-mu.';
  }
  return null;
}

class CbtLoginScreen extends StatefulWidget {
  const CbtLoginScreen({super.key});
  @override
  State<CbtLoginScreen> createState() => _CbtLoginScreenState();
}

class _CbtLoginScreenState extends State<CbtLoginScreen> {
  /// Satu objek sesi dipakai sepanjang alur (login -> info -> ujian -> selesai).
  final CbtSession session = CbtSession();
  final TextEditingController _kodeCtrl = TextEditingController();
  final TextEditingController _nisnCtrl = TextEditingController();

  CbtDataLogin? dataLogin;
  bool _muatData = true;
  bool _proses = false;
  bool _retryDisabled = false;
  bool _sesiTersimpanAda = false;
  String _errorMessage = '';
  String _dataErrorMessage = '';
  String _sumberStatus = '';
  String? _kelasTerpilih;
  String? _nisnTerpilih;
  String? _namaTerpilih;

  @override
  void initState() {
    super.initState();
    // Pre-locking + monitor keamanan SEGERA saat masuk alur CBT.
    CbtSecurityController.instance.mulai();
    _inisialisasi();
  }

  Future<void> _inisialisasi() async {
    // Cadangan deteksi URL API: tarik dari link ujian terakhir yang tersimpan
    // (kalau Daftar Ujian belum sempat memuatnya).
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('lastExamUrl') ?? '';
      if (last.isNotEmpty) deteksiUrlApiDariLink(last);
    } catch (_) {}
    final kred = await CbtSession.cariKredensialTersimpan();
    if (kred != null &&
        (kred['nisn'] ?? '').isNotEmpty &&
        (kred['kode'] ?? '').isNotEmpty) {
      session.nisn = kred['nisn']!;
      session.kodeUjian = kred['kode']!;
      await _autoLogin();
    } else {
      await muatDataLoginDropdown();
    }
  }

  // ---------- muat data login: cache lokal 12 jam -> server ----------
  // [diam] = true dipakai untuk penyegaran latar belakang (stale-while-revalidate):
  // UI tetap memakai cache, tidak masuk mode loading, dan kegagalan jaringan TIDAK
  // menampilkan banner error — login 900 siswa tidak boleh terganggu refresh.
  Future<void> muatDataLoginDropdown(
      {bool paksaServer = false, bool diam = false}) async {
    if (!mounted) return;
    if (!diam) {
      setState(() {
        _dataErrorMessage = '';
        _muatData = true;
        _sumberStatus = '';
      });
    }
    if (!paksaServer) {
      final cache = await CbtSession.bacaCacheDataLogin();
      if (cache != null && mounted) {
        setState(() {
          dataLogin = cache.data;
          _muatData = false;
          _sumberStatus = '✔ Sumber daftar: cache aplikasi'
              '${cache.data.versi > 0 ? ' v${cache.data.versi}' : ''}';
        });
        // Cache kedaluwarsa: tetap pakai cache (instan) lalu segarkan diam-diam.
        if (cache.kedaluwarsa) {
          unawaited(muatDataLoginDropdown(paksaServer: true, diam: true));
        }
        return;
      }
    }
    if (!mounted) return;
    setState(
        () => _sumberStatus = paksaServer ? 'SERVER (dipilih manual)' : 'SERVER');
    try {
      final res = await CbtApi.getDataLogin();
      if (res['success'] == false) {
        // Penyegaran latar: jangan ganggu UI, cache tetap dipakai.
        if (diam) return;
        // Data kosong/tidak valid dari server -> pesan terlihat + Coba Lagi.
        setState(() {
          _muatData = false;
          _dataErrorMessage = teksDari(res['error']).isEmpty
              ? 'Data siswa dari server kosong. Pastikan sheet "siswa" berisi data (kolom NISN/NAMA/KELAS), lalu klik Coba Lagi.'
              : teksDari(res['error']);
          _sumberStatus = '';
        });
        return;
      }
      final dl = CbtDataLogin.fromJsonValid(res); // validasi keras
      await CbtSession.simpanCacheDataLogin(dl);
      if (!mounted) return;
      setState(() {
        dataLogin = dl;
        _muatData = false;
        _sumberStatus = '✔ Sumber daftar: SERVER';
      });
    } catch (e) {
      debugPrint('Gagal ambil data login: $e');
      if (!mounted) return;
      setState(() {
        _muatData = false;
        // Pesan spesifik (mis. "doPost belum ter-deploy"/HTTP error) jangan
        // ditimpa pesan generik — penyebab sebenarnya harus terlihat.
        _dataErrorMessage = e is CbtApiException
            ? e.message
            : 'Gagal terhubung ke server saat memuat daftar siswa. '
                'Periksa koneksi, lalu klik Coba Lagi.';
        _sumberStatus = '';
      });
    }
  }

  void _pilihKelas(String? kelas) {
    setState(() {
      _kelasTerpilih = kelas;
      _nisnTerpilih = null;
      _namaTerpilih = null;
      _nisnCtrl.clear(); // sinkronNisnLogin: kosongkan NISN lama
    });
  }

  void _pilihNama(String? nisn) {
    final list = (dataLogin?.siswa[_kelasTerpilih] ?? <CbtSiswa>[])
        .where((s) => s.nisn == nisn);
    setState(() {
      _nisnTerpilih = nisn;
      _namaTerpilih = list.isNotEmpty ? list.first.nama : null;
      _nisnCtrl.clear(); // kosongkan NisnLogin saat ganti nama
    });
  }

  // ---------- prosesLogin (validasi client + panggil login) ----------
  Future<void> _prosesLogin() async {
    final kode = _kodeCtrl.text.trim();
    final nisn = _nisnTerpilih ?? '';
    setState(() => _errorMessage = '');
    if (nisn.isEmpty || kode.isEmpty) {
      setState(() => _errorMessage = 'Pilih nama, lalu isi Kode Ujian wajib diisi.');
      return;
    }
    // KEAMANAN: NISN ketik WAJIB cocok dengan NISN nama yang dipilih —
    // berlaku untuk SEMUA login, tidak peduli flag server.
    final galatNisn = validasiNisnLogin(
      diketik: _nisnCtrl.text,
      nisnTerpilih: nisn,
      namaTerpilih: _namaTerpilih ?? '',
    );
    if (galatNisn != null) {
      setState(() => _errorMessage = galatNisn);
      return;
    }
    setState(() => _proses = true);
    if (mounted) {
      CbtLoading.show(context, 'Memverifikasi login & memuat soal...',
          'Mohon tunggu, jangan tutup halaman ini.');
    }
    await Future.delayed(Duration(milliseconds: 300 + Random().nextInt(1700)));
    try {
      final res = await CbtApi.login(nisn, kode);
      if (!mounted) return;
      CbtLoading.hide();
      setState(() => _proses = false);
      if (res['sudahSelesai'] == true) {
        await _tampilkanSudahSelesai(res);
        return;
      }
      if (res['success'] != true) {
        setState(() => _errorMessage = teksDari(res['error']));
        return;
      }
      _terapkanLoginSukses(res, gabungJawaban: false);
      await session.simpanLogin();
      await session.simpanSesi();
      if (res['belumMulai'] == true) {
        _bukaInfo();
      } else {
        _bukaUjian();
      }
    } on CbtApiException catch (e) {
      if (!mounted) return;
      CbtLoading.hide();
      setState(() {
        _proses = false;
        // Error konfigurasi/deploy (URL API / doPost / HTTP) tampil apa adanya;
        // hanya error jaringan biasa yang memakai pesan generik.
        final spesifik = e.message.startsWith('URL API') ||
            e.message.startsWith('Server CBT') ||
            e.message.startsWith('Server merespons');
        _errorMessage =
            spesifik ? e.message : 'Gagal terhubung ke server. Coba lagi.';
      });
    }
  }

  /// Terapkan respons login ke sesi. gabungJawaban=true -> jalur autoLogin.
  void _terapkanLoginSukses(Map<String, dynamic> res, {required bool gabungJawaban}) {
    final siswa = res['siswa'] is Map
        ? Map<String, dynamic>.from(res['siswa'])
        : <String, dynamic>{};
    final uj = res['ujian'] is Map
        ? Map<String, dynamic>.from(res['ujian'])
        : <String, dynamic>{};
    final daftar = res['soalList'] is List
        ? (res['soalList'] as List)
            .whereType<Map>()
            .map((e) => SoalCbt.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <SoalCbt>[];
    if (daftar.isNotEmpty) session.soalList = daftar;
    session.durasiUjianMenit =
        num.tryParse(teksDari(uj['durasiUjianMenit']))?.toInt() ?? 0;
    final jawabanServer = res['jawabanTerpilih'] is Map
        ? (res['jawabanTerpilih'] as Map)
            .map((k, v) => MapEntry(teksDari(k), teksDari(v)))
        : <String, String>{};
    if (gabungJawaban) {
      session.jawabanTerpilih = {...jawabanServer, ...session.jawabanTerpilih};
    } else {
      session.nisn = teksDari(siswa['nisn']);
      session.kodeUjian = teksDari(uj['kode']);
      session.jawabanTerpilih = jawabanServer;
      session.raguRagu = {};
      session.dirtySet.clear();
      session.adaPerubahan = false;
      session.modeOffline = false;
      session.idx = 0;
    }
    if (uj['startTime'] is num) session.startTime = (uj['startTime'] as num).toInt();
    session.siswaNama = teksDari(siswa['nama']);
    session.siswaKelas = teksDari(siswa['kelas']);
    session.mapel = teksDari(uj['mapel']);
    if (uj['tampilNilai'] is bool) session.tampilNilai = uj['tampilNilai'] as bool;
    if (uj['acakSoal'] is bool) session.acakSoal = uj['acakSoal'] as bool;
    if (uj['acakOpsi'] is bool) session.acakOpsi = uj['acakOpsi'] as bool;
    session.percobaanRemedi = int.tryParse(teksDari(res['percobaan'])) ?? 0;
    session.pastikanUrutanSoal();
    session.pastikanUrutanOpsi();
  }

  // ---------- autoLogin (kredensial tersimpan, jitter 0-8000ms) ----------
  Future<void> _autoLogin() async {
    _sesiTersimpanAda =
        await session.muatSesiTersimpan(session.nisn, session.kodeUjian);
    if (!mounted) return;
    CbtLoading.show(context, 'Memuat data login & menyiapkan soal...',
        'Mohon tunggu sebentar, jangan tutup halaman ini.');
    await Future.delayed(Duration(milliseconds: Random().nextInt(8000)));
    try {
      final res = await CbtApi.login(session.nisn, session.kodeUjian);
      if (!mounted) return;
      CbtLoading.hide();
      if (res['sudahSelesai'] == true) {
        await _tampilkanSudahSelesai(res);
        return;
      }
      if (res['success'] == true) {
        _terapkanLoginSukses(res, gabungJawaban: true);
        await session.simpanSesi();
        if (res['belumMulai'] == true) {
          _bukaInfo();
        } else {
          _bukaUjian();
        }
      } else {
        await _tampilkanDariCacheAtauForm();
      }
    } catch (e) {
      debugPrint('autoLogin gagal: $e');
      await _tampilkanDariCacheAtauForm();
    }
  }

  /// Auto-login gagal: pakai sesi cache (mode offline) atau tampilkan form.
  Future<void> _tampilkanDariCacheAtauForm() async {
    if (!mounted) return;
    CbtLoading.hide();
    if (_sesiTersimpanAda && session.soalList.isNotEmpty) {
      session.modeOffline = true;
      session.pastikanUrutanSoal();
      session.pastikanUrutanOpsi();
      session.hitungSisaDari();
      if (!session.isTanpaBatas() && session.sisaDetik <= 0) {
        await muatDataLoginDropdown();
        return;
      }
      _bukaUjian();
    } else {
      await muatDataLoginDropdown();
    }
  }

  /// Login cabang sudahSelesai: langsung ke halaman "selesai" dgn nilai lama
  /// + info remedi (tampilkanSudahSelesai).
  Future<void> _tampilkanSudahSelesai(Map<String, dynamic> res) async {
    final siswa = res['siswa'] is Map
        ? Map<String, dynamic>.from(res['siswa'])
        : <String, dynamic>{};
    final uj = res['ujian'] is Map
        ? Map<String, dynamic>.from(res['ujian'])
        : <String, dynamic>{};
    final nisnBaru = teksDari(siswa['nisn']);
    final kodeBaru = teksDari(uj['kode']);
    if (nisnBaru.isNotEmpty) session.nisn = nisnBaru;
    if (kodeBaru.isNotEmpty) session.kodeUjian = kodeBaru;
    session.siswaNama = teksDari(siswa['nama']);
    session.siswaKelas = teksDari(siswa['kelas']);
    session.mapel = teksDari(uj['mapel']);
    if (uj['tampilNilai'] is bool) session.tampilNilai = uj['tampilNilai'] as bool;
    if (uj['acakSoal'] is bool) session.acakSoal = uj['acakSoal'] as bool;
    if (uj['acakOpsi'] is bool) session.acakOpsi = uj['acakOpsi'] as bool;
    session.percobaanRemedi = int.tryParse(teksDari(res['percobaan'])) ?? 0;
    session.remediInfo = res['remedi'] is Map
        ? RemediInfo.fromJson(Map<String, dynamic>.from(res['remedi']))
        : null;
    final jmlJawab =
        (res['jumlahJawab'] is num) ? (res['jumlahJawab'] as num).toInt() : 0;
    final skor = res['skor'];
    final skorTeks =
        (skor == null || teksDari(skor).isEmpty) ? null : teksDari(skor);
    // Salinan jawaban akhir masih tertahan? -> banner merah + retry otomatis.
    final finalTertahan = (await session.ambilFinal()) != null;
    session.statusKirimFinal = finalTertahan ? 'gagal' : 'ok';
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CbtDoneScreen(
          session: session,
          skorAkhir: skorTeks,
          tampilkanDetail: true,
          jumlahJawab: jmlJawab,
          finalTertahan: finalTertahan,
        ),
      ),
    );
  }

  void _bukaInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CbtInfoScreen(session: session)),
    );
  }

  void _bukaUjian() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CbtExamScreen(session: session)),
    );
  }

  /// Keluar total dari alur CBT (kembali ke Daftar Ujian): hapus sesi lokal
  /// lalu lepas keamanan (monitor/secure/brightness + pre-lock).
  Future<void> _keluarAlur() async {
    await session.kembaliKeLogin();
    await CbtSecurityController.instance.akhiriSesi();
    if (mounted) Navigator.of(context).pop();
  }

  void _konfirmasiKeluar() {
    // Kunci keluar: wajib kunci (kode admin dari sheet) — sama seperti
    // layar kunci anti-cheat. Fallback konfirmasi biasa bila kode tidak ada.
    CbtNotifs.konfirmasiKunci(
      context,
      'Keluar dari CBT Alternatif Family Link? Sesi ujian di perangkat ini akan dihapus.',
      _keluarAlur,
      ambilKode: CbtSecurityController.instance.kodeAdminSiap,
    );
  }

  @override
  void dispose() {
    _kodeCtrl.dispose();
    _nisnCtrl.dispose();
    super.dispose();
  }

  InputDecoration _deko(String label, {String? hint}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kCbtBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kCbtBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kCbtPrimary, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final daftarNama = (_kelasTerpilih == null)
        ? const <CbtSiswa>[]
        : (dataLogin?.siswa[_kelasTerpilih] ?? const <CbtSiswa>[]);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _konfirmasiKeluar();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFf3f7f3),
        appBar: AppBar(
          title: const Text('CBT Alternatif Family Link'),
          leading:
              IconButton(icon: const Icon(Icons.close), onPressed: _konfirmasiKeluar),
        ),
        body: CbtSecurityController.instance.wrap(
          context,
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kCbtBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: kCbtPrimary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Text('📚', style: TextStyle(fontSize: 26)),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CBT Alternatif Family Link',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: kCbtPrimaryDark)),
                              SizedBox(height: 2),
                              Text('SMPN 4 Malang',
                                  style: TextStyle(
                                      fontSize: 13, color: kCbtTextMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: kCbtDanger,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_errorMessage,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14, height: 1.4)),
                      ),
                    if (_dataErrorMessage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFfdecec),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFf5c2c2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_dataErrorMessage,
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF7f1d1d))),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kCbtDanger,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 38),
                                    ),
                                    onPressed: _retryDisabled
                                        ? null
                                        : () async {
                                            setState(() => _retryDisabled = true);
                                            await muatDataLoginDropdown();
                                            if (mounted) {
                                              Timer(const Duration(seconds: 10), () {
                                                if (mounted) {
                                                  setState(() =>
                                                      _retryDisabled = false);
                                                }
                                              });
                                            }
                                          },
                                    child: Text(
                                        _retryDisabled ? 'Mencoba…' : 'Coba Lagi',
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kCbtSlate,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 38),
                                    ),
                                    onPressed: () =>
                                        muatDataLoginDropdown(paksaServer: true),
                                    child: const Text('Muat via Server',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Pilih Kelas',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kCbtTextMuted)),
                        ),
                        // Refresh daftar kelas & nama kapan pun (cache 12 jam
                        // jarang berubah — tarik server hanya bila perlu).
                        IconButton(
                          tooltip: 'Perbarui daftar kelas & nama dari server',
                          visualDensity: VisualDensity.compact,
                          iconSize: 19,
                          onPressed: _muatData
                              ? null
                              : () =>
                                  muatDataLoginDropdown(paksaServer: true),
                          icon: _muatData
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh,
                                  color: kCbtTextMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_muatData && dataLogin == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 3))),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: _kelasTerpilih,
                        decoration: _deko('Kelas'),
                        hint: const Text('-- pilih kelas --'),
                        items: (dataLogin?.kelasList ?? const <String>[])
                            .map((k) => DropdownMenuItem(
                                value: k,
                                child: Text(k, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: _pilihKelas,
                      ),
                    if (_sumberStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 10, left: 2),
                        child: Text(_sumberStatus,
                            style: const TextStyle(
                                fontSize: 11.5, color: kCbtTextMuted)),
                      )
                    else
                      const SizedBox(height: 12),
                    const Text('Pilih Nama',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kCbtTextMuted)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _nisnTerpilih,
                      decoration: _deko('Nama'),
                      hint: const Text('-- pilih nama --'),
                      isExpanded: true,
                      items: daftarNama
                          .map((s) => DropdownMenuItem(
                              value: s.nisn,
                              child: Text(s.nama, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: daftarNama.isEmpty ? null : _pilihNama,
                    ),
                    const SizedBox(height: 12),
                    const Text('NISN (wajib diketik)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kCbtTextMuted)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nisnCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 12,
                      decoration: _deko('NISN',
                          hint: 'Ketik NISN yang sesuai nama di atas'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Kode Ujian',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kCbtTextMuted)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _kodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration:
                          _deko('Kode Ujian', hint: 'Masukkan Kode Ujian'),
                      onSubmitted: (_) => _prosesLogin(),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCbtPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        disabledBackgroundColor: const Color(0xFFa9b8ac),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _proses ? null : _prosesLogin,
                      child: Text(_proses ? 'Memverifikasi...' : 'Mulai Ujian'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



