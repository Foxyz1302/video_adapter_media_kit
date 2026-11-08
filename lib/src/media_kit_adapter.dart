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

/// Whether [log] means the media failed to load, given the player's
/// [duration] when it arrived.
///
/// `Player.stream.error` also carries mpv errors a playing file recovers
/// from (decoder, audio, network retries), so it is no failure signal. A
/// file failed only when mpv could not open or recognize it: an error from
/// `cplayer`, `stream`, `file` or `demux` before any duration is known.
bool mpvLoadFailed(PlayerLog log, Duration duration) {
  if (duration > Duration.zero) return false;
  if (log.level != 'error' && log.level != 'fatal') return false;
  return const {'cplayer', 'stream', 'file', 'demux'}.contains(log.prefix);
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
  /// [playerConfiguration] and [videoControllerConfiguration] reach the
  /// [Player] and [VideoController] as-is; [mpvProperties] are set on mpv
  /// right before the media opens, for options mpv reads at open time.
  MediaKitAdapter({
    this.initialVolume,
    this.onVolumeChanged,
    this.loop = true,
    PlayerConfiguration playerConfiguration = const PlayerConfiguration(),
    VideoControllerConfiguration videoControllerConfiguration = const VideoControllerConfiguration(),
    this.mpvProperties = const {},
  }) {
    _player = Player(configuration: playerConfiguration);
    _videoController = VideoController(_player, configuration: videoControllerConfiguration);
  }

  final double? initialVolume;
  final ValueChanged<double>? onVolumeChanged;
  final bool loop;
  final Map<String, String> mpvProperties;

  late final Player _player;
  late final VideoController _videoController;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<PlayerLog>? _logSub;
  final _readyCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();
  bool _readyFired = false;
  bool _loadFailed = false;
  bool _disposed = false;

  /// The underlying player, e.g. for mpv properties (`player.platform` is a
  /// [NativePlayer] on native platforms).
  Player get player => _player;

  VideoController get videoController => _videoController;

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
    _loadFailed = false;
    _logSub ??= _player.stream.log.listen((log) {
      if (_loadFailed || _disposed || !mpvLoadFailed(log, _player.state.duration)) return;
      _loadFailed = true;
      _errorCtrl.add(log.text);
    });
    _player.stream.position.where((position) => position > Duration.zero).take(1).listen((_) {
      if (!_readyFired && !_disposed) {
        _readyFired = true;
        _readyCtrl.add(null);
      }
    });
    final platform = _player.platform;
    if (platform is NativePlayer) {
      for (final property in mpvProperties.entries) {
        if (_disposed) return;
        await platform.setProperty(property.key, property.value);
      }
    }
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
  Stream<Object> get errorStream => _errorCtrl.stream;

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
    _logSub?.cancel();
    _readyCtrl.close();
    _errorCtrl.close();
    unawaited(_player.dispose());
  }
}
