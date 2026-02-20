import 'package:flutter/foundation.dart' show kIsWeb;

const _proxyBase =
    'https://asia-northeast3-gooddeal-app.cloudfunctions.net/imageProxy?url=';

/// 웹에서는 CORS 프록시 경유, 모바일에서는 원본 URL 사용
String proxyImage(String url) {
  if (!kIsWeb || url.isEmpty) return url;
  return '$_proxyBase${Uri.encodeComponent(url)}';
}

/// 이미지 URL → aspect ratio (width / height) 전역 캐시
final _imageAspectCache = <String, double>{};

double? getCachedAspectRatio(String url) => _imageAspectCache[url];

void cacheAspectRatio(String url, double ratio) =>
    _imageAspectCache[url] = ratio;
