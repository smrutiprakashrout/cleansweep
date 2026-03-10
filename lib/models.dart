enum FileCategory {
  image,
  video,
  document,
  other,
}

class CategorizedFile {
  final String path;
  final String name;
  final String extension;
  final FileCategory category;
  final Uri? documentUri;
  final int sizeInBytes;

  CategorizedFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.category,
    required this.sizeInBytes,
    this.documentUri,
  });
}
