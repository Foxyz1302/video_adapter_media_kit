import 'package:flutter_test/flutter_test.dart';
import 'package:video_adapter_media_kit/video_adapter_media_kit.dart';

void main() {
  test('network urls carry headers through', () {
    final playable = playableForUrl('https://file.pawchive.pw/data/abc?f=a.mp4', {
      'Referer': 'https://pawchive.pw/',
    });
    expect(playable.uri, 'https://file.pawchive.pw/data/abc?f=a.mp4');
    expect(playable.httpHeaders, {'Referer': 'https://pawchive.pw/'});
  });

  test('network urls without headers stay headerless', () {
    final playable = playableForUrl('https://example.com/v.mp4', null);
    expect(playable.uri, 'https://example.com/v.mp4');
    expect(playable.httpHeaders, isNull);
  });

  test('file urls never carry headers', () {
    final playable = playableForUrl('file:///tmp/clip.mp4', {'Referer': 'https://pawchive.pw/'});
    expect(playable.uri, '/tmp/clip.mp4');
    expect(playable.httpHeaders, isNull);
  });
}
