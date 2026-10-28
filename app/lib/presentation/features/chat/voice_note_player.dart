import 'dart:async';
import 'dart:typed_data';

import 'package:av_chat/presentation/shared/format.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Plays a voice note straight from memory.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    required this.bytes,
    required this.duration,
    required this.color,
    super.key,
  });

  final Uint8List bytes;
  final Duration duration;
  final Color color;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  var _loaded = false;

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_loaded) {
      await _player.setAudioSource(_BytesSource(widget.bytes));
      _loaded = true;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      unawaited(_player.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snap) {
        final playing =
            (snap.data?.playing ?? false) &&
            snap.data?.processingState != ProcessingState.completed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _toggle,
              color: widget.color,
              tooltip: playing ? 'Pause' : 'Play voice note',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  playing ? Icons.pause_circle : Icons.play_circle,
                  key: ValueKey(playing),
                  size: 36,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, pos) {
                  final total = widget.duration.inMilliseconds;
                  final at = pos.data?.inMilliseconds ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: total == 0 ? 0 : (at / total).clamp(0, 1),
                        color: widget.color,
                        backgroundColor: widget.color.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Format.duration(
                          playing ? pos.data ?? Duration.zero : widget.duration,
                        ),
                        style: TextStyle(color: widget.color, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Feeds bytes to the player without writing a file.
class _BytesSource extends StreamAudioSource {
  _BytesSource(this._bytes);
  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(_bytes.sublist(s, e)),
      contentType: 'audio/mp4',
    );
  }
}
