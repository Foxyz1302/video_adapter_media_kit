# video_adapter_media_kit

`VideoPlayerAdapter` over media_kit (libmpv) + a warm player pool. Shared
by media_kit consumers (kemono_browser_project; civit_project's mobile
debug toggle).

Depends on `leaf_widgets`, `media_kit`, `media_kit_video` — deliberately
NOT on `media_kit_libs_video`. The app owns native libs (bundle vs split
per-platform libs) and calls `MediaKit.ensureInitialized()` in `main()`;
this package assumes both.

## `MediaKitAdapter`

| Member | Source | Notes |
|---|---|---|
| `surface` | `Video(NoVideoControls, contain, transparent)` | Player + controller are built in the ctor — the page reads `surface` before `load()` |
| `load(url, headers)` | `open(playable, play: false)` | The page owns autoplay; opening with `play: true` double-plays against settled/neighbor policy |
| `readyStream` | first `position > Duration.zero` | Approximation — mpv exposes no first-frame callback. Paused prebuffered neighbors correctly stay unready; the spinner clears on settle-play |
| `errorStream` | `stream.error` | Load-time throws propagate via the `load()` future → page retry UI |
| `seek` | clamped to `[0, duration]` | `duration == 0` pre-load means "no clamp" |
| volume | `HasVolume` → `stream.volume` / `setVolume` | Range is **0–100**, not 0–1; the desktop slider assumes this |
| `file://` URLs | `Media(url)`, headers dropped | `Media` normalizes to a path (tested). Temp-file delete belongs to the caller, after `dispose()` completes (Windows file lock) |

Ctor opts (not interface members): `initialVolume` applied on load,
`onVolumeChanged` for persistence, `loop` for single-item repeat.

## `MkPlayerPool`

Capped pool of warm players for scroll feeds: `acquire()` hands a
stopped player or builds one, `release()` stops (frees media/traffic) and
stashes up to `maxSize`, disposing surplus. Every pooled player uses
`bufferSize` (default 8 MB) as its demuxer cache instead of media_kit's
32 MB default, so preloaded neighbors each hold at most that much —
watched video streams through normally. `VideoController` needs no
pooling: it is cheap, tile-owned, and dropped with the tile.

Cross-cutting first-decode throttling lives in `leaf_widgets` as
`FirstFrameGate`, not here — it covers both engines.

## Tests

`Player` cannot instantiate headless (needs libmpv), so tests cover only
the pure `playableForUrl` helper (`test/media_selection_test.dart`).
Adapter behavior is covered indirectly by the fake-adapter widget tests in
`leaf_widgets/test/video/`. Don't add tests that construct `Player`; they
die in CI. Verify on device: first-frame timing, volume persistence,
short-clip cover drop.

## Non-goals

Tracks, speed, subtitles, screenshots, playlists, downloads. App code
casts to `MediaKitAdapter`/`Player` for those. A second consumer-facing
feature here probably belongs app-side.
