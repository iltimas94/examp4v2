// ==================== Layar Ujian — inti CBT Alternatif Family Link ====================
// Porting halaman exam Index.txt: timer, nav-grid, opsi (radio/checkbox sesuai
// kunci), autosave batch (dirtySet + throttle + pending retry), ragu-ragu,
// refresh soal, konfirmasi selesai, submit final write-through + retry.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'cbt_api.dart';
import 'cbt_done_screen.dart';
import 'cbt_models.dart';
import 'cbt_richtext.dart';
import 'cbt_security.dart';
import 'cbt_session.dart';
import 'cbt_widgets.dart';

class CbtExamScreen extends StatefulWidget {
  final CbtSession session;
  const CbtExamScreen({super.key, required this.session});
  @override
  State<CbtExamScreen> createState() => _CbtExamScreenState();
}

class _CbtExamScreenState extends State<CbtExamScreen> {
  CbtSession get session => widget.session;

  Timer? _timerGlobal;
  Timer? _backupTimer;
  Timer? _throttleTimer;
  Timer? _retryTimer;
  Timer? _statusClearTimer;
  bool sendInFlight = false;
  bool _navTerbuka = false;
  bool _sedangKirim = false; // proses tombol Kirim (flush + tanya selesai)
  bool _sedangRefresh = false;
  bool _prosesSelesai = false;
  String _statusSave = '';

