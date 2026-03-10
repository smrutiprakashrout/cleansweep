import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'models.dart';

class FileService extends ChangeNotifier {
  String? _selectedDirectory;
  String? get selectedDirectory => _selectedDirectory;

  Uri? _selectedSafUri;
  bool _isCustomFileSelection = false;

  List<CategorizedFile> _files = [];
  List<CategorizedFile> get files => _files;

  final List<CategorizedFile> _filesToDelete = [];
  final List<CategorizedFile> _filesToKeep = [];

  List<CategorizedFile> get filesToDelete => _filesToDelete;
  List<CategorizedFile> get filesToKeep => _filesToKeep;
  int _initialTotalCount = 0;
  int get initialTotalCount => _initialTotalCount;
  int get currentIndex => _initialTotalCount - _files.length + 1;
  bool get hasReviewedFiles => _filesToDelete.isNotEmpty || _filesToKeep.isNotEmpty;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  FileService();

  Future<void> pickDirectory() async {
    if (Platform.isAndroid) {
      // Use Storage Access Framework (SAF) on Android for write permissions
      final uri = await saf.openDocumentTree();
      if (uri != null) {
        _selectedSafUri = uri;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_saf_uri', uri.toString());
        await scanDirectory();
      }
    } else {
      final String? path = await FilePicker.platform.getDirectoryPath();
      if (path != null) {
        _selectedDirectory = path;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_directory', path);
        await scanDirectory();
      }
    }
  }

  Future<void> pickMultipleFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.paths.isNotEmpty) {
      _isCustomFileSelection = true;
      _isLoading = true;
      _files = [];
      _filesToDelete.clear();
      _filesToKeep.clear();
      _initialTotalCount = 0;
      notifyListeners();

      for (var path in result.paths) {
        if (path != null) {
          final file = File(path);
          int size = 0;
          if (file.existsSync()) {
            size = file.lengthSync();
          }
          _addFile(p.basename(path), path, size);
        }
      }

      _initialTotalCount = _files.length;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> scanDirectory() async {
    _isCustomFileSelection = false;
    _isLoading = true;
    _files = [];
    _filesToDelete.clear();
    _filesToKeep.clear();
    _initialTotalCount = 0;
    notifyListeners();

    if (Platform.isAndroid && _selectedSafUri != null) {
      // SAF implementation
      try {
        final List<saf.DocumentFile> docs = await saf.listFiles(
          _selectedSafUri!,
          columns: saf.DocumentFileColumn.values,
        ).toList();
        for (var doc in docs) {
          if (doc.isFile ?? false) {
            _addFile(doc.name ?? 'Unknown', doc.uri.toString(), doc.size ?? 0, safUri: doc.uri);
          }
        }
      } catch (e) {
        if (kDebugMode) print("SAF Scan error: $e");
      }
    } else if (_selectedDirectory != null) {
      // Standard File I/O
      final dir = Directory(_selectedDirectory!);
      if (dir.existsSync()) {
        final List<FileSystemEntity> entities = dir.listSync(recursive: false);
        for (var entity in entities) {
          if (entity is File) {
            _addFile(p.basename(entity.path), entity.path, entity.lengthSync());
          }
        }
      }
    }

    _initialTotalCount = _files.length;
    _isLoading = false;
    notifyListeners();
  }

  void _addFile(String name, String path, int sizeInBytes, {Uri? safUri}) {
    final sanitizedName = name.replaceAll(RegExp(r'\s\(\d+\)$'), '');
    final ext = p.extension(sanitizedName).toLowerCase();
    FileCategory category = FileCategory.other;

    if (['.jpg', '.jpeg', '.png', '.webp', '.svg', '.heic', '.gif', '.avif'].contains(ext)) {
      category = FileCategory.image;
    } else if (['.mp4', '.mkv', '.mov', '.avi'].contains(ext)) {
      category = FileCategory.video;
    } else if (['.pdf', '.docx', '.txt', '.doc'].contains(ext)) {
      category = FileCategory.document;
    }

    _files.add(CategorizedFile(
      path: path,
      name: name,
      extension: ext,
      category: category,
      sizeInBytes: sizeInBytes,
      documentUri: safUri,
    ));
  }

  // Queue file for deletion
  void deleteFile(CategorizedFile file) {
    _filesToDelete.add(file);
    _removeFileFromList(file);
  }

  // Queue file to keep
  void skipFile(CategorizedFile file) {
    _filesToKeep.add(file);
    _removeFileFromList(file);
  }

  // Restore file back to active queue
  void restoreFile(CategorizedFile file, {required bool fromDeleteQueue}) {
    if (fromDeleteQueue) {
      _filesToDelete.removeWhere((f) => f.path == file.path);
    } else {
      _filesToKeep.removeWhere((f) => f.path == file.path);
    }
    _files.add(file);
    notifyListeners();
  }

  // Apply deletions to disk
  Future<void> finalizeDeletions() async {
    _isLoading = true;
    notifyListeners();

    for (var file in _filesToDelete) {
      try {
        if (Platform.isAndroid && file.documentUri != null) {
          // Delete via SAF
          await saf.delete(file.documentUri!);
        } else {
          // Delete via standard dart:io
          final f = File(file.path);
          if (f.existsSync()) {
            f.deleteSync();
          }
        }
      } catch (e) {
        if (kDebugMode) print("Delete error for ${file.name}: $e");
      }
    }

    _filesToDelete.clear();
    _filesToKeep.clear();
    _initialTotalCount = 0;
    
    // Clear selected directory and file states to return to completely empty state
    _selectedDirectory = null;
    _selectedSafUri = null;
    _isCustomFileSelection = false;
    
    _isLoading = false;
    notifyListeners();
  }

  void clearSession() {
    _files.clear();
    _filesToDelete.clear();
    _filesToKeep.clear();
    _initialTotalCount = 0;
    _selectedDirectory = null;
    _selectedSafUri = null;
    _isCustomFileSelection = false;
    notifyListeners();
  }

  void _removeFileFromList(CategorizedFile file) {
    _files.removeWhere((f) => f.path == file.path);
    notifyListeners();
  }
}
