import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Builds the [Media] for [MediaKitAdapter.load]: network URLs carry
/// [headers], `file://` URLs never do (`Media` normalizes them to a path).
Media playableForUrl(String url, Map<String, String>? headers) {
  if (url.startsWith('file://')) return Media(url);
  return Media(url, httpHeaders: headers);
}

/// [VideoPlayerAdapter] over media_kit (libmpv).
///
/// The [Player] and [VideoController] are created in the constructor so
/// [surface] is valid before [load()] runs. Media is always opened with
/// `play: false`; the page owns autoplay, otherwise settled/neighbor policy
/// double-plays. `readyStream` fires on the first position past zero, which
/// mpv only emits while playing — prebuffered (paused) neighbors correctly
/// stay unready until they settle and play.
/// [Player] cannot instantiate headless (needs libmpv), so tests cover only
/// [playableForUrl]; adapter behavior is covered by the fake-adapter widget
/// tests in `leaf_widgets`.
class MediaKitAdapter extends VideoPlayerAdapter implements HasVolume {
  /// [initialVolume] is applied on [load] (media_kit range is 0–100, not 0–1).
  /// [onVolumeChanged] reports user/system volume changes for persistence.
  /// [loop] selects single-item repeat; pass false for play-once.
  MediaKitAdapter({this.initialVolume, this.onVolumeChanged, this.loop = true}) {
    _player = Player();
    _videoController = VideoController(_player);
  }

  final double? initialVolume;
  final ValueChanged<double>? onVolumeChanged;
  final bool loop;

  late final Player _player;
  late final VideoController _videoController;
  StreamSubscription<double>? _volumeSub;
  final _readyCtrl = StreamController<void>.broadcast();
  bool _readyFired = false;
  bool _disposed = false;

  @override
  Widget get surface => Video(
        controller: _videoController,
        controls: NoVideoControls,
        alignment: Alignment.center,
        fit: BoxFit.contain,
        fill: const Color(0x00000000),
      );

  @override
  Future<void> load({required String url, Map<String, String>? headers}) async {
    if (loop) await _player.setPlaylistMode(PlaylistMode.single);
    final volume = initialVolume;
    if (volume != null) {
      try {
        await _player.setVolume(volume);
      } catch (error, stack) {
        debugPrint('MediaKitAdapter.setVolume failed: $error\n$stack');
      }
    }
    final reportVolume = onVolumeChanged;
    if (reportVolume != null) {
      _volumeSub = _player.stream.volume.listen(reportVolume);
    }
    _player.stream.position.where((position) => position > Duration.zero).take(1).listen((_) {
      if (!_readyFired && !_disposed) {
        _readyFired = true;
        _readyCtrl.add(null);
      }
    });
    if (_disposed) return;
    await _player.open(playableForUrl(url, headers), play: false);
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<void> get readyStream => _readyCtrl.stream;
  @override
  Stream<Object> get errorStream => _player.stream.error;

  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  Duration get buffer => _player.state.buffer;
  @override
  bool get isPlaying => _player.state.playing;

  @override
  Stream<double> get volumeStream => _player.stream.volume;
  @override
  double get volume => _player.state.volume;
  @override
  void setVolume(double volume) {
    if (!_disposed) unawaited(_player.setVolume(volume));
  }

  @override
  void play() {
    if (!_disposed) unawaited(_player.play());
  }

  @override
  void pause() {
    if (!_disposed) unawaited(_player.pause());
  }

  @override
  void playOrPause() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  @override
  void seek(Duration target) {
    if (_disposed) return;
    final total = duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (total > Duration.zero && target > total ? total : target);
    unawaited(_player.seek(clamped));
  }

  @override
  void dispose() {
    _disposed = true;
    _volumeSub?.cancel();
    _readyCtrl.close();
    unawaited(_player.dispose());
  }
}
