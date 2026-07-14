import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_gadget/features/image_watermark/image_watermark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('图片隐形水印可写入并读取 EPUB 图片', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_watermark_');
    addTearDown(() => tempDir.delete(recursive: true));

    final image = img.Image.rgb(80, 80);
    img.fill(image, img.getColor(180, 120, 80));
    final imageBytes = img.encodeJpg(image, quality: 90);

    final source = File('${tempDir.path}/source.epub');
    final output = '${tempDir.path}/watermarked.epub';
    final archive = Archive()
      ..addFile(
        ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')),
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/content.opf',
          240,
          utf8.encode(
            '<package><manifest>'
            '<item id="cover" href="Images/cover.jpg" media-type="image/jpeg"/>'
            '</manifest></package>',
          ),
        ),
      )
      ..addFile(
        ArchiveFile(
          'OEBPS/Text/chapter.xhtml',
          120,
          utf8.encode(
            '<html><body><img src="../Images/cover.jpg"/></body></html>',
          ),
        ),
      )
      ..addFile(
        ArchiveFile('OEBPS/Images/cover.jpg', imageBytes.length, imageBytes),
      );
    await source.writeAsBytes(ZipEncoder().encode(archive)!);

    final embedLog = await ImageWatermarkOperation.embed(
      epubPath: source.path,
      outputPath: output,
      watermarkText: 'user=alice;order=20260714',
    );
    expect(embedLog, contains('写入完成'));

    final inspectLog = await ImageWatermarkOperation.inspect(epubPath: output);
    expect(inspectLog, contains('user=alice;order=20260714'));

    final result = ZipDecoder().decodeBytes(await File(output).readAsBytes());
    expect(result.findFile('OEBPS/Images/cover.png'), isNotNull);

    final html = utf8.decode(
      result.findFile('OEBPS/Text/chapter.xhtml')!.content as List<int>,
    );
    expect(html, contains('cover.png'));

    final opf = utf8.decode(
      result.findFile('OEBPS/content.opf')!.content as List<int>,
    );
    expect(opf, contains('href="Images/cover.png"'));
    expect(opf, contains('media-type="image/png"'));
  });
}
