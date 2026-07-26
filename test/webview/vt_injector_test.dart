import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/webview/vt_injector.dart';

class _FakeJsEvaluator implements JsEvaluator {
  final List<String> calls = [];
  int _videoQueryCount = 0;
  bool alwaysReturnFalse = false;

  @override
  Future<dynamic> evaluate(String source) async {
    if (alwaysReturnFalse) return false;
    calls.add(source);
    if (source.contains('querySelector("video")')) {
      _videoQueryCount++;
      return _videoQueryCount >= 2; // 第二次轮询时返回 true
    }
    return null;
  }
}

class _FakeAssetsLoader implements AssetsLoader {
  final List<String> loadedPaths = [];
  String content = 'console.log("vt-lite");';

  @override
  Future<String> loadString(String path) async {
    loadedPaths.add(path);
    return content;
  }
}

void main() {
  test('轮询直到 video 元素出现后注入 VtLite JS', () async {
    final js = _FakeJsEvaluator();
    final assets = _FakeAssetsLoader();
    final injector = VTInjector(js: js, assets: assets);

    await injector.waitForVideoAndInject();

    // 应该有 querySelector 调用 + 注入调用
    expect(js.calls.any((c) => c.contains('querySelector("video")')), isTrue);
    expect(js.calls.any((c) => c.contains('console.log("vt-lite")')), isTrue);
    // 加载的是 vt-lite.js，不是 vt-client.js
    expect(assets.loadedPaths, contains('assets/vt-lite.js'));
  });

  test('超时（maxAttempts 次无 video）后抛 VideoNotFoundException', () async {
    final js = _FakeJsEvaluator()..alwaysReturnFalse = true;
    final assets = _FakeAssetsLoader();
    final injector = VTInjector(
      js: js,
      assets: assets,
      pollInterval: const Duration(milliseconds: 10),
      maxAttempts: 3,
    );

    await expectLater(
      injector.waitForVideoAndInject(),
      throwsA(isA<VideoNotFoundException>()),
    );
  });

  test('VideoNotFoundException toString 非空', () {
    expect(VideoNotFoundException().toString(), isNotEmpty);
  });
}
