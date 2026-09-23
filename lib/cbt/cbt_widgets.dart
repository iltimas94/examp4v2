// ==================== Widget umum alur CBT ====================
// Overlay loading + palet warna — identik halaman Index.txt.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kCbtPrimary = Color(0xFF15803d);
const Color kCbtPrimaryDark = Color(0xFF14532d);
const Color kCbtPrimaryLight = Color(0xFFeafbef);
const Color kCbtAccent = Color(0xFFca8a04);
const Color kCbtAccentLight = Color(0xFFfef9e7);
const Color kCbtDanger = Color(0xFFb91c1c);
const Color kCbtText = Color(0xFF1a2b20);
const Color kCbtTextMuted = Color(0xFF5b6b60);
const Color kCbtBorder = Color(0xFFdfe6df);
const Color kCbtSlate = Color(0xFF57606f);

/// Overlay loading full-screen (tampilLoading/sembunyikanLoading).
class CbtLoading {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String teks, [String hint = '']) {
    // Bila sudah tampil: ganti isi (mis. update teks retry 2/4).
    if (_entry != null) {
      _entry!.remove();
      _entry = null;
    }
    _entry = OverlayEntry(
      builder: (_) => Container(
        color: const Color(0xF2ffffff),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(strokeWidth: 5, color: kCbtPrimary),
                ),
                const SizedBox(height: 16),
                Text(
                  teks,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kCbtText),
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: kCbtTextMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _NotifItem {
  final String pesan;
  final String tipe;
  final VoidCallback? cbOk;
  final bool duaTombol;

  /// Kunci password opsional (konfirmasiKunci): bila ada, dialog mewajibkan
  /// input kunci yang cocok sebelum cbOk dijalankan.
  final Future<String?> Function()? ambilKode;
  _NotifItem(this.pesan, this.tipe, this.cbOk, this.duaTombol,
      [this.ambilKode]);
}

/// Modal notif berantre (porting bukaNotif/bukaNotifBerikutnya): popup terbuka
/// TIDAK pernah ditimpa — notif berikutnya masuk antrean, tampil satu per satu.
class CbtNotifs {
  static bool _terbuka = false;
  static final List<_NotifItem> _antrean = [];

  /// Root navigator key — dipasang pada MaterialApp (main.dart) agar popup CBT
  /// tetap bisa tampil walau layar pemanggilnya sudah ditutup/di-dispose.
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  /// Pengganti alert(): satu tombol OK (+ cbOk opsional setelah OK ditekan).
  static Future<void> tampil(
    BuildContext context,
    String pesan, {
    String tipe = 'info',
    VoidCallback? cbOk,
  }) =>
      _buka(context, pesan, tipe, cbOk, false);

  /// Pengganti confirm(): tombol Batal/Ya, cbYa dipanggil bila siswa setuju.
  static Future<void> konfirmasi(
    BuildContext context,
    String pesan,
    VoidCallback cbYa, {
    String tipe = 'warning',
  }) =>
      _buka(context, pesan, tipe, cbYa, true);

  /// Konfirmasi DIKUNCI password (kunci keluar): ambilKode() mengambil kunci
  /// (kode admin dari sheet — sama dengan layar kunci anti-cheat). Bila kunci
  /// tersedia, dialog mewajibkan input yang cocok sebelum cbYa dijalankan;
  /// bila tidak tersedia, jatuh ke konfirmasi biasa (fallback agar siswa
  /// tidak terkunci total).
  static Future<void> konfirmasiKunci(
    BuildContext context,
    String pesan,
    VoidCallback cbYa, {
    required Future<String?> Function() ambilKode,
  }) =>
      _buka(context, pesan, 'warning', cbYa, true, ambilKode);

  /// Antrean diproses lewat root navigator (bukan BuildContext layar lama yang
  /// mungkin sudah di-dispose) supaya popup berikutnya tetap muncul.
  static Future<void> _prosesAntrean() async {
    while (_antrean.isNotEmpty) {
      final nxt = _antrean.removeAt(0);
      final ctx = navKey.currentContext;
      if (ctx == null) break;
      await _buka(ctx, nxt.pesan, nxt.tipe, nxt.cbOk, nxt.duaTombol,
          nxt.ambilKode);
    }
  }

  static Future<void> _buka(
    BuildContext context,
    String pesan,
    String tipe,
    VoidCallback? cb,
    bool duaTombol, [
    Future<String?> Function()? ambilKode,
  ]) async {
    if (_terbuka) {
      _antrean.add(_NotifItem(pesan, tipe, cb, duaTombol, ambilKode));
      return;
    }
    _terbuka = true;
    // Kunci keluar: ambil kode admin dulu. Bila tidak tersedia, jatuh ke
    // konfirmasi biasa (fallback) agar siswa tidak terkunci total.
    String? kunci;
    if (ambilKode != null) {
      try {
        kunci = (await ambilKode())?.trim();
      } catch (e) {
        debugPrint('[CBT] gagal ambil kunci: $e');
      }
      if (kunci != null && kunci.isEmpty) kunci = null;
      if (kunci == null) {
        debugPrint('[CBT] kunci tidak tersedia — konfirmasi tanpa password.');
        pesan = '$pesan\n\n(Kunci tidak tersedia — konfirmasi tanpa password.)';
      }
    }
    final terkunci = kunci != null;
    final ctrlKunci = TextEditingController();
    var salahKunci = false;
    final cfg = _konfig(tipe);
    // Context root navigator diambil SESUDAH await (aman dari async-gap);
    // popup tetap tayang walau layar pemanggil sudah ter-dispose.
    final ctxShow = navKey.currentContext;
    if (ctxShow == null || !ctxShow.mounted) {
      // Root navigator belum siap/ter-mount: batalkan popup ini; antrean
      // diproses pada panggilan berikutnya (_terbuka sudah di-reset).
      _terbuka = false;
      return;
    }
    final ok = await showDialog<bool>(
      context: ctxShow,
      barrierDismissible: false,
      builder: (ctx) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.94, end: 1.0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        // StatefulBuilder agar pesan "kunci salah" bisa rebuild in-dialog.
        child: StatefulBuilder(
          builder: (ctxDlg, setSB) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          actionsPadding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: cfg.bg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(cfg.ikon, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(height: 12),
              Text(
                terkunci ? 'Kunci Keluar' : cfg.judul,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: kCbtPrimaryDark),
              ),
              const SizedBox(height: 8),
              Text(
                pesan,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: kCbtText, height: 1.4),
              ),
              if (terkunci) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrlKunci,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(letterSpacing: 5, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Masukkan kunci',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kCbtBorder, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => setSB(() {
                    if (ctrlKunci.text.trim() == kunci) {
                      Navigator.of(ctxDlg).pop(true);
                    } else {
                      salahKunci = true;
                      ctrlKunci.clear();
                    }
                  }),
                ),
                if (salahKunci)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Kunci salah. Coba lagi.',
                      style: TextStyle(
                          color: kCbtDanger,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
              ],
            ],
          ),
          // JANGAN pakai Expanded di actions: AlertDialog Flutter 3.32
          // membungkus actions dengan OverflowBar (bukan RenderFlex) —
          // Expanded menyebabkan ParentDataWidget error dan popup tampil
          // sebagai kotak putih yang tidak bisa disentuh. Lebar tombol dibuat
          // tetap (sama lebar) agar berdampingan rapi.
          actions: [
            if (duaTombol)
              SizedBox(
                width: 116,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: kCbtSlate,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            SizedBox(
              width: duaTombol ? 116 : 150,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: tipe == 'error' ? kCbtDanger : kCbtPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  // Kunci aktif: input harus cocok dulu sebelum popup tertutup.
                  if (terkunci && ctrlKunci.text.trim() != kunci) {
                    setSB(() {
                      salahKunci = true;
                      ctrlKunci.clear();
                    });
                    HapticFeedback.mediumImpact();
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: Text(
                  duaTombol ? 'Ya, Lanjut' : 'OK',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
            ),
          ),
        ),
      );
    // ctrlKunci sengaja TIDAK di-dispose: route mungkin masih animasi keluar
    // (controller dipakai TextField) — biarkan ter-GC bersama dialog.
    _terbuka = false;
    // cbOk dipanggil SETELAH popup tertutup (spt tekanNotifOk) — abaikan error
    // callback agar tidak mati senyap.
    if (ok == true && cb != null) {
      try {
        cb();
      } catch (e) {
        debugPrint('[CBT] callback popup error: $e');
      }
    }
    if (_antrean.isNotEmpty) {
      await _prosesAntrean();
    }
  }

  static ({String ikon, Color bg, String judul}) _konfig(String tipe) {
    switch (tipe) {
      case 'sukses':
        return (ikon: '✅', bg: kCbtPrimaryLight, judul: 'Berhasil');
      case 'error':
        return (ikon: '❌', bg: const Color(0xFFfdecec), judul: 'Gagal');
      case 'warning':
        return (ikon: '⚠️', bg: kCbtAccentLight, judul: 'Perhatian');
      default:
        return (ikon: 'ℹ️', bg: const Color(0xFFeaf2fd), judul: 'Info');
    }
  }
}
