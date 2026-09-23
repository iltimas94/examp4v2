// ==================== Layar Ujian Selesai ====================
// Porting halaman done Index.txt: detail, kotak skor, banner status kirim
// (ok/gagal/basi), retry kirim final ber-generasi, tombol Remedi.
import 'dart:async';

import 'package:flutter/material.dart';

import 'cbt_api.dart';
import 'cbt_info_screen.dart';
import 'cbt_models.dart';
import 'cbt_security.dart';
import 'cbt_session.dart';
import 'cbt_widgets.dart';

class CbtDoneScreen extends StatefulWidget {
  final CbtSession session;
  final String? pesanSelesai;
  final String? skorAkhir; // string dari server / null
  final String? banner; // 'ok' | 'gagal' | 'basi'
  final bool finalTertahan; // salinan final masih tertahan -> loop retry
  final bool tampilkanDetail;
  final int jumlahJawab;

  const CbtDoneScreen({
    super.key,
    required this.session,
    this.pesanSelesai,
    this.skorAkhir,
    this.banner,
    this.finalTertahan = false,
    this.tampilkanDetail = false,
    this.jumlahJawab = 0,
  });

  @override
  State<CbtDoneScreen> createState() => _CbtDoneScreenState();
}

class _CbtDoneScreenState extends State<CbtDoneScreen> {
  CbtSession get session => widget.session;
  late String _pesan;
  String? _skor;
  late bool _tampilDetail;
  bool _tombolRemedi = false;
  String _infoRemedi = '';
  bool _sedangRemedi = false;
  String _bannerTeks = '';
  Color _bannerBg = kCbtDanger;
  Color _bannerFg = kCbtDanger;
  bool _bannerTampil = false;
  String _teksBolehTutup = '';

  double? get _skorNum {
    final s = _skor;
    if (s == null) return null;
    return double.tryParse(s);
  }

  @override
  void initState() {
    super.initState();
    _pesan = widget.pesanSelesai ?? 'Terima kasih, jawabanmu sudah tersimpan.';
    _skor = widget.skorAkhir;
    _tampilDetail = widget.tampilkanDetail;
    final bannerAwal = widget.banner ?? session.statusKirimFinal;
    if (bannerAwal == 'ok' || bannerAwal == 'gagal' || bannerAwal == 'basi') {
      _setBanner(bannerAwal, ceritakan: false);
    }
    _perbaruiTombolRemedi(_skorNum, session.tampilNilai);
    _renderTeksBolehTutup();
    if (widget.finalTertahan) _upayakanKirimFinal();
  }

  /// Banner status pengiriman jawaban akhir (setBannerKirim).
  void _setBanner(String status, {bool ceritakan = true}) {
    session.statusKirimFinal =
        (status == 'ok') ? 'ok' : (status == 'basi' ? 'basi' : 'gagal');
    if (session.statusKirimFinal == 'ok') {
      _bannerTeks =
          '✅ Jawaban akhir BERHASIL TERKIRIM ke server. Semua jawabanmu sudah aman.';
      _bannerBg = kCbtPrimaryLight;
      _bannerFg = kCbtPrimaryDark;
    } else if (session.statusKirimFinal == 'basi') {
      _bannerTeks =
          '⚠️ Sesi ujian sudah di-reset di server. Login ulang agar sesi terbaru dimuat.';
      _bannerBg = const Color(0xFFfdecec);
      _bannerFg = kCbtDanger;
    } else {
      _bannerTeks =
          '❌ JAWABAN AKHIR BELUM TERKIRIM ke server (koneksi internet bermasalah).\n'
          'Sistem terus mencoba mengirim otomatis setiap beberapa detik.\n'
          'JANGAN tutup aplikasi ini sampai banner berubah menjadi ✅.\n'
          'SEGERA LAPORKAN ke admin/pengawas ujian agar jawaban dan nilaimu dapat diperiksa.';
      _bannerBg = const Color(0xFFfdecec);
      _bannerFg = kCbtDanger;
    }
    _bannerTampil = true;
    _renderTeksBolehTutup();
    if (ceritakan && mounted) setState(() {});
  }

  /// Sinkronkan tampilan tombol REMEDI (perbaruiTombolRemedi).
  void _perbaruiTombolRemedi(double? skor, bool tampilSkor) {
    if (session.sedangRemedi) session.sedangRemedi = false;
    final rd = session.remediInfo;
    bool tersedia = (rd != null && rd.tersedia) && tampilSkor;
    // Jaring pengaman: skor sudah capai batas -> remedi tutup.
    final double? batasRemedi = rd?.batas;
    if (tersedia && skor != null && batasRemedi != null && skor >= batasRemedi) {
      tersedia = false;
    }
    // Kuota habis -> sembunyikan.
    if (tersedia && rd != null && rd.sisa != 99 && rd.sisa <= 0) {
      tersedia = false;
    }
    if (tersedia && rd != null) {
      var infoTeks = 'Batas remedi: nilai < ${rd.batas}';
      if (rd.sisa != 99) {
        infoTeks += ' · Sisa percobaan: ${rd.sisa}x';
      } else {
        infoTeks += ' · Percobaan: tanpa batas';
      }
      _infoRemedi = infoTeks;
    }
    _tombolRemedi = tersedia;
    if (mounted) {
      setState(() {});
      _renderTeksBolehTutup();
    }
  }

