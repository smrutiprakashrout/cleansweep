import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'models.dart';

class FileCard extends StatelessWidget {
  final CategorizedFile file;
  final WidgetBuilder? overlayBuilder;
  final bool isCurrent;

  const FileCard({
    Key? key,
    required this.file,
    this.overlayBuilder,
    this.isCurrent = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _buildCardContent(context);
  }

  Widget _buildSwipeBackground(Color color, IconData icon, Alignment alignment, String label) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment == Alignment.centerLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 48),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 96, left: 16, right: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Preview Image / Backdrop
            Positioned.fill(
              child: FilePreviewWidget(file: file, isCurrent: isCurrent),
            ),
            
            // Dynamic Overlay (if provided)
            if (overlayBuilder != null)
              Positioned.fill(
                child: overlayBuilder!(context),
              ),
              
            // Bottom info text
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          file.extension.replaceAll('.', '').toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatBytes(file.sizeInBytes), 
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "Unknown size";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }
}

class FilePreviewWidget extends StatefulWidget {
  final CategorizedFile file;
  final bool isCurrent;

  const FilePreviewWidget({Key? key, required this.file, this.isCurrent = false}) : super(key: key);

  @override
  State<FilePreviewWidget> createState() => _FilePreviewWidgetState();
}

class _FilePreviewWidgetState extends State<FilePreviewWidget> {
  Uint8List? _bytes;
  Player? _player;
  VideoController? _videoController;
  PdfDocument? _pdfDocument;
  PdfPageImage? _pdfImage;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(FilePreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.file.documentUri?.toString() ?? oldWidget.file.path;
    final newKey = widget.file.documentUri?.toString() ?? widget.file.path;
    if (oldKey != newKey) {
      _isLoading = true;
      _bytes = null;
      _player?.dispose();
      _player = null;
      _videoController = null;
      _pdfDocument?.close();
      _pdfDocument = null;
      _pdfImage = null;
      _loadPreview();
    } else if (oldWidget.isCurrent != widget.isCurrent && _player != null) {
      if (widget.isCurrent) {
        _player!.setVolume(100.0);
        _player!.play();
      } else {
        _player!.setVolume(0.0);
        _player!.pause();
      }
    }
  }

  Future<void> _loadPreview() async {
    final file = widget.file;
    try {
      if (file.category == FileCategory.image) {
        if (Platform.isAndroid && file.documentUri != null) {
          final content = await saf.getDocumentContent(file.documentUri!);
          if (mounted) setState(() { _bytes = content; _isLoading = false; });
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      } else if (file.category == FileCategory.video) {
        _player = Player();
        _videoController = VideoController(_player!);
        await _player!.setPlaylistMode(PlaylistMode.loop);
        
        if (!widget.isCurrent) {
          await _player!.setVolume(0.0);
        }

        if (Platform.isAndroid && file.documentUri != null) {
          await _player!.open(Media(file.documentUri!.toString()), play: widget.isCurrent);
        } else {
          await _player!.open(Media('file://${file.path}'), play: widget.isCurrent);
        }
        if (mounted) setState(() => _isLoading = false);
      } else if (file.category == FileCategory.document && file.extension == '.pdf') {
        if (Platform.isAndroid && file.documentUri != null) {
          final content = await saf.getDocumentContent(file.documentUri!);
          _pdfDocument = await PdfDocument.openData(content!);
        } else {
          _pdfDocument = await PdfDocument.openFile(file.path);
        }
        final page = await _pdfDocument!.getPage(1);
        _pdfImage = await page.render(width: page.width, height: page.height);
        await page.close();
        if (mounted) setState(() => _isLoading = false);
      } else {
        if (mounted) setState(() { _isLoading = false; _hasError = true; });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  @override
  void dispose() {
    if (widget.file.category == FileCategory.image) {
      if (_bytes != null) {
        MemoryImage(_bytes!).evict();
      } else {
        FileImage(File(widget.file.path)).evict();
      }
    }
    _player?.dispose();
    _pdfDocument?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
      );
    }
    
    final file = widget.file;
    Widget? previewContent;

    if (!_hasError) {
      if (file.category == FileCategory.image) {
        if (_bytes != null) {
          final uniqueKey = ValueKey(file.documentUri?.toString() ?? file.path);
          if (file.extension == '.svg') {
            previewContent = SvgPicture.memory(
              _bytes!,
              key: uniqueKey,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          } else {
            previewContent = Image.memory(
              _bytes!,
              key: uniqueKey,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: false,
            );
          }
        } else {
          final uniqueKey = ValueKey(file.documentUri?.toString() ?? file.path);
          if (file.extension == '.svg') {
            previewContent = SvgPicture.file(
              File(file.path),
              key: uniqueKey,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          } else {
            previewContent = Image.file(
              File(file.path),
              key: uniqueKey,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: false,
            );
          }
        }
      } else if (file.category == FileCategory.video && _videoController != null) {
        previewContent = Video(controller: _videoController!, controls: NoVideoControls, fit: BoxFit.cover);
      } else if (file.category == FileCategory.document && _pdfImage != null) {
        previewContent = Image.memory(
          _pdfImage!.bytes,
          key: ValueKey(file.documentUri?.toString() ?? file.path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: false,
        );
      }
    }

    if (previewContent != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          previewContent,
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ],
      );
    }

    // Fallback: Orange Gradient + Icon
    IconData icon;
    switch (file.category) {
      case FileCategory.image: icon = Icons.landscape_rounded; break;
      case FileCategory.video: icon = Icons.play_circle_fill_rounded; break;
      case FileCategory.document: icon = Icons.description_rounded; break;
      case FileCategory.other: default: icon = Icons.insert_drive_file_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1E1705),
            Colors.orange.shade800.withValues(alpha: 0.9),
            const Color(0xFF1E1400),
          ],
          stops: const [0.1, 0.7, 1.0],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Icon(icon, size: 64, color: Colors.orangeAccent),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              file.extension.replaceAll('.', '').toUpperCase(),
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
