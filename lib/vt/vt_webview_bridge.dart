import 'dart:async';
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
///
/// 事件转发：VtLite 通过
/// `window.flutter_inappwebview.callHandler('vtEvent', {event, data})` 把事件
/// 派发到 Dart 侧。本类在构造时注册 `vtEvent` handler，把 JSON 解析为
/// [VTEvent] 后投递到 [events] 流。
class VTWebViewBridge implements VTBridge {
  final AppWebViewController webview;
  final VTInjector injector;

  final StreamController<VTEvent> _events =
      StreamController<VTEvent>.broadcast();
  bool _injected = false;

  VTWebViewBridge({required this.webview, required this.injector}) {
    webview.registerHandler('vtEvent', _handleVtEvent);
  }

  Future<dynamic> _handleVtEvent(List<dynamic> args) async {
    if (args.isEmpty) return;
    final raw = args.first;
    if (raw is Map) {
      try {
        _events.add(VTEvent.fromJson(raw.cast<String, dynamic>()));
      } catch (_) {
        // 解析失败忽略，避免影响 JS 侧
      }
    }
    return null;
  }

  @override
  Stream<VTEvent> get events => _events.stream;

  /// 在网页加载完后调用：注入 VtLite JS（含轮询等 video 出现）
  Future<void> onPageLoaded() async {
    if (_injected) return;
    await injector.waitForVideoAndInject();
    _injected = true;
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
    _events.close();
  }
}

/// 把 Dart 字符串转成 JS 字符串字面量（单引号包裹，转义反斜杠和单引号）
String _jsStr(String s) {
  final escaped = s.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  return "'$escaped'";
}