  // Konstanta autosave identik Index.txt.
  static const int _ambangKirim = 15;
  static const Duration _jedaCadangan = Duration(seconds: 60);
  static const Duration _jedaMinAutosave = Duration(seconds: 10);
  int _lastKirimOtomatis = 0;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    session.pastikanUrutanSoal();
    session.pastikanUrutanOpsi();
    session.hitungSisaDari();
    if (!session.isTanpaBatas() && session.sisaDetik <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CbtNotifs.tampil(context, 'Waktu ujian sudah habis.',
            tipe: 'warning', cbOk: prosesSelesaiUjian);
      });
    }
    _mulaiTimerGlobal();
    _mulaiBackupTimer();
    _cobaRetryPilih();
  }

  @override
  void dispose() {
    _timerGlobal?.cancel();
    _backupTimer?.cancel();
    _throttleTimer?.cancel();
    _retryTimer?.cancel();
    _statusClearTimer?.cancel();
    super.dispose();
  }

  // ---------- timer global (countdown + auto-submit waktu habis) ----------
  void _mulaiTimerGlobal() {
    _timerGlobal?.cancel();
    if (session.isTanpaBatas()) return;
    _timerGlobal = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || session.selesai) return;
      session.sisaDetik--;
      setState(() {});
      if (session.sisaDetik <= 0) {
        _timerGlobal?.cancel();
        CbtNotifs.tampil(context,
            'Waktu habis! Jawaban Anda akan dikirim otomatis.',
            tipe: 'warning', cbOk: prosesSelesaiUjian);
      }
    });
  }

  // Cadangan: kirim jawaban belum-terkirim tiap 60 detik walau tak pindah soal.
  void _mulaiBackupTimer() {
    _backupTimer?.cancel();
    _backupTimer = Timer.periodic(_jedaCadangan, (_) {
      if (!session.selesai &&
          !session.modeOffline &&
          session.dirtySet.isNotEmpty) {
        kirimKeSheet(force: false);
      }
    });
  }

  String _tampilanTimer() {
    if (session.isTanpaBatas()) return 'Tanpa Batas';
    if (session.sisaDetik < 0) return '00:00';
    final jam = session.sisaDetik ~/ 3600;
    final mnt = (session.sisaDetik % 3600) ~/ 60;
    final dtk = session.sisaDetik % 60;
    final mm = mnt < 10 ? '0$mnt' : '$mnt';
    final ss = dtk < 10 ? '0$dtk' : '$dtk';
    return jam > 0 ? '$jam:$mm:$ss' : '$mm:$ss';
  }

  bool get _timerKritis =>
      !session.isTanpaBatas() && session.sisaDetik >= 0 && session.sisaDetik <= 300;

  /// Status save sesaat (auto-hilang 1.6 dtk) — pola setStatus().
  void setStatus(String txt) {
    if (!mounted) return;
    setState(() => _statusSave = txt);
    _statusClearTimer?.cancel();
    if (txt.isNotEmpty) {
      _statusClearTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted && _statusSave == txt) setState(() => _statusSave = '');
      });
    }
  }

  // ---------- autosave (throttle + kirimKeSheet + pending retry) ----------
  Future<void> upayaKirimOtomatis() async {
    final sisa = _jedaMinAutosave.inMilliseconds -
        (DateTime.now().millisecondsSinceEpoch - _lastKirimOtomatis);
    if (sisa > 0) {
      // Dunda SATU kali dgn jitter 0-1.5 dtk (gelombang antar-siswa menyebar).
      _throttleTimer ??= Timer(
        Duration(milliseconds: sisa + _rng.nextInt(1500)),
        () {
          _throttleTimer = null;
          if (!session.selesai &&
              !session.modeOffline &&
              session.dirtySet.length >= _ambangKirim) {
            kirimKeSheet(force: false);
          }
        },
      );
      return;
    }
    if (session.dirtySet.length >= _ambangKirim) kirimKeSheet(force: false);
  }

  /// Kirim SELURUH jawaban terkini (idempotent), single-flight.
  Future<void> kirimKeSheet({required bool force, VoidCallback? onDone}) async {
    if (sendInFlight) {
      Timer(const Duration(milliseconds: 400),
          () => kirimKeSheet(force: force, onDone: onDone));
      return;
    }
    if (!force && session.dirtySet.isEmpty) {
      onDone?.call();
      return;
    }
    session.adaPerubahan = session.dirtySet.isNotEmpty;
    final json = jsonEncode(session.jawabanTerpilih);
    final dikirim = Set<String>.from(session.dirtySet);
    setStatus(session.modeOffline ? 'Menyimpan... (saat online)' : 'Menyimpan...');
    sendInFlight = true;
    if (!force) _lastKirimOtomatis = DateTime.now().millisecondsSinceEpoch;
    try {
      final res = await CbtApi.simpanJawabanBatch(
        nisn: session.nisn,
        kodeUjian: session.kodeUjian,
        jawabanJSON: json,
        terakhir: DateTime.now().toIso8601String(),
        startTimeMs: session.startTime,
      );
      sendInFlight = false;
      if (res['success'] == true) {
        // Hanya soal yang terkirim kali ini dihapus dari dirtySet.
        for (final nd in dikirim) {
          session.dirtySet.remove(nd);
        }
        session.adaPerubahan = session.dirtySet.isNotEmpty;
        session.modeOffline = false;
        setStatus('Tersimpan');
      } else {
        await _masukPending(json);
      }
      onDone?.call();
      if (session.dirtySet.isNotEmpty) {
        Timer(const Duration(milliseconds: 600), () => kirimKeSheet(force: false));
      }
    } catch (e) {
      sendInFlight = false;
      await _masukPending(json);
      onDone?.call();
      debugPrint('simpanJawabanBatch gagal: $e');
    }
  }

  Future<void> _masukPending(String json) async {
    session.modeOffline = true;
    final arr = await session.ambilPending();
    arr.add({'json': json, 'ts': DateTime.now().toIso8601String()});
    if (arr.length > 5) arr.removeAt(0);
    await session.simpanPending(arr);
    setStatus('Pengiriman GAGAL - tetap di halaman ini. Mengirim ulang otomatis... '
        'Jika terus gagal, laporkan ke admin/pengawas ujian.');
    _upayakanKirim();
  }

  /// Retry tiap 10 detik selama ada job pending (upayakanKirim).
  void _upayakanKirim() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      _kirimJobTertunda();
    });
  }

  Future<void> _kirimJobTertunda() async {
    if (sendInFlight) return;
    final arr = await session.ambilPending();
    if (arr.isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    final job = arr.last;
    final jsonJob = teksDari(job['json']);
    setStatus('Mengirim ulang jawaban yang gagal...');
    try {
      final res = await CbtApi.simpanJawabanBatch(
        nisn: session.nisn,
        kodeUjian: session.kodeUjian,
        jawabanJSON: jsonJob,
        terakhir: DateTime.now().toIso8601String(),
        startTimeMs: session.startTime,
      );
      if (res['success'] == true) {
        await session.hapusPending(jsonJob);
        session.dirtySet.clear();
        session.adaPerubahan = false;
        session.modeOffline = false;
        setStatus('Tersimpan');
      }
    } catch (e) {
      debugPrint('simpanJawabanBatch:retry gagal: $e');
    }
  }

  Future<void> _cobaRetryPilih() async {
    final arr = await session.ambilPending();
    if (arr.isNotEmpty) {
      _upayakanKirim();
      _kirimJobTertunda();
    }
  }

  // ---------- interaksi soal (pilihOpsi / ragu / nav / home / refresh) ----------
  void pilihOpsi(String huruf, SoalCbt soal, {required bool checked}) {
    final no = soal.noSoal;
    final String nilaiBaru;
    if (!soal.isMulti) {
      if (!checked) return; // radio: hanya saat benar-benar terpilih
      nilaiBaru = huruf;
    } else {
      // Checkbox: bangun ulang dari pilihan aktif (idempotent, kebal dbl-fire).
      final set = (session.jawabanTerpilih[no] ?? '')
          .split('|')
          .where((h) => h.isNotEmpty)
          .toSet();
      checked ? set.add(huruf) : set.remove(huruf);
      final urutan = session.urutanOpsi[no] ?? const ['A', 'B', 'C', 'D', 'E'];
      nilaiBaru = urutan.where(set.contains).join('|');
    }
    session.jawabanTerpilih[no] = nilaiBaru;
    session.adaPerubahan = true;
    session.dirtySet.add(no);
    session.simpanSesi();
    upayaKirimOtomatis();
    setStatus('Tersimpan (lokal)');
    setState(() {});
  }

  void toggleRagu() {
    final soal = session.soalPadaPosisi(session.idx);
    session.raguRagu[soal.noSoal] = !(session.raguRagu[soal.noSoal] ?? false);
    session.simpanSesi();
    setState(() {});
  }

  void _keSoal(int posisi) {
    upayaKirimOtomatis();
    session.idx = posisi;
    _navTerbuka = false;
    setState(() {});
  }

  void soalSebelumnya() {
    if (session.idx > 0) {
      upayaKirimOtomatis();
      session.idx--;
      setState(() {});
    }
  }

  void soalBerikutnya() {
    if (session.idx < session.soalList.length - 1) {
      upayaKirimOtomatis();
      session.idx++;
      setState(() {});
    }
  }

  void _hentikanSemuaTimer() {
    _timerGlobal?.cancel();
    _timerGlobal = null;
    _backupTimer?.cancel();
    _backupTimer = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _statusClearTimer?.cancel();
    _lastKirimOtomatis = 0;
  }

  /// Home: kembali halaman login & kosongkan sesi (keluarKeLogin).
  void keluarKeLogin() {
    // DIKUNCI: keluar dari ujian wajib kunci (kode admin) — sama seperti X.
    CbtNotifs.konfirmasiKunci(
      context,
      'Keluar ke halaman awal? Sesi ujian ini akan dihapus dari perangkat ini.',
      () async {
        _hentikanSemuaTimer();
        await session.kembaliKeLogin();
        if (mounted) {
          Navigator.of(context)
              .popUntil((r) => r.settings.name == 'cbt-login');
        }
      },
      ambilKode: CbtSecurityController.instance.kodeAdminSiap,
    );
  }

  /// Refresh soal (ambilSoalTerbaru) — jawaban lama tetap dipertahankan.
  void refreshSoal() {
    CbtNotifs.konfirmasi(
      context,
      'Muat ulang soal dari versi terbaru? Jawaban yang sudah dipilih tetap dipertahankan.',
      lakukanRefreshSoal,
    );
  }

  Future<void> lakukanRefreshSoal() async {
    if (_sedangRefresh) return;
    setState(() => _sedangRefresh = true);
    try {
      final res = await CbtApi.ambilSoalTerbaru(session.nisn, session.kodeUjian);
      if (!mounted) return;
      setState(() => _sedangRefresh = false);
      final daftarBaru = res['soalList'] is List
          ? (res['soalList'] as List)
              .whereType<Map>()
              .map((e) => SoalCbt.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <SoalCbt>[];
      if (res['success'] == true && daftarBaru.isNotEmpty) {
        final jawabanLama = session.jawabanTerpilih;
        session.soalList = daftarBaru;
        final jawabanServer = res['jawabanTerpilih'] is Map
            ? (res['jawabanTerpilih'] as Map)
                .map((k, v) => MapEntry(teksDari(k), teksDari(v)))
            : <String, String>{};
        session.jawabanTerpilih = {...jawabanServer, ...jawabanLama};
        session.urutanSoal = [];
        session.urutanOpsi = {};
        session.pastikanUrutanSoal();
        session.pastikanUrutanOpsi();
        if (session.idx >= session.soalList.length) session.idx = 0;
        session.simpanSesi();
        setState(() {});
        CbtNotifs.tampil(context,
            'Soal berhasil diperbarui (${session.soalList.length} soal).',
            tipe: 'sukses');
      } else {
        CbtNotifs.tampil(
            context,
            teksDari(res['error']).isEmpty
                ? 'Gagal mengambil soal terbaru.'
                : teksDari(res['error']),
            tipe: 'error');
      }
    } catch (e) {
      debugPrint('refreshSoal gagal: $e');
      if (mounted) setState(() => _sedangRefresh = false);
      CbtNotifs.tampil(context, 'Gagal terhubung ke server.', tipe: 'error');
    }
  }

  // ---------- konfirmasi selesai (kirimLaluTanyaSelesai + hitung status) ----------
  Future<void> kirimLaluTanyaSelesai() async {
    if (_sedangKirim) return;
    setState(() => _sedangKirim = true);
    setStatus('Menyimpan semua jawaban ke server...');
    if (session.dirtySet.isEmpty) {
      setState(() => _sedangKirim = false);
      await konfirmasiSelesai();
      return;
    }
    await kirimKeSheet(force: true, onDone: () {
      if (mounted) setState(() => _sedangKirim = false);
      konfirmasiSelesai();
    });
  }

  Future<void> konfirmasiSelesai() async {
    final total = session.soalList.length;
    final terjawab = session.jumlahTerjawab;
    final pending = await session.ambilPending();
    final finalAda = (await session.ambilFinal()) != null;
    final belumSinkron = session.dirtySet.isNotEmpty ||
        pending.isNotEmpty ||
        session.modeOffline ||
        finalAda;
    final statusTeks = belumSinkron
        ? '⚠️ PERHATIAN: ada jawaban yang BELUM TERKIRIM ke server (koneksi bermasalah).\n'
            'Sistem akan terus mencoba mengirim otomatis setelah ujian diakhiri.\n'
            'Jika pengiriman tetap gagal, LAPORKAN ke admin/pengawas ujian.\n'
        : 'Semua jawaban sudah dikirim.\n';
    if (!mounted) return;
    final ya = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Selesai Ujian?',
            textAlign: TextAlign.center,
            style: TextStyle(color: kCbtPrimaryDark, fontWeight: FontWeight.w800)),
        content: Text(
          'Terjawab: $terjawab dari $total soal.\n'
          '${statusTeks}Mengakhiri ujian?',
          textAlign: TextAlign.left,
          style: const TextStyle(fontSize: 14.5, height: 1.45),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          // TANPA Expanded/flex: actions AlertDialog dibungkus OverflowBar
          // (bukan RenderFlex) — flex bikin popup jadi kotak putih beku
          // (bug yang sama dengan CbtNotifs). Lebar tombol tetap.
          SizedBox(
            width: 116,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kCbtSlate,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(
            width: 130,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kCbtDanger,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ya, Selesai',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
    if (ya == true) prosesSelesaiUjian();
  }

  // ---------- proses selesai (write-through final + retry) ----------
  Future<void> prosesSelesaiUjian() async {
    if (_prosesSelesai) return;
    _prosesSelesai = true;
    _hentikanSemuaTimer();
    session.selesai = true;
    setStatus('Mengirim jawaban akhir...');
    if (mounted) {
      CbtLoading.show(context, 'Mengirim jawaban akhir & menghitung skor...',
          'Mohon tunggu, jangan tutup halaman ini.');
    }
    final json = jsonEncode(session.jawabanTerpilih);
    // Salinan jawaban akhir disimpan LEBIH DULU — bila submit gagal, salinan
    // inilah yang dikirim ulang otomatis oleh layar selesai.
    await session.simpanFinal(json);
    int retrySubmit = 0;
    late final Future<void> Function() cobaSubmit;
    late final void Function(String) gagalSubmit;

    gagalSubmit = (alasan) {
      if (retrySubmit < 3) {
        retrySubmit++;
        if (mounted) {
          CbtLoading.show(
              context,
              'Mengirim jawaban akhir & menghitung skor... (percobaan ${retrySubmit + 1}/4)',
              'Server sibuk, sistem mencoba lagi otomatis. Mohon tunggu, jangan tutup halaman ini.');
        }
        Timer(const Duration(seconds: 5), () => cobaSubmit());
      } else {
        session.modeOffline = true;
        if (mounted) {
          CbtLoading.hide();
          CbtNotifs.tampil(
              context,
              'Pengiriman jawaban akhir GAGAL ($alasan). Jangan tutup halaman - sistem akan terus mencoba mengirim otomatis.\nSegera laporkan ke admin/pengawas ujian.',
              tipe: 'error');
        }
        _akhirSelesai(skor: null, terkirim: false);
      }
    };

    cobaSubmit = () async {
      try {
        final res = await CbtApi.selesaiUjian(
          nisn: session.nisn,
          kodeUjian: session.kodeUjian,
          jawabanJSON: json,
          startTimeMs: session.startTime,
          percobaanKlien: session.percobaanRemedi,
        );
        if (!mounted) return;
        if (res['success'] == true) {
          CbtLoading.hide();
          await session.hapusFinal();
          final skorTeks = teksDari(res['skor']);
          _akhirSelesai(skor: skorTeks.isEmpty ? null : skorTeks, terkirim: true);
          return;
        }
        if (res['stale'] == true) {
          await session.hapusFinal();
          await session.simpanPending([]); // buang pending basi
          session.modeOffline = false;
          _akhirSelesaiBasi();
          return;
        }
        gagalSubmit(teksDari(res['error']).isEmpty
            ? 'server belum menerima jawaban akhir'
            : teksDari(res['error']));
      } catch (_) {
        gagalSubmit('tidak dapat terhubung ke server');
      }
    };

    // Jitter 0-10 dtk agar submit serentak antar siswa tidak menumpuk.
    Timer(Duration(milliseconds: _rng.nextInt(10000)), () => cobaSubmit());
  }

  void _akhirSelesai({required String? skor, required bool terkirim}) {
    CbtLoading.hide();
    final mapelTeks = session.mapel.isEmpty ? 'ujian' : session.mapel;
    final pesan = terkirim
        ? 'Ujian $mapelTeks (kode ${session.kodeUjian}) telah selesai. Terima kasih, jawabanmu sudah tersimpan.'
        : 'Ujian $mapelTeks (kode ${session.kodeUjian}) telah selesai. NAMUN jawaban akhir BELUM terkirim - lihat status di bawah.';
    // Sesi barusan hasil REMEDI: satu percobaan terpakai.
    final rd = session.remediInfo;
    if (session.sedangRemedi && rd != null && rd.sisa != 99) {
      session.remediInfo = RemediInfo(
          tersedia: rd.tersedia,
          batas: rd.batas,
          sisa: rd.sisa - 1,
          kodeSoal: rd.kodeSoal,
          mapel: rd.mapel);
    }
    session.statusKirimFinal = terkirim ? 'ok' : 'gagal';
    if (terkirim) session.hapusSesiDanLogin();
    _keHalamanSelesai(
        pesan: pesan,
        skor: skor,
        banner: terkirim ? 'ok' : 'gagal',
        finalTertahan: !terkirim,
        // Baris detail (nama/kelas/nisn/mapel/terjawab) ikut tampil —
        // seperti halaman selesai pada web CBT asli.
        tampilkanDetail: true);
  }

  void _akhirSelesaiBasi() {
    CbtLoading.hide();
    _hentikanSemuaTimer();
    session.statusKirimFinal = 'basi';
    _keHalamanSelesai(
      pesan: 'Pengiriman jawaban akhir DIABAIKAN: sesi ujian ini sudah di-reset di '
          'server (mis. karena REMEDI dikerjakan dari perangkat lain). '
          'Login ulang untuk melihat status terbaru.',
      skor: null,
      banner: 'basi',
    );
    if (mounted) {
      CbtNotifs.tampil(
          context,
          'Sesi ujian sudah di-reset di server (mis. karena REMEDI). Login ulang, '
          'lalu periksa status terbaru.',
          tipe: 'warning');
    }
  }

  // ---------- widget bantu: kartu opsi + nav grid ----------
  Widget _kartuOpsi(SoalCbt soal, String huruf, String teks, bool checked) {
    final isMulti = soal.isMulti;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!isMulti) {
            if (checked) return; // radio: no-op saat sudah terpilih
            pilihOpsi(huruf, soal, checked: true);
          } else {
            pilihOpsi(huruf, soal, checked: !checked);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: checked ? kCbtPrimaryLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: checked ? kCbtPrimary : kCbtBorder, width: 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isMulti
                    ? (checked
                        ? Icons.check_box
                        : Icons.check_box_outline_blank)
                    : (checked
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                color: checked ? kCbtPrimary : kCbtTextMuted,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CbtRichText.rich(
                  teks,
                  style: const TextStyle(
                      fontSize: 15, height: 1.5, color: kCbtText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Daftar nomor soal: isi (hijau) / ragu (kuning) / aktif (border hijau).
  Widget _navGrid() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(4),
        child: GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            for (var posisi = 0; posisi < session.urutanSoal.length; posisi++)
              _navItem(posisi),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int posisi) {
    final s = session.soalList[session.urutanSoal[posisi]];
    final terisi = (session.jawabanTerpilih[s.noSoal] ?? '').isNotEmpty;
    final ragu = session.raguRagu[s.noSoal] ?? false;
    final aktif = posisi == session.idx;
    Color bg = Colors.white;
    Color fg = kCbtText;
    Color border = kCbtBorder;
    double bw = 1.5;
    if (terisi) {
      bg = kCbtPrimary;
      fg = Colors.white;
      border = kCbtPrimary;
    }
    if (ragu) {
      bg = kCbtAccent;
      fg = Colors.white;
      border = kCbtAccent;
    }
    if (aktif) {
      bw = 2;
      if (!terisi && !ragu) border = kCbtPrimary;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _keSoal(posisi),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: bw),
        ),
        child: Text(
          '${posisi + 1}',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData ikon, String label, VoidCallback? onTap) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: label,
        onPressed: onTap,
        icon: Icon(ikon, size: 20),
      ),
    );
  }

  Widget _tombolAksi(String teks, Color warna, VoidCallback? onTap,
      {double tinggi = 50, double fontSize = 16}) {
    return SizedBox(
      height: tinggi,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: warna,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFa9b8ac),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onTap,
        child: Text(teks,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
      ),
    );
  }

  /// Kotak legenda warna nav-grid.
  Widget _legenda(Color warna, String teks, {Color? garis}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: warna,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: garis ?? warna),
          ),
        ),
        const SizedBox(width: 6),
        Text(teks, style: const TextStyle(fontSize: 12, color: kCbtTextMuted)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (session.soalList.isEmpty || session.urutanSoal.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ujian')),
        body: const Center(
            child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Soal tidak tersedia. Kembali lalu login ulang.',
              textAlign: TextAlign.center),
        )),
      );
    }
    final soal = session.soalPadaPosisi(session.idx);
    final isLast = session.idx == session.soalList.length - 1;
    final rawDipilih = session.jawabanTerpilih[soal.noSoal] ?? '';
    final setDipilih =
        rawDipilih.split('|').where((h) => h.isNotEmpty).toSet();
    final urutan =
        session.urutanOpsi[soal.noSoal] ?? const ['A', 'B', 'C', 'D', 'E'];
    final opsiWidgets = <Widget>[];
    for (final huruf in urutan) {
      final teks = soal.opsi[huruf] ?? '';
      if (teks.isEmpty) continue;
      opsiWidgets.add(_kartuOpsi(soal, huruf, teks, setDipilih.contains(huruf)));
    }
    final isRagu = session.raguRagu[soal.noSoal] ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) keluarKeLogin();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFf3f7f3),
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
                    // Header: identitas + tombol home/refresh + timer.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${session.siswaNama} - ${session.siswaKelas}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              Text(session.mapel,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: kCbtTextMuted)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                _iconBtn(Icons.home, 'Keluar / Home',
                                    keluarKeLogin),
                                const SizedBox(width: 8),
                                _iconBtn(Icons.refresh, 'Refresh Soal',
                                    _sedangRefresh ? null : refreshSoal),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _timerKritis
                                    ? const Color(0xFFfdecec)
                                    : kCbtPrimaryLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _tampilanTimer(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: _timerKritis
                                      ? kCbtDanger
                                      : kCbtPrimaryDark,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => setState(() => _navTerbuka = !_navTerbuka),
                      child: Text(
                        'Soal ${session.idx + 1} / ${session.soalList.length} (Lihat Daftar)',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kCbtPrimaryDark,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                    if (_sedangRefresh)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (_navTerbuka) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kCbtBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _navGrid(),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                _legenda(kCbtPrimary, 'Terisi'),
                                _legenda(kCbtAccent, 'Ragu-ragu'),
                                _legenda(Colors.white, 'Belum diisi',
                                    garis: kCbtBorder),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],




                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf7fbf7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kCbtBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: kCbtPrimary),
                                ),
                                child: Text(
                                  'Soal ${session.idx + 1}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: kCbtPrimaryDark),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  soal.isMulti
                                      ? 'Pilih SEMUA jawaban yang benar'
                                      : 'Pilih satu jawaban',
                                  style: const TextStyle(
                                      fontSize: 12, color: kCbtTextMuted),
                                ),
                              ),
                              if (isRagu)
                                const Text('🤔',
                                    style: TextStyle(fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          CbtRichText.block(soal.pertanyaan),
                          if (soal.gambarUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 260),
                              child: Image.network(
                                soal.gambarAman,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...opsiWidgets,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _tombolAksi(
                              '⬅️ Kembali',
                              kCbtSlate,
                              session.idx > 0 ? soalSebelumnya : null,
                              fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _tombolAksi(
                              isRagu ? '🤔 Ragu ✓' : '🤔 Ragu-Ragu',
                              isRagu ? kCbtAccent : kCbtSlate,
                              toggleRagu,
                              fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: isLast
                              ? _tombolAksi(
                                  '✅ Selesai',
                                  kCbtPrimary,
                                  _sedangKirim ? null : kirimLaluTanyaSelesai,
                                  fontSize: 14)
                              : _tombolAksi('Lanjut ➡️', kCbtPrimary,
                                  soalBerikutnya,
                                  fontSize: 14),
                        ),
                      ],
                    ),
                    if (_statusSave.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _statusSave,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12.5, color: kCbtTextMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _keHalamanSelesai({
    required String pesan,
    required String? skor,
    required String banner,
    bool finalTertahan = false,
    bool tampilkanDetail = false,
    int jumlahJawab = 0,
  }) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CbtDoneScreen(
          session: session,
          pesanSelesai: pesan,
          skorAkhir: skor,
          banner: banner,
          finalTertahan: finalTertahan,
          tampilkanDetail: tampilkanDetail,
          jumlahJawab: jumlahJawab,
        ),
      ),
    );
  }
}




