// ==================== Model data CBT ====================
// Struktur JSON persis respons Apps Script (lihat ambilSoalLengkap/login/
// mulaiRemedi di Kode.txt).
import 'cbt_richtext.dart';

String teksDari(dynamic v) => v == null ? '' : v.toString();

/// Nomor soal dinormalkan ke string ('1','2',...) — kunci map jawaban di
/// JavaScript juga selalu string setelah JSON.stringify/parse.
String normKeyNoSoal(dynamic v) {
  if (v is num && v == v.roundToDouble()) return v.toInt().toString();
  return teksDari(v);
}

/// Satu soal: {noSoal, pertanyaan, opsi:{A..E}, gambarUrl, kunci}.
class SoalCbt {
  final String noSoal;
  final String pertanyaan; // HTML subset <b><i><u><br><p><img> + \n
  final Map<String, String> opsi; // A..E ('' bila tidak dipakai)
  final String gambarUrl;
  final String kunci; // 'A' atau 'A|C' (multi)

  const SoalCbt({
    required this.noSoal,
    required this.pertanyaan,
    required this.opsi,
    required this.gambarUrl,
    required this.kunci,
  });

  bool get isMulti => kunci.contains('|');

  /// Gambar utama via urlGambarAman (endpoint thumbnail Drive).
  String get gambarAman => CbtRichText.urlGambarAman(gambarUrl);

  factory SoalCbt.fromJson(Map<String, dynamic> j) {
    final Map<String, String> opsi = {'A': '', 'B': '', 'C': '', 'D': '', 'E': ''};
    final raw = j['opsi'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final kk = teksDari(k).trim().toUpperCase();
        if (opsi.containsKey(kk)) opsi[kk] = teksDari(v);
      });
    }
    return SoalCbt(
      noSoal: normKeyNoSoal(j['noSoal']),
      pertanyaan: teksDari(j['pertanyaan']),
      opsi: opsi,
      gambarUrl: teksDari(j['gambarUrl']),
      kunci: teksDari(j['kunci']).trim().toUpperCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'noSoal': noSoal,
        'pertanyaan': pertanyaan,
        'opsi': opsi,
        'gambarUrl': gambarUrl,
        'kunci': kunci,
      };
}

/// Info remedi dari respons login cabang sudahSelesai / mulaiRemedi.
/// sisa: 99 = tanpa batas.
class RemediInfo {
  final bool tersedia;
  final double? batas;
  final int sisa;
  final String kodeSoal;
  final String mapel;

  const RemediInfo({
    required this.tersedia,
    required this.batas,
    required this.sisa,
    required this.kodeSoal,
    required this.mapel,
  });

  factory RemediInfo.fromJson(Map<String, dynamic> j) {
    final dynamic b = j['batas'];
    double? batas;
    if (b != null && teksDari(b).trim().isNotEmpty) {
      final n = b is num ? b.toDouble() : double.tryParse(teksDari(b).trim());
      if (n != null && !n.isNaN) batas = n;
    }
    return RemediInfo(
      tersedia: j['tersedia'] == true,
      batas: batas,
      sisa: int.tryParse(teksDari(j['sisa'])) ?? 0,
      kodeSoal: teksDari(j['kodeSoal']),
      mapel: teksDari(j['mapel']),
    );
  }
}

/// Satu baris nama siswa pada data login.
class CbtSiswa {
  final String nisn;
  final String nama;
  const CbtSiswa({required this.nisn, required this.nama});

  factory CbtSiswa.fromJson(Map<String, dynamic> j) =>
      CbtSiswa(nisn: teksDari(j['nisn']), nama: teksDari(j['nama']));
}

/// Paket data login: {kelasList, siswa: {kelas: [{nisn,nama}]}, wajibNisn}.
class CbtDataLogin {
  final List<String> kelasList;
  final Map<String, List<CbtSiswa>> siswa;
  final bool wajibNisn;
  final int versi;

  const CbtDataLogin({
    required this.kelasList,
    required this.siswa,
    required this.wajibNisn,
    required this.versi,
  });

  /// Validasi keras seperti setLoginOptions() di Index.txt — data kosong/tidak
  /// valid dibuang supaya dropdown tidak pernah "kosong dianggap sukses".
  factory CbtDataLogin.fromJsonValid(Map<String, dynamic> j) {
    final kl = j['kelasList'];
    final sw = j['siswa'];
    if (kl is! List || kl.isEmpty || sw is! Map) {
      throw const FormatException('Data login kosong/tidak valid');
    }
    final Map<String, List<CbtSiswa>> siswa = {};
    sw.forEach((k, v) {
      final list = <CbtSiswa>[];
      if (v is List) {
        for (final item in v) {
          if (item is Map) list.add(CbtSiswa.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      siswa[teksDari(k)] = list;
    });
    if (siswa.isEmpty) throw const FormatException('Data login kosong/tidak valid');
    return CbtDataLogin(
      kelasList: kl.map((e) => teksDari(e)).where((e) => e.isNotEmpty).toList(),
      siswa: siswa,
      wajibNisn: j['wajibNisn'] == true,
      versi: (j['versi'] is num) ? (j['versi'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'versi': versi,
        'kelasList': kelasList,
        'siswa': siswa.map((k, v) => MapEntry(
            k, v.map((s) => {'nisn': s.nisn, 'nama': s.nama}).toList())),
        'wajibNisn': wajibNisn,
      };
}

/// Cache data login yang tersimpan di perangkat + metadata umurnya.
/// `kedaluwarsa == true` berarti data MASIH dipakai untuk tampilan instan
/// (stale-while-revalidate), tetapi perlu disegarkan dari server di latar
/// belakang — jadi login 900 siswa tidak pernah menunggu jaringan.
class CbtCacheLogin {
  final CbtDataLogin data;
  final bool kedaluwarsa;
  final int umurMs;

  const CbtCacheLogin(this.data, this.kedaluwarsa, this.umurMs);
}
