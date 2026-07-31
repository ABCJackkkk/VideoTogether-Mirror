import 'dart:async';
import 'dart:convert';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';
import 'package:videotogether/webview/app_webview_controller.dart';
import 'package:videotogether/webview/vt_injector.dart';

/// [VTBridge] 的 WebView 实现，通过注入的 VtLite JS 完成房间管理与同步。
///
/// JS API（见 assets/vt-lite.js）：
/// - `window.VtLite.createRoom(name, password, videoEl)` async
/// - `window.VtLite.joinRoom(name, password, videoEl)` async
/// - `window.VtLite.leaveRoom()`
/// - `window.VtLite.sendText(msg)`
/// - `window.VtLite.getState()` → `{role, roomName, wsOpen, memberCount}`
/// - `window.VtLite.flushEvents()` → JSON 字符串，事件队列
///
/// 事件转发：VtLite 把事件存入内部队列，Dart 侧通过定时轮询
/// `flushEvents()` 拉取。不依赖 callHandler（在某些 WebView 页面中不可靠）。
class VTWebViewBridge implements VTBridge {
  final AppWebViewController webview;
  final VTInjector injector;

  final StreamController<VTEvent> _events =
      StreamController<VTEvent>.broadcast();
  bool _injected = false;
  Timer? _pollTimer;

  VTWebViewBridge({required this.webview, required this.injector});

  @override
  Stream<VTEvent> get events => _events.stream;

  /// 在网页加载完后调用：直接注入 VtLite JS，并启动事件轮询。
  /// 不等待 video 元素——VtLite JS 内部 startVideoPolling 会自动轮询绑定。
  Future<void> onPageLoaded() async {
    if (_injected) return;
    await injector.injectOnly();
    _injected = true;
    startPolling();
  }

  /// 重置注入状态（URL 变化后需重新注入）
  void reset() {
    _injected = false;
    stopPolling();
  }

  /// 启动事件轮询：每 500ms 调用 flushEvents() 拉取 VtLite 事件
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _pollEvents();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollEvents() async {
    try {
      final result = await webview.evaluateJavascript(
        'window.VtLite ? window.VtLite.flushEvents() : "[]"',
      );
      if (result == null) return;
      String jsonStr;
      if (result is String) {
        jsonStr = result;
      } else {
        // 某些平台可能返回已解析的对象
        jsonStr = jsonEncode(result);
      }
      if (jsonStr.isEmpty || jsonStr == '[]' || jsonStr == '"[]"') return;
      final List<dynamic> events = jsonDecode(jsonStr);
      for (final event in events) {
        if (event is Map) {
          try {
            _events.add(VTEvent.fromJson(event.cast<String, dynamic>()));
          } catch (_) {}
        }
      }
    } catch (_) {
      // 轮询失败静默忽略，下次重试
    }
  }

  Future<dynamic> _eval(String js) async {
    return webview.evaluateJavascript(js);
  }

  @override
  Future<Room> createRoom({required String name, String password = ''}) async {
    await _eval(
      'window.VtLite.createRoom('
      '${_jsStr(name)}, ${_jsStr(password)}, document.querySelector("video")'
      ')',
    );
    // VtLite.createRoom 返回 void，构造 Room 由本地完成
    return Room(
      id: name,
      name: name,
      members: const [],
      memberCount: 1,
    );
  }

  @override
  Future<Room> joinRoom({required String name, String password = ''}) async {
    await _eval(
      'window.VtLite.joinRoom('
      '${_jsStr(name)}, ${_jsStr(password)}, document.querySelector("video")'
      ')',
    );
    // VtLite.joinRoom 返回 void，房间状态通过 room_update 事件异步到达
    return Room(
      id: name,
      name: name,
      members: const [],
    );
  }

  @override
  Future<void> leaveRoom() async {
    stopPolling();
    await _eval('window.VtLite.leaveRoom()');
  }

  @override
  Future<void> pause() async {
    // VtLite 自动监听 video 元素，无需手动调
  }

  @override
  Future<void> play() async {
    // VtLite 自动监听 video 元素，无需手动调
  }

  @override
  Future<void> seek(double seconds) async {
    // VtLite 自动监听 video 元素，无需手动调
  }

  @override
  Future<void> sendMessage(String text) async {
    await _eval('window.VtLite.sendText(${_jsStr(text)})');
  }

  @override
  void dispose() {
    stopPolling();
    _events.close();
  }
}

/// 把 Dart 字符串转成 JS 字符串字面量（单引号包裹，转义反斜杠和单引号）
String _jsStr(String s) {
  final escaped = s.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  return "'$escaped'";
}
