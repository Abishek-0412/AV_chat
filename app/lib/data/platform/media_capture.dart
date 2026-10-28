import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Photos and voice notes as bytes in memory. Plugins need a file on the
/// way, so each temporary file is deleted as soon as it has been read.
final class MediaCapture {
  /// Raw attachments larger than this would not fit in one envelope.
  static const int maxBytes = 900 * 1024;
  static const Duration maxVoice = Duration(minutes: 2);

  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  String? _recordingPath;
  DateTime? _recordingStarted;

  /// Null if the user cancelled or the photo could not be made small enough.
  Future<Uint8List?> pickImage({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final Uint8List original;
    try {
      original = await file.readAsBytes();
    } finally {
      await _deleteQuietly(file.path);
    }
    // Shrink until it fits; EXIF (location, device) is always dropped.
    for (final (side, quality) in const [(1600, 75), (1280, 65), (960, 55)]) {
      final out = await FlutterImageCompress.compressWithList(
        original,
        minWidth: side,
        minHeight: side,
        quality: quality,
      );
      if (out.length <= maxBytes) return out;
    }
    return null;
  }

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        bitRate: 32000,
        sampleRate: 22050,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: _recordingPath!,
    );
    _recordingStarted = DateTime.now();
    return true;
  }

  /// Returns the recording, or null if it was too short or too big.
  Future<(Uint8List, Duration)?> stopRecording() async {
    final path = await _recorder.stop() ?? _recordingPath;
    final started = _recordingStarted;
    _recordingPath = null;
    _recordingStarted = null;
    if (path == null || started == null) return null;
    try {
      final duration = DateTime.now().difference(started);
      final bytes = await File(path).readAsBytes();
      if (duration < const Duration(milliseconds: 700)) return null;
      if (bytes.length > maxBytes) return null;
      return (bytes, duration);
    } finally {
      await _deleteQuietly(path);
    }
  }

  Future<void> cancelRecording() async {
    final path = await _recorder.stop() ?? _recordingPath;
    _recordingPath = null;
    _recordingStarted = null;
    if (path != null) await _deleteQuietly(path);
  }

  Future<void> dispose() => _recorder.dispose();

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