  /// "Boleh menutup" hanya saat aman (renderTeksBolehTutup).
  void _renderTeksBolehTutup() {
    String teks = '';
    if (session.statusKirimFinal != 'ok') {
      teks = ''; // belum aman -> banner merah jadi acuan
    } else if (_tombolRemedi) {
      teks = 'Atau kerjakan remedi dengan tombol di atas.';
    } else {
      teks = 'Kamu boleh menutup aplikasi ini.';
    }
    _teksBolehTutup = teks;
    if (mounted) setState(() {});
  }

  // ---------- retry kirim final (upayakanKirimFinal, token generasi) ----------
  void _upayakanKirimFinal() {
    final gen = session.kirimFinalGen;
    Future<void> coba() async {
      if (gen != session.kirimFinalGen) return; // sesi di-reset: hentikan
      final finalJson = await session.ambilFinal();
      if (finalJson == null) return;
      try {
        final res = await CbtApi.selesaiUjian(
          nisn: session.nisn,
          kodeUjian: session.kodeUjian,
          jawabanJSON: finalJson,
          startTimeMs: session.startTime,
          percobaanKlien: session.percobaanRemedi,
        );
        if (gen != session.kirimFinalGen) return; // hasil basi: abaikan
        if (res['success'] == true) {
          await session.hapusFinal();
          await session.hapusSesiDanLogin();
          session.modeOffline = false;
          _setBanner('ok');
          _pesan = 'Jawaban akhir berhasil terkirim ke server. Terima kasih.';
          _tampilkanSkor(teksDari(res['skor']));
          if (mounted) {
            CbtNotifs.tampil(context,
                'Jawaban akhir berhasil terkirim ke server. Semua jawabanmu sudah aman.',
                tipe: 'sukses');
          }
        } else if (res['stale'] == true) {
          await session.hapusFinal();
          await session.simpanPending([]);
          session.modeOffline = false;
        } else {
          _setBanner('gagal');
          Timer(const Duration(seconds: 10), () => coba());
        }
      } catch (_) {
        if (gen != session.kirimFinalGen) return;
        _setBanner('gagal');
        Timer(const Duration(seconds: 10), () => coba());
      }
    }

    coba();
  }

  void _tampilkanSkor(String skorBaru) {
    if (session.tampilNilai == false) return;
    if (skorBaru.isEmpty) return;
    if (!mounted) return;
    setState(() => _skor = skorBaru);
  }

