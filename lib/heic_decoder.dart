import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class HeicDecoder {
  static final Map<String, Uint8List> _cache = {};

  static Widget buildPreview(String path) {
    return FutureBuilder<Uint8List?>(
      future: _decodeHeic(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1E1705),
                  Colors.orange.shade800.withOpacity(0.9),
                  const Color(0xFF1E1400),
                ],
                stops: const [0.1, 0.7, 1.0],
              ),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.landscape_rounded, size: 64, color: Colors.orangeAccent),
                  SizedBox(height: 24),
                  Text(
                    'HEIC NOT SUPPORTED',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Image.memory(
          snapshot.data!,
          key: ValueKey(path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: false,
        );
      },
    );
  }

  static Future<Uint8List?> _decodeHeic(String path) async {
    if (_cache.containsKey(path)) {
      return _cache[path];
    }

    try {
      Uint8List? bytes;

      if (Platform.isAndroid || Platform.isIOS) {
        // Use flutter_image_compress for mobile platforms
        bytes = await FlutterImageCompress.compressWithFile(
          path,
          format: CompressFormat.jpeg,
          quality: 90,
        );
      } else if (Platform.isLinux) {
        // Use Process Runner for Linux using libheif-examples (heif-convert)
        final tempDir = await getTemporaryDirectory();
        final fileName = path.split(Platform.pathSeparator).last;
        final tempJpgPath = '${tempDir.path}/preview_$fileName.jpg';

        final result = await Process.run('heif-convert', ['-q', '90', path, tempJpgPath]);

        if (result.exitCode == 0) {
          final file = File(tempJpgPath);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
            // Cleanup temp file
            await file.delete();
          }
        } else {
          debugPrint('heif-convert failed: ${result.stderr}');
        }
      }

      if (bytes != null) {
        _cache[path] = bytes;
      }
      return bytes;
    } catch (e) {
      debugPrint('Error decoding HEIC at $path: $e');
      return null;
    }
  }

  static void clearCache() {
    _cache.clear();
  }
}
