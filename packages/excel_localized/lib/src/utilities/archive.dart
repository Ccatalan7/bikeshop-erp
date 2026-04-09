part of excel;

Archive _cloneArchive(
  Archive archive,
  Map<String, ArchiveFile> archiveFiles, {
  String? excludedFile,
}) {
  var clone = Archive();
  for (var file in archive.files) {
    if (file.isFile) {
      if (excludedFile != null &&
          file.name.toLowerCase() == excludedFile.toLowerCase()) {
        continue;
      }
      ArchiveFile copy;
      if (archiveFiles.containsKey(file.name)) {
        copy = archiveFiles[file.name]!;
      } else {
        var content = file.content;
        // var compress = !_noCompression.contains(file.name);
        copy = ArchiveFile(file.name, content.length, content);
        // ..compress = compress; // Removed for archive 4 compatibility
      }
      clone.addFile(copy);
    }
  }
  return clone;
}
