import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_adapter_media_kit/video_adapter_media_kit.dart';

PlayerLog log(String prefix, String level, String text) => PlayerLog(prefix: prefix, level: level, text: text);

void main() {
  const loaded = Duration(seconds: 6);

  test('mpv errors of a file that opened are no load failure', () {
    for (final line in [
      log('vd', 'error', 'Error while decoding frame (hardware decoding)!'),
      log('ad', 'error', 'Error decoding audio.'),
      log('ffmpeg', 'error', 'tcp: Connection to tcp://127.0.0.1:1 failed: Connection refused'),
      log('stream', 'error', 'Failed to reopen the stream.'),
      log('cplayer', 'error', 'Could not open/initialize audio device -> no sound.'),
    ]) {
      expect(mpvLoadFailed(line, loaded), isFalse, reason: line.text);
    }
  });

  test('errors outside the open path are no load failure, even before a duration', () {
    expect(mpvLoadFailed(log('lavf', 'error', 'Failed to create file cache.'), Duration.zero), isFalse);
    expect(mpvLoadFailed(log('ffmpeg/video', 'error', 'h264: error while decoding MB 15 8'), Duration.zero), isFalse);
    expect(mpvLoadFailed(log('cplayer', 'warn', 'Something.'), Duration.zero), isFalse);
  });

  test('a file mpv cannot open or recognize is a load failure', () {
    for (final line in [
      log('cplayer', 'error', 'Failed to recognize file format.'),
      log('file', 'error', 'Cannot open file: No such file or directory'),
      log('stream', 'error', 'Failed to open the media.'),
      log('demux', 'error', 'Failed to open the demuxer.'),
      log('cplayer', 'fatal', 'No video or audio streams selected.'),
    ]) {
      expect(mpvLoadFailed(line, Duration.zero), isTrue, reason: line.text);
    }
  });
}
