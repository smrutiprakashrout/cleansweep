import 'dart:io';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'file_service.dart';
import 'file_card.dart';
import 'swipeable_card_stack.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(450, 850),
      minimumSize: Size(400, 700),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => FileService(),
      child: const CleanSweepApp(),
    ),
  );
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class CleanSweepApp extends StatelessWidget {
  const CleanSweepApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanSweep',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
      ),
      scrollBehavior: AppScrollBehavior(),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<SwipeableCardStackState> _swipeKey = GlobalKey<SwipeableCardStackState>();

  Future<String?> _pickDirectoryPath() async {
    if (Platform.isAndroid) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Select Folder to Organize"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text("Downloads"),
                  onTap: () => Navigator.pop(context, '/storage/emulated/0/Download'),
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text("Documents"),
                  onTap: () => Navigator.pop(context, '/storage/emulated/0/Documents'),
                ),
                ListTile(
                  leading: const Icon(Icons.image),
                  title: const Text("Pictures"),
                  onTap: () => Navigator.pop(context, '/storage/emulated/0/Pictures'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text("Other (System Picker)"),
                  subtitle: const Text("Android 11+ reduces access to the root Downloads folder", style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(context, 'SYSTEM_PICKER'),
                ),
              ],
            ),
          );
        },
      );
      
      if (result == 'SYSTEM_PICKER') {
        return await FilePicker.platform.getDirectoryPath();
      }
      return result;
    }
    return await FilePicker.platform.getDirectoryPath();
  }

  Future<void> _organizeDirectory() async {
    if (Platform.isAndroid) {
      bool hasAccess = false;
      
      // Request standard storage permission (shows native popup on Android <= 12)
      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }
      if (storageStatus.isGranted) {
        hasAccess = true;
      }

      // Request granular media permissions (shows native popup on Android 13+)
      if (!hasAccess) {
        var photosStatus = await Permission.photos.request();
        var videosStatus = await Permission.videos.request();
        var audioStatus = await Permission.audio.request();
        
        if (photosStatus.isGranted || videosStatus.isGranted || audioStatus.isGranted) {
          hasAccess = true;
        }
      }

      // Request MANAGE_EXTERNAL_STORAGE (opens settings on Android 11+)
      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }
      if (manageStatus.isGranted) {
        hasAccess = true;
      }

      if (!hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Storage permission is required to organize folders. "
                "Please grant 'All files access' in Settings.",
              ),
            ),
          );
        }
        await openAppSettings();
        return;
      }
    }

    final String? path = await _pickDirectoryPath();
    if (path == null) return;

    if (!mounted) return;

    int fileCount = 0;
    try {
      final dir = Directory(path);
      final List<FileSystemEntity> entities = await dir.list(recursive: false).toList();

      for (var entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          String? categoryFolder;

          if (['.jpg', '.png', '.jpeg', '.gif', '.svg' ,'.avif', '.webp', '.heic'].contains(ext)) {
            categoryFolder = 'Images';
          } else if (['.ico','.ai','.icns'].contains(ext)) {
            categoryFolder = 'VectorArt';
          } else if (['.mp4', '.mkv', '.mov', '.avi','.webm'].contains(ext)) {
            categoryFolder = 'Videos';
          } else if (['.pdf', '.docx', '.txt', '.xlsx','.xls','.doc'].contains(ext)) {
            categoryFolder = 'Documents';
          } else if (['.zip', '.rar', '.7z', '.tar.gz'].contains(ext)) {
            categoryFolder = 'Archives';
          }else if (['.apk','.deb','.rpm','.exe','.tar.xz','.AppImage','.x86_64'].contains(ext)) {
            categoryFolder = 'Package';
          }else if (['.mp3'].contains(ext)) {
            categoryFolder = 'audio';
          }else if (['.iso'].contains(ext)) {
            categoryFolder = 'IsoFiles';
          }else {
            categoryFolder = 'Others';
          }

          if (categoryFolder != null) {
            final targetDir = Directory(p.join(path, categoryFolder));
            if (!await targetDir.exists()) {
              await targetDir.create();
            }
            final newPath = p.join(targetDir.path, p.basename(entity.path));
            
            // In scoped storage, rename can throw FileSystemException if not permitted.
            await entity.rename(newPath);
            fileCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Boom! $fileCount files organized")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error organizing folder. Details: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileService = context.watch<FileService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CleanSweep',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
            if (fileService.files.isNotEmpty)
              Text(
                "${fileService.currentIndex} of ${fileService.initialTotalCount}",
                style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          if (fileService.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                onPressed: () {
                  fileService.clearSession();
                  _focusNode.requestFocus();
                },
                icon: const Icon(Icons.refresh, color: Colors.white54),
                tooltip: "Reset Session",
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: InkWell(
              onTap: () {
                fileService.pickDirectory();
                _focusNode.requestFocus();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: fileService.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, fileService),
    );
  }

  Widget _buildBody(BuildContext context, FileService fileService) {
    if (fileService.files.isEmpty) {
      if (fileService.hasReviewedFiles) {
        return _buildReviewScreen(context, fileService);
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5), width: 2),
                  borderRadius: BorderRadius.circular(32),
                  color: Colors.blueAccent.withValues(alpha: 0.05),
                ),
                child: const Icon(Icons.folder_outlined, size: 64, color: Colors.blueAccent),
              ),
              const SizedBox(height: 32),
              const Text(
                "Ready to Sweep",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                "Pick files from your device to start categorizing and cleaning up",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        fileService.pickMultipleFiles();
                        _focusNode.requestFocus();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.file_copy, color: Colors.black),
                      label: const Text("Pick Files", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        fileService.pickDirectory();
                        _focusNode.requestFocus();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: Icon(Icons.folder_open, color: Colors.blue.shade300),
                      label: Text("Pick Folder", style: TextStyle(color: Colors.blue.shade300, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _organizeDirectory();
                    _focusNode.requestFocus();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigoAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.auto_awesome, color: Colors.white),
                  label: const Text("Organize Your Folder", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  "⣾ K/← Keep · L/→ Delete",
                  style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    final currentFile = fileService.files.first;
    final hasNext = fileService.files.length > 1;

    Widget body = Column(
      children: [
        Expanded(
          child: SwipeableCardStack(
            key: _swipeKey,
            files: fileService.files,
            onSwipeLeft: (f) {
              fileService.skipFile(f);
              _focusNode.requestFocus();
            },
            onSwipeRight: (f) {
              fileService.deleteFile(f);
              _focusNode.requestFocus();
            },
          ),
        ),
        
        // Buttons Row
        Padding(
          padding: const EdgeInsets.only(bottom: 32.0, left: 32, right: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Keep Button
              GestureDetector(
                onTap: () {
                  _swipeKey.currentState?.swipeLeft();
                },
                child: Row(
                  children: [
                    const Text("← Keep", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(width: 16),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.greenAccent, width: 2),
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                      ),
                      child: const Icon(Icons.check, color: Colors.greenAccent, size: 32),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Delete Button
              GestureDetector(
                onTap: () {
                  _swipeKey.currentState?.swipeRight();
                },
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.redAccent, width: 2),
                        color: Colors.redAccent.withValues(alpha: 0.1),
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 32),
                    ),
                    const SizedBox(width: 16),
                    const Text("Delete →", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyL ||
              event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.delete) {
            _swipeKey.currentState?.swipeRight(customDuration: const Duration(milliseconds: 500));
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyK ||
                     event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _swipeKey.currentState?.swipeLeft(customDuration: const Duration(milliseconds: 500));
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: body,
      ),
    );
  }

  Widget _buildReviewScreen(BuildContext context, FileService fileService) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.analytics, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            "Review Summary",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          _buildStatRow("Total Scanned", fileService.initialTotalCount, Colors.blueGrey),
          const SizedBox(height: 16),
          _buildStatRow("Keeping", fileService.filesToKeep.length, Colors.green),
          const SizedBox(height: 16),
          _buildStatRow("Deleting", fileService.filesToDelete.length, Colors.redAccent),
          const SizedBox(height: 48),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    fileService.clearSession();
                  },
                  icon: const Icon(Icons.cancel),
                  label: const Text("Discard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await fileService.finalizeDeletions();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Application of changes successful!")),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          Text(value.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
