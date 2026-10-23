import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Capped pool of warm media_kit [Player]s for scroll feeds.
///
/// Creating a [Player] spins up a full mpv instance (threads, config) which
/// janks on scroll churn; destroying one per disposed tile repeats that cost
/// forever. Pooled players are [Player.stop]ped on release (demuxer/decoder
/// freed, no media held, no traffic) and handed out again on acquire.
///
/// Every pooled player uses [bufferSize] as its demuxer cache: preloaded
/// neighbors each hold at most that much, so feed scroll traffic stays
/// bounded no matter how many tiles prebuild. Default 32 MB (media_kit
/// default) would hoard per tile; 8 MB covers instant start for short clips.
///
/// Not unit-testable headless ([Player] needs libmpv); verify on device.
/// [VideoController] needs no pooling or disposal — it is cheap, tile-owned,
/// and dropped with the tile; only the [Player] cycles through here.
class MkPlayerPool {
  /// [maxSize] caps the idle stash; surplus releases are disposed.
  /// [bufferSize] is the per-player demuxer cache in bytes.
  MkPlayerPool({this.maxSize = 4, this.bufferSize = 8 * 1024 * 1024})
      : assert(maxSize > 0),
        assert(bufferSize > 0);

  final int maxSize;
  final int bufferSize;

  final _idle = <Player>[];

  /// Warm, media-free players currently stashed.
  int get idleCount => _idle.length;

  /// A warm player, or a fresh one when the stash is empty.
  Player acquire() {
    if (_idle.isNotEmpty) return _idle.removeLast();
    return Player(configuration: PlayerConfiguration(bufferSize: bufferSize));
  }

  /// Stops [player] (frees media/traffic) and stashes it, disposing instead
  /// once the stash is full. Never touch [player] after calling this.
  void release(Player player) {
    unawaited(player.stop());
    if (_idle.length < maxSize) {
      _idle.add(player);
    } else {
      unawaited(player.dispose());
    }
  }

  /// Disposes the whole stash, e.g. on app scope teardown.
  void dispose() {
    for (final player in _idle) {
      unawaited(player.dispose());
    }
    _idle.clear();
  }
}
