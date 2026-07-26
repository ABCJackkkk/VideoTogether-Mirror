import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 对 [InAppWebViewController] 的业务层封装
///
/// 提供 loadUrl / injectJS / registerHandler 三个高层方法，隔离上层对
/// flutter_inappwebview 具体类型的依赖。
class AppWebViewController {
  InAppWebViewController? _raw;

  /// 由 InAppWebView widget 的 onCreate 回调注入
  void attach(InAppWebViewController controller) {
    _raw = controller;
    // 桌面 UA，规避移动端反爬
    controller.setSettings(
      settings: InAppWebViewSettings(
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
    );
  }

  void detach() => _raw = null;

  /// 加载指定 URL
  Future<void> loadUrl(String url) async {
    await _raw?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// 注入一段 JS，返回其执行结果
  Future<dynamic> evaluateJavascript(String source) async {
    return _raw?.evaluateJavascript(source: source);
  }

  /// 注册 Dart 侧 handler，供 JS 通过 callHandler 调用
  ///
  /// JS 侧调用方式：`window.flutter_inappwebview.callHandler(name, ...args)`
  /// Dart 侧 [handler] 收到的参数即 args 列表。
  void registerHandler(
    String name,
    Future<dynamic> Function(List<dynamic> args) handler,
  ) {
    _raw?.addJavaScriptHandler(handlerName: name, callback: handler);
  }

  /// 拦截 App 唤起 scheme，只放行 http/https
  void configureUrlInterception() {
    _raw?.setSettings(
      settings: InAppWebViewSettings(useShouldOverrideUrlLoading: true),
    );
  }

  bool get isAttached => _raw != null;
}
