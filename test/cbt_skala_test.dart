// ==================== Uji skalabilitas CBT (900 siswa / limit 30) ====================
// Semaphore: kuota Google Apps Script ~30 eksekusi bersamaan — perangkat
// wajib menahan diri. Klien shared: keep-alive TLS (rekreasi setelah tutup).
import 'dart:async';

import 'package:examp4/cbt/cbt_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbtSemaphore (limit 30 eksekusi bersamaan Apps Script)', () {
    test('tidak pernah melebihi batas meski 100 permintaan berbarengan', () async {
      final s = CbtSemaphore(30);
      var maksTerlihat = 0;
      final jobs = List.generate(100, (_) async {
        await s.masuk();
        if (s.aktif > maksTerlihat) maksTerlihat = s.aktif;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        s.keluar();
      });
      await Future.wait(jobs);
      expect(maksTerlihat, lessThanOrEqualTo(30));
      expect(s.aktif, 0);
      expect(s.menunggu, 0);
    });

    test('slot dilepas ke antrean berikutnya tanpa kebocoran', () async {
      final s = CbtSemaphore(2);
      await s.masuk();
      await s.masuk();
      final ketiga = s.masuk(); // pasti mengantre
      expect(s.menunggu, 1);
      expect(s.aktif, 2);
      s.keluar(); // serah-terima langsung ke pengantri
      await ketiga;
      expect(s.aktif, 2);
      expect(s.menunggu, 0);
      s.keluar();
      s.keluar();
      expect(s.aktif, 0);
    });
  });

  group('Klien HTTP shared (hemat TLS handshake)', () {
    test('tutupKlien() tidak mematikan request: klien dibuat ulang otomatis', () {
      final a = CbtApi.client;
      CbtApi.tutupKlien();
      final b = CbtApi.client; // wajib klien BARU, bukan yang sudah closed
      expect(identical(a, b), isFalse);
      CbtApi.tutupKlien(); // bersih-bersih akhir test
    });
  });
}
