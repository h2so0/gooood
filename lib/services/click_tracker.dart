import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ClickTracker {
  ClickTracker._();

  static const _baseUrl =
      'https://asia-northeast3-gooddeal-app.cloudfunctions.net/trackClick';

  /// Fire-and-forget click tracking
  static void track(String type) {
    final url = Uri.parse('$_baseUrl?type=$type');
    http.post(url).catchError((e) {
      debugPrint('[ClickTracker] error: $e');
      return http.Response('', 500);
    });
  }
}
