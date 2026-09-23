// ==================== Parser rich-text CBT (subset HTML) ====================
// Meniru perilaku halaman Index: soal/opsi disimpan sebagai HTML yang dibatasi
// tag <b>, <i>, <u>, <br>, <p>, <img> (lihat htmlFragmentToStored/richTextToHtml
// di Kode.txt) plus baris baru biasa — tanpa paket dependency tambahan.
import 'package:flutter/material.dart';

class CbtRichText {
  CbtRichText._();

  /// Decode entity HTML umum (porting htmlFragmentToStored).
  static String decodeEntities(String s) {
    var out = s;
    out = out.replaceAll('&nbsp;', ' ');
    out = out.replaceAll('&quot;', '"');
    out = out.replaceAll('&#34;', '"');
    out = out.replaceAll('&#39;', "'");
    out = out.replaceAll('&#039;', "'");
    out = out.replaceAll('&lt;', '<');
    out = out.replaceAll('&gt;', '>');
    out = out.replaceAll('&amp;', '&'); // &amp; terakhir agar tidak double-decode
    return out;
  }

  static final RegExp _tagRe =
      RegExp(r'<(\/?)(b|i|u|br|p)(\s[^>]*)?>', caseSensitive: false);
  static final RegExp _imgRe = RegExp(
      r'''<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false);

  /// Ubah segmen teks HTML (tanpa <img>) menjadi InlineSpans.
  /// Menangani <b>/<i>/<u> bersaran, <br> dan \n menjadi baris baru,
  /// </p> menjadi baris baru paragraf.
  static List<InlineSpan> spans(String html, TextStyle base) {
    final List<InlineSpan> out = [];
    final String text = decodeEntities(html);
    int b = 0, i = 0, u = 0;
    final StringBuffer buf = StringBuffer();
    int pos = 0;

    void flush() {
      if (buf.isEmpty) return;
      var style = base;
      if (b > 0) style = style.copyWith(fontWeight: FontWeight.bold);
      if (i > 0) style = style.copyWith(fontStyle: FontStyle.italic);
      if (u > 0) {
        style = style.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: style.color,
        );
      }
      out.add(TextSpan(text: buf.toString(), style: style));
      buf.clear();
    }

    while (pos < text.length) {
      final match = _tagRe.matchAsPrefix(text, pos);
      if (match != null) {
        final closing = match.group(1) == '/';
        final tag = (match.group(2) ?? '').toLowerCase();
        flush();
        if (tag == 'br') {
          out.add(TextSpan(text: '\n', style: base));
        } else if (tag == 'p') {
          if (closing) {
            out.add(TextSpan(text: '\n\n', style: base));
          } else {
            out.add(TextSpan(text: '\n', style: base));
          }
        } else if (tag == 'b') {
          b = closing ? (b > 0 ? b - 1 : 0) : b + 1;
        } else if (tag == 'i') {
          i = closing ? (i > 0 ? i - 1 : 0) : i + 1;
        } else if (tag == 'u') {
          u = closing ? (u > 0 ? u - 1 : 0) : u + 1;
        }
        pos += match.end - match.start;
        continue;
      }
      buf.write(text[pos]);
      pos++;
    }
    flush();
    return out;
  }

  /// Teks rich-text sederhana (untuk opsi jawaban dsb).
  static Widget rich(String html, {TextStyle? style, TextAlign? textAlign}) {
    final base = style ??
        const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF1a2b20));
    return Text.rich(
      TextSpan(children: spans(html, base)),
      textAlign: textAlign ?? TextAlign.left,
    );
  }

  /// Blok soal lengkap: potongan teks + <img> yang tertanam di dalam pertanyaan.
  static Widget block(String html, {TextStyle? style}) {
    final base = style ??
        const TextStyle(fontSize: 17, height: 1.55, color: Color(0xFF1a2b20));
    final String source = html;
    final List<Widget> children = [];
    int pos = 0;
    final matchIt = _imgRe.allMatches(source);

    void addText(String chunk) {
      // Lewati potongan yang hanya berisi spasi/baris kosong.
      if (chunk.trim().isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(children: spans(chunk, base)),
            textAlign: TextAlign.left,
          ),
        ),
      );
    }

    for (final m in matchIt) {
      if (m.start > pos) addText(source.substring(pos, m.start));
      final url = urlGambarAman(m.group(1) ?? '');
      if (url.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ));
      }
      pos = m.end;
    }
    if (pos < source.length) addText(source.substring(pos));
    if (children.isEmpty) children.add(const SizedBox.shrink());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  /// Porting urlGambarAman() dari Index.txt: paksa URL gambar Drive ke
  /// endpoint thumbnail yang ramah-permalink publik. Ditambah dukungan tautan
  /// bentuk "/file/d/&lt;id&gt;" dan "/d/&lt;id&gt;" (tautan "bagikan" dari Drive)
  /// supaya gambar yang ditempel manual tetap tampil.
  static String urlGambarAman(String originalUrl) {
    if (originalUrl.isEmpty) return '';
    final match = RegExp(r'[?&]id=([a-zA-Z0-9\-_]+)').firstMatch(originalUrl);
    if (match != null) {
      return 'https://drive.google.com/thumbnail?id=${match.group(1)}&sz=w1000';
    }
    if (originalUrl.contains('/thumbnail?id=')) return originalUrl;
    if (originalUrl.contains('drive.google.com')) {
      final jalur = RegExp(r'/(?:file/)?d/([a-zA-Z0-9\-_]{5,})')
          .firstMatch(originalUrl);
      if (jalur != null) {
        return 'https://drive.google.com/thumbnail?id=${jalur.group(1)}&sz=w1000';
      }
      final idPart = originalUrl.split('id=');
      if (idPart.length > 1) {
        final id = idPart[1].split('&').first;
        if (id.isNotEmpty) return 'https://drive.google.com/thumbnail?id=$id&sz=w1000';
      }
    }
    return originalUrl;
  }
}
