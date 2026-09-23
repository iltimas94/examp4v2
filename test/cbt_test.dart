import 'package:examp4/cbt/cbt_api.dart';
import 'package:examp4/cbt/cbt_models.dart';
import 'package:examp4/cbt/cbt_richtext.dart';
import 'package:examp4/cbt/cbt_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Kartu paten Daftar Ujian', () {
    test('nama kartu = CBT Alternatif Family Link (bukan mapel dari CMS)', () {
      expect(kCbtNamaPaten, 'CBT Alternatif Family Link');
    });

    test('penanda link kartu paten bukan URL web', () {
      expect(kCbtNativeLink, 'native://cbt');
      expect(kCbtNativeLink.startsWith('http'), isFalse);
    });

    test('URL API terdeteksi dari link ujian Web App (/exec)', () {
      const link = 'https://script.google.com/macros/s/AKfycbXYZ_123/exec?token=x';
      expect(deteksiUrlApiDariLink(link), isTrue);
      expect(urlApiTerdeteksi,
          'https://script.google.com/macros/s/AKfycbXYZ_123/exec');
      // Link yang sama tidak dianggap perubahan baru.
      expect(deteksiUrlApiDariLink(link), isFalse);
    });

    test('link non-Apps-Script tidak dipakai sebagai URL API', () {
      expect(deteksiUrlApiDariLink('native://cbt'), isFalse);
      expect(deteksiUrlApiDariLink('https://forms.gle/abcdef'), isFalse);
      // URL hasil deteksi sebelumnya tetap dipertahankan.
      expect(urlApiTerdeteksi,
          'https://script.google.com/macros/s/AKfycbXYZ_123/exec');
    });

    test('kCbtApiUrl terisi permanen dengan deployment CBT (/exec)', () {
      expect(kCbtApiUrl.trim().isEmpty, isFalse);
      expect(kCbtApiUrl.trim().startsWith('https://script.google.com/macros/s/'),
          isTrue);
      expect(kCbtApiUrl.trim().endsWith('/exec'), isTrue);
    });

    test('URL permanen diutamakan di atas hasil deteksi otomatis', () {
      // Deteksi tetap boleh bekerja (mis. saat kCbtApiUrl dikosongkan lagi),
      // tetapi selama konstanta terisi, URL itulah yang dipakai klien.
      expect(kCbtUrlEfektif, kCbtApiUrl.trim());
      expect(kCbtUrlEfektif.endsWith('/exec'), isTrue);
    });
  });

  group('SoalCbt', () {
    test('parsing respons server: noSoal numerik -> string, opsi A-E dinormalkan',
        () {
      final soal = SoalCbt.fromJson({
        'noSoal': 7,
        'pertanyaan': 'Ibu kota Jawa Timur adalah <b>Surabaya</b>.<br>Setuju?',
        'opsi': {'a': 'Ya', 'C': 'Tidak', 'F': 'Bukan opsi ini'},
        'gambarUrl': 'https://drive.google.com/file/d/1AbC_dEf/view',
        'kunci': 'c',
      });

      expect(soal.noSoal, '7');
      expect(soal.opsi['A'], 'Ya');
      expect(soal.opsi['C'], 'Tidak');
      expect(soal.opsi['B'], '');
      expect(soal.opsi.containsKey('F'), isFalse);
      expect(soal.kunci, 'C');
      expect(soal.isMulti, isFalse);
      expect(soal.gambarAman,
          'https://drive.google.com/thumbnail?id=1AbC_dEf&sz=w1000');
    });

    test('kunci multi (A|C) dikenali sebagai soal checkbox', () {
      final soal = SoalCbt.fromJson({'noSoal': '3', 'kunci': 'a|c'});
      expect(soal.isMulti, isTrue);
      expect(soal.kunci, 'A|C');
    });
  });

  group('RemediInfo & CbtDataLogin', () {
    test('batas null / sisa 99 (tanpa batas) terbaca benar', () {
      final rd = RemediInfo.fromJson({
        'tersedia': true,
        'batas': null,
        'sisa': 99,
        'kodeSoal': 'MTK-REMEDI',
        'mapel': 'Matematika',
      });
      expect(rd.tersedia, isTrue);
      expect(rd.batas, isNull);
      expect(rd.sisa, 99);
      expect(rd.mapel, 'Matematika');
    });

    test('batas angka (string dari Sheets) dikonversi ke double', () {
      final rd =
          RemediInfo.fromJson({'tersedia': 1, 'batas': '80', 'sisa': '2'});
      expect(rd.batas, 80);
      expect(rd.sisa, 2);
    });

    test('data login valid dipetakan apa adanya', () {
      final dl = CbtDataLogin.fromJsonValid({
        'kelasList': ['7A', '7B'],
        'siswa': {
          '7A': [
            {'nisn': '123', 'nama': 'Ani'}
          ]
        },
        'wajibNisn': true,
      });
      expect(dl.kelasList, ['7A', '7B']);
      expect(dl.siswa['7A']!.first.nama, 'Ani');
      expect(dl.wajibNisn, isTrue);
    });

    test('data login kosong DITOLAK (dropdown tidak dianggap sukses)', () {
      expect(() => CbtDataLogin.fromJsonValid({'kelasList': [], 'siswa': {}}),
          throwsFormatException);
      expect(() => CbtDataLogin.fromJsonValid({'kelasList': ['7A']}),
          throwsFormatException);
    });
  });

  group('CbtRichText', () {
    test('decodeEntities menangani &amp; terakhir (tanpa double-decode)', () {
      expect(CbtRichText.decodeEntities('a &amp;amp; b'), 'a &amp; b');
      expect(
          CbtRichText.decodeEntities('&lt;b&gt;x&lt;/b&gt;&nbsp;&quot;q&quot;'),
          '<b>x</b> "q"');
    });

    test('spans: <b> menjadi bold, <br> menjadi baris baru', () {
      final spans = CbtRichText.spans(
          'tebal <b>B</b><br>baris2', const TextStyle(fontSize: 14));
      final teks = spans.map((s) => (s as TextSpan).text).join();
      expect(teks, 'tebal B\nbaris2');
      final bold = spans
          .cast<TextSpan>()
          .where((s) => s.style?.fontWeight == FontWeight.bold)
          .map((s) => s.text)
          .join();
      expect(bold, 'B');
    });

    test('urlGambarAman: id= dan tautan /file/d/ dipaksa ke thumbnail', () {
      expect(CbtRichText.urlGambarAman('https://drive.google.com/uc?id=XYZ123'),
          'https://drive.google.com/thumbnail?id=XYZ123&sz=w1000');
      expect(
          CbtRichText.urlGambarAman(
              'https://drive.google.com/thumbnail?id=XYZ123&sz=w1000'),
          'https://drive.google.com/thumbnail?id=XYZ123&sz=w1000');
      expect(CbtRichText.urlGambarAman('https://contoh.test/a.png'),
          'https://contoh.test/a.png');
      expect(CbtRichText.urlGambarAman(''), '');
      // Tautan "bagikan" Drive bentuk /file/d/<id>/view juga dipaksa thumbnail.
      expect(
          CbtRichText.urlGambarAman(
              'https://drive.google.com/file/d/1AbCdEfGhIjKl/view?usp=sharing'),
          'https://drive.google.com/thumbnail?id=1AbCdEfGhIjKl&sz=w1000');
      expect(
          CbtRichText.urlGambarAman('https://drive.google.com/d/1AbCdEfGh'),
          'https://drive.google.com/thumbnail?id=1AbCdEfGh&sz=w1000');
      // Gambar non-Drive (mis. link FormApp/upload manual) dibiarkan apa adanya.
      expect(
          CbtRichText.urlGambarAman('https://lh7-us.googleusercontent.com/x.png'),
          'https://lh7-us.googleusercontent.com/x.png');
    });
  });

  group('CbtSession', () {
    CbtSession sesiDengan(int jumlahSoal, {bool acakSoal = false}) {
      return CbtSession()
        ..soalList = List<SoalCbt>.generate(
            jumlahSoal,
            (i) => SoalCbt(
                  noSoal: '${i + 1}',
                  pertanyaan: 'soal ${i + 1}',
                  opsi: const {'A': 'a', 'B': 'b'},
                  gambarUrl: '',
                  kunci: 'A',
                ))
        ..acakSoal = acakSoal;
    }

    test('urutan soal lama dipertahankan saat pindah layar', () {
      final s = sesiDengan(5);
      s.pastikanUrutanSoal();
      final urutanPertama = List<int>.from(s.urutanSoal);
      s.pastikanUrutanSoal();
      expect(s.urutanSoal, urutanPertama);
      expect(s.urutanSoal, [0, 1, 2, 3, 4]);
    });

    test('acakSoal menghasilkan permutasi lengkap tanpa duplikat', () {
      final s = sesiDengan(8, acakSoal: true);
      s.pastikanUrutanSoal();
      expect(s.urutanSoal.toSet().length, 8);
      expect(s.urutanSoal.toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
    });

    test('pastikanUrutanOpsi mengisi A-E tanpa menimpa urutan yang sudah ada',
        () {
      final s = sesiDengan(3);
      s.acakOpsi = false;
      s.pastikanUrutanOpsi();
      expect(s.urutanOpsi['1'], ['A', 'B', 'C', 'D', 'E']);
      s.urutanOpsi['2'] = ['E', 'D', 'C', 'B', 'A'];
      s.pastikanUrutanOpsi();
      expect(s.urutanOpsi['2'], ['E', 'D', 'C', 'B', 'A']);
    });

    test('soalPadaPosisi mengikuti urutan acak', () {
      final s = sesiDengan(3);
      s.urutanSoal = [2, 0, 1];
      expect(s.soalPadaPosisi(0).noSoal, '3');
      expect(s.soalPadaPosisi(2).noSoal, '2');
    });

    test('durasi 0 = tanpa batas (timer global tidak dijalankan)', () {
      final s = sesiDengan(1);
      s.durasiUjianMenit = 0;
      expect(s.isTanpaBatas(), isTrue);
      s.hitungSisaDari();
      expect(s.sisaDetik, -1);
    });

    test('sisa waktu dihitung dari startTime (durasi 60 menit)', () {
      final s = sesiDengan(1);
      s.durasiUjianMenit = 60;
      s.startTime = DateTime.now().millisecondsSinceEpoch -
          const Duration(minutes: 10).inMilliseconds;
      s.hitungSisaDari();
      expect(s.sisaDetik, closeTo(3000, 5));
    });

    test('jawabanTerpilih menghitung soal terjawab termasuk jawaban kosong', () {
      final s = sesiDengan(3);
      expect(s.jumlahTerjawab, 0);
      s.jawabanTerpilih['1'] = 'A';
      s.jawabanTerpilih['2'] = '';
      expect(s.jumlahTerjawab, 2);
    });

    test('dirtySet melacak soal yang belum tersinkron', () {
      final s = sesiDengan(2);
      s.dirtySet.add('1');
      s.dirtySet.add('2');
      s.dirtySet.remove('1');
      expect(s.dirtySet, {'2'});
    });

    test('kunci penyimpanan mengikuti skema web (cbt_sesi_nisn_kode)', () {
      expect(CbtSession.keySesi('123', 'MTK'), 'cbt_sesi_123_MTK');
      expect(CbtSession.keyFinal('123', 'MTK'), 'cbt_final_123_MTK');
      expect(CbtSession.keyPending('123', 'MTK'), 'cbt_pending_123_MTK');
    });

    test('status kirim akhir default "belum" (belum aman menutup aplikasi)',
        () {
      expect(sesiDengan(1).statusKirimFinal, 'belum');
    });
  });
}
