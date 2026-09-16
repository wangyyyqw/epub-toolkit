import 'package:path/path.dart' as path;

class ZipPathUtils {
  /// Decode URI escapes once, without passing raw Unicode to decodeFull.
  static String decode(String value) => value.replaceAllMapped(
        RegExp(r'(?:%[0-9a-fA-F]{2})+'),
        (match) => Uri.decodeComponent(match.group(0)!),
      );

  /// URI references and ZIP entry names are distinct: strip URI suffixes
  /// before decoding, so an escaped # or ? remains part of the filename.
  static String fileName(String reference) =>
      path.posix.normalize(decode(reference.split(RegExp(r'[?#]')).first));

  static String getDirectoryPath(String filePath) {
    var lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex == -1) {
      return '';
    } else {
      return filePath.substring(0, lastSlashIndex);
    }
  }

  static String? combine(String? directory, String? fileName) {
    if (directory == null || directory == '') {
      return fileName;
    } else {
      return path.posix.normalize(path.posix.join(directory, fileName!));
    }
  }
}
