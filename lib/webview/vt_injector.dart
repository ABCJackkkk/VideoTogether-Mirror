import 'package:flutter/services.dart' show rootBundle;

/// JS 执行器抽象（便于测试）
abstract class JsEvaluator {
  Future<dynamic> evaluate(String source);
}

/// Assets 读取抽象（便于测试）
abstract class AssetsLoader {
  Future<String> loadString(String path);
}

class _RootBundleAssetsLoader implements AssetsLoader {
  @override
  Future<String> loadString(String path) => rootBundle.loadString(path);
}

class VideoNotFoundException implements Exception {
  @override
  String toString() => '未检测到可同步的视频元素';
}

/// 轮询直到页面出现 `<video>` 元素，然后把 `assets/vt-lite.js` 注入 WebView
class VTInjector {
  static const String _assetPath = 'assets/vt-lite.js';

  final JsEvaluator js;
  final AssetsLoader assets;
  final Duration pollInterval;
  final int maxAttempts;

  VTInjector({
    required this.js,
    AssetsLoader? assets,
    this.pollInterval = const Duration(milliseconds: 500),
    this.maxAttempts = 20,
  }) : assets = assets ?? _RootBundleAssetsLoader();

  /// 轮询直到 <video> 出现，然后注入 VtLite JS
  Future<void> waitForVideoAndInject() async {
    for (var i = 0; i < maxAttempts; i++) {
      final has = await js.evaluate('!!document.querySelector("video")');
      if (has == true) {
        await injectOnly();
        return;
      }
      await Future.delayed(pollInterval);
    }
    throw VideoNotFoundException();
  }

  /// 直接注入 VtLite JS，不等待 video 元素
  Future<void> injectOnly() async {
    final vtJs = await assets.loadString(_assetPath);
    await js.evaluate(vtJs);
  }
}