  /// Kembali ke halaman login dari layar selesai (btnDoneBack -> kembaliKeLogin).
  Future<void> _kembaliKeLogin() async {
    session.batalkanKirimFinal(); // hentikan retry final yg mungkin berjalan
    await session.kembaliKeLogin();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.settings.name == 'cbt-login');
  }

  // ---------- Remedi (klikRemedi + lakukanRemedi) ----------
  void klikRemedi() {
    Future<void> lanjut() async {
      if (session.nisn.isEmpty || session.kodeUjian.isEmpty) {
        final kred = await CbtSession.cariKredensialTersimpan();
        if (kred != null) {
          if (session.nisn.isEmpty) session.nisn = kred['nisn'] ?? '';
          if (session.kodeUjian.isEmpty) session.kodeUjian = kred['kode'] ?? '';
        }
      }
      if (session.nisn.isEmpty || session.kodeUjian.isEmpty) {
        if (mounted) {
          CbtNotifs.tampil(context,
              'Sesi tidak terbaca. Muat ulang aplikasi, login ulang, lalu tekan tombol Remedi lagi.',
              tipe: 'error');
        }
        return;
      }
      if (!mounted) return;
      CbtNotifs.konfirmasi(
        context,
        'Mulai REMEDI? Jawaban ujian sebelumnya akan dikosongkan dan nilaimu akan dihitung ulang dari hasil remedi.',
        lakukanRemedi,
      );
    }

    lanjut();
  }

  Future<void> lakukanRemedi() async {
    if (_sedangRemedi) return;
    setState(() => _sedangRemedi = true);
    if (mounted) {
      CbtLoading.show(context, 'Menyiapkan ujian remedi...',
          'Mohon tunggu, jangan tutup halaman ini.');
    }
    try {
      final res = await CbtApi.mulaiRemedi(session.nisn, session.kodeUjian)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      CbtLoading.hide();
      setState(() => _sedangRemedi = false);
      if (res['success'] != true) {
        final err = teksDari(res['error']);
        CbtNotifs.tampil(context,
            'Gagal memulai remedi: ${err.isEmpty ? 'coba lagi.' : err}',
            tipe: 'error');
        return;
      }
      // Sesi LAMA sengaja di-reset: hentikan retry basi & buang salinan final.
      session.batalkanKirimFinal();
      await session.hapusFinal();
      await session.simpanPending([]);
      final daftar = res['soalList'] is List
          ? (res['soalList'] as List)
              .whereType<Map>()
              .map((e) => SoalCbt.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <SoalCbt>[];
      session.soalList = daftar;
      final uj = res['ujian'] is Map
          ? Map<String, dynamic>.from(res['ujian'])
          : <String, dynamic>{};
      session.durasiUjianMenit =
          num.tryParse(teksDari(uj['durasiUjianMenit']))?.toInt() ?? 0;
      session.startTime = uj['startTime'] is num
          ? (uj['startTime'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch;
      session.jawabanTerpilih = {};
      session.raguRagu = {};
      session.urutanSoal = [];
      session.urutanOpsi = {};
      session.dirtySet.clear();
      session.adaPerubahan = false;
      session.modeOffline = false;
      session.selesai = false;
      session.idx = 0;
      session.mapel = teksDari(uj['mapel']);
      if (uj['tampilNilai'] is bool) {
        session.tampilNilai = uj['tampilNilai'] as bool;
      }
      if (uj['acakSoal'] is bool) session.acakSoal = uj['acakSoal'] as bool;
      if (uj['acakOpsi'] is bool) session.acakOpsi = uj['acakOpsi'] as bool;
      session.percobaanRemedi = int.tryParse(teksDari(res['percobaan'])) ?? 0;
      session.sedangRemedi = true;
      session.statusKirimFinal = 'belum';
      _bannerTampil = false;
      session.pastikanUrutanSoal();
      session.pastikanUrutanOpsi();
      await session.simpanLogin();
      await session.simpanSesi();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => CbtInfoScreen(session: session)),
        (r) => r.settings.name == 'cbt-login',
      );
    } on TimeoutException {
      if (!mounted) return;
      CbtLoading.hide();
      setState(() => _sedangRemedi = false);
      CbtNotifs.tampil(
          context,
          'Server tidak merespons selama 20 detik. Periksa koneksi internet, lalu tekan tombol Remedi sekali lagi.',
          tipe: 'error');
    } on CbtApiException catch (e) {
      if (!mounted) return;
      CbtLoading.hide();
      setState(() => _sedangRemedi = false);
      CbtNotifs.tampil(
          context, 'Gagal terhubung ke server: ${e.message}. Coba lagi.',
          tipe: 'error');
    }
  }

  Widget _barisDetail(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label,
                style: const TextStyle(fontSize: 13.5, color: kCbtTextMuted)),
          ),
          Expanded(
            child: Text(
              nilai.isEmpty ? '-' : nilai,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: kCbtText),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jumlahJawabTampil =
        widget.jumlahJawab > 0 ? widget.jumlahJawab : session.jumlahTerjawab;
    final adaSkor = session.tampilNilai && _skor != null && _skor!.isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _kembaliKeLogin();
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
                    const Text('✅',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 46)),
                    const SizedBox(height: 6),
                    const Text(
                      'Ujian Selesai',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kCbtPrimaryDark),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _pesan,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, height: 1.5, color: kCbtText),
                    ),
                    if (_tampilDetail) ...[
                      const SizedBox(height: 18),
                      _barisDetail('Nama', session.siswaNama),
                      _barisDetail('Kelas', session.siswaKelas),
                      _barisDetail('NISN', session.nisn),
                      _barisDetail('Mata pelajaran', session.mapel),
                      _barisDetail('Kode ujian', session.kodeUjian),
                      _barisDetail('Soal terjawab',
                          '$jumlahJawabTampil dari ${session.soalList.length}'),
                    ],
                    if (adaSkor) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: kCbtPrimaryLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kCbtPrimary),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'NILAI KAMU',
                              style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w700,
                                  color: kCbtPrimaryDark),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _skor!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  color: kCbtPrimaryDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_bannerTampil) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _bannerBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _bannerFg),
                        ),
                        child: Text(
                          _bannerTeks,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: _bannerFg),
                        ),
                      ),
                    ],
                    if (_tombolRemedi) ...[
                      const SizedBox(height: 18),
                      Text(
                        _infoRemedi,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 13, color: kCbtTextMuted),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kCbtAccent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFa9b8ac),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          onPressed: _sedangRemedi ? null : klikRemedi,
                          child: Text(_sedangRemedi
                              ? 'Menyiapkan remedi...'
                              : '🔄 Kerjakan REMEDI'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kCbtPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _kembaliKeLogin,
                        child: const Text('Kembali ke Halaman Awal'),
                      ),
                    ),
                    if (_teksBolehTutup.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _teksBolehTutup,
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
}


