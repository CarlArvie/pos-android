import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// Service for managing local offline-first product images.
///
/// Principles:
/// 1. Stores image binaries on disk in `<ApplicationDocumentsDirectory>/product_images/`.
/// 2. Returns and accepts relative paths (e.g. `product_images/prod_123_456.jpg`) so paths
///    remain valid across OS upgrades and app container path changes.
/// 3. Zero network requirement to save or view local images.
class ProductImageService {
  static const String imageSubDir = 'product_images';

  /// In-memory cache of resolved local files to avoid redundant disk I/O on UI rebuilds
  static final Map<String, File?> _resolvedFileCache = {};
  static String? _cachedDocsDirPath;

  static Future<String> _getDocsDirPath() async {
    if (_cachedDocsDirPath != null) return _cachedDocsDirPath!;
    final docsDir = await getApplicationDocumentsDirectory();
    _cachedDocsDirPath = docsDir.path;
    return _cachedDocsDirPath!;
  }

  /// Synchronously returns cached resolved File if already loaded into memory.
  static File? getCachedFile(String? relativePath) {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    return _resolvedFileCache[relativePath];
  }

  /// Returns the persistent local directory for product images.
  static Future<Directory> getImageDirectory() async {
    final docsDirPath = await _getDocsDirPath();
    final imgDir = Directory(p.join(docsDirPath, imageSubDir));
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }
    return imgDir;
  }

  /// Saves a picked [XFile] (from Camera or Gallery) to the local product images folder.
  /// Returns the relative path to store in SQLite, e.g. `product_images/prod_<id>_<timestamp>.jpg`.
  static Future<String> saveImageLocally(String productId, XFile sourceFile) async {
    final imgDir = await getImageDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(sourceFile.path).isNotEmpty ? p.extension(sourceFile.path) : '.jpg';
    final fileName = 'prod_${productId}_$timestamp$ext';
    final targetFile = File(p.join(imgDir.path, fileName));

    final bytes = await sourceFile.readAsBytes();
    await targetFile.writeAsBytes(bytes, flush: true);

    final relPath = p.join(imageSubDir, fileName).replaceAll(r'\', '/');
    _resolvedFileCache[relPath] = targetFile;
    return relPath;
  }

  /// Resolves a relative path (e.g. `product_images/abc.jpg`) to an absolute [File] on disk.
  /// Returns `null` if the file does not exist.
  static Future<File?> resolveLocalFile(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    if (_resolvedFileCache.containsKey(relativePath)) {
      return _resolvedFileCache[relativePath];
    }
    try {
      final dirPath = await _getDocsDirPath();
      final fullPath = p.join(dirPath, relativePath);
      final file = File(fullPath);
      if (await file.exists()) {
        _resolvedFileCache[relativePath] = file;
        return file;
      } else {
        _resolvedFileCache[relativePath] = null;
      }
    } catch (e) {
      debugPrint('[ProductImageService] Error resolving file: $e');
    }
    return null;
  }

  /// Synchronously or fast resolves file without throwing.
  static Future<String?> getAbsolutePath(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, relativePath);
  }

  /// Deletes a local image file from disk (e.g. when an image is replaced or product deleted).
  static Future<void> deleteLocalImage(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return;
    _resolvedFileCache.remove(relativePath);
    try {
      final dirPath = await _getDocsDirPath();
      final fullPath = p.join(dirPath, relativePath);
      final file = File(fullPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[ProductImageService] Error deleting local image: $e');
    }
  }

  /// Alias for [deleteLocalImage].
  static Future<void> deleteImageLocally(String? relativePath) => deleteLocalImage(relativePath);

  /// Downloads a cloud image from Supabase Storage and caches it locally on disk.
  /// Returns the relative path of the cached file.
  static Future<String?> cacheCloudImageLocally(String productId, String cloudUrl) async {
    try {
      final response = await http.get(Uri.parse(cloudUrl));
      if (response.statusCode == 200) {
        final imgDir = await getImageDirectory();
        final fileName = 'prod_${productId}_cloud.jpg';
        final targetFile = File(p.join(imgDir.path, fileName));
        await targetFile.writeAsBytes(response.bodyBytes, flush: true);
        final relPath = p.join(imageSubDir, fileName).replaceAll(r'\', '/');
        _resolvedFileCache[relPath] = targetFile;
        return relPath;
      }
    } catch (e) {
      debugPrint('[ProductImageService] Error caching cloud image: $e');
    }
    return null;
  }
}
