import 'dart:async';
import 'dart:convert';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';
import 'package:videotogether/webview/app_webview_controller.dart';

/// [VTBridge] 的 WebView 实现，直接调用 VT 原版油猴脚本的 API。
///
/// 原版脚本（assets/vt-original.user.js）通过 initialUserScripts 注入，
/// 自带 video 查找（跨域 iframe postMessage）、ScheduledTask 同步、WS 重连、浮动面板 UI。
///
/// 原版公开 API（window.videoTogetherExtension）：
/// - `CreateRoom(name, password)` async — 同步设置 role=Master/roomName 后异步上报
/// - `JoinRoom(name, password)` async — 同步设置 role=Member/roomName
/// - `exitRoom()` — 断开 WS、清空状态
///
/// 原版不主动通知 Dart，Dart 侧每 500ms 轮询 extension 状态属性，
/// 检测变化后转发为 [VTEvent]。
class VTWebViewBridge implements VTBridge {
  final AppWebViewController webview;

  /// 聊天昵称（原版用 VideoTogetherStorage，这里暂不透传，原版自带聊天 UI）
  String nickname = '';

  final StreamController<VTEvent> _events =
      StreamController<VTEvent>.broadcast();
  Timer? _pollTimer;

  /// 上一次轮询到的状态，用于检测变化
  int _lastRole = 1; // RoleEnum.Null = 1
  String _lastRoomName = '';
  String _lastUrl = '';
  int _lastMemberCount = 0;
  bool _lastWsOpen = false;
  bool _roomAnnounced = false;

  VTWebViewBridge({required this.webview});

  @override
  Stream<VTEvent> get events => _events.stream;

  /// 原版脚本通过 initialUserScripts 自动注入，onPageLoaded 只需启动轮询。
  /// 保留方法签名兼容 watch_page.dart 调用。
  Future<void> onPageLoaded() async {
    startPolling();
  }

  /// 查询原版 extension 是否已就绪
  Future<bool> hasVtLite() async {
    try {
      final result = await webview.evaluateJavascript(
        'typeof window.videoTogetherExtension === "object" && '
        'window.videoTogetherExtension !== null',
      );
      return result == true || result == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 重置状态（URL 变化后原版脚本会重新初始化）
  void reset() {
    _roomAnnounced = false;
    _lastRole = 1;
    _lastRoomName = '';
    stopPolling();
  }

  /// 启动状态轮询：每 500ms 读 extension 的 role/roomName/url/memberCount
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _pollState();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollState() async {
    try {
      final result = await webview.evaluateJavascript(_pollJs);
      if (result == null) return;
      String jsonStr;
      if (result is String) {
        jsonStr = result;
      } else {
        jsonStr = jsonEncode(result);
      }
      // evaluateJavascript 返回 JSON 字符串可能带引号
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
        jsonStr = jsonStr
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\')
            .replaceAll(r'\n', '\n');
      }
      if (jsonStr.isEmpty || jsonStr == 'null') return;
      final Map<String, dynamic> state;
      try {
        state = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      _handleState(state);
    } catch (_) {
      // 轮询失败静默忽略
    }
  }

  /// 轮询 JS：一次性读取 extension 状态 + DOM 成员数
  static const String _pollJs = '''
(function(){
  var ext = window.videoTogetherExtension;
  if (!ext || ext === null) return JSON.stringify({ready:false});
  var mc = 0;
  try {
    var el = document.querySelector('#memberCount');
    if (el) mc = parseInt(el.innerText.replace(/[^0-9]/g,'')) || 0;
  } catch(e){}
  var wsOpen = false;
  try { wsOpen = !!ext.ctxWsIsOpen; } catch(e){}
  return JSON.stringify({
    ready: true,
    role: ext.role,
    roomName: ext.roomName || '',
    url: window.location.href || '',
    memberCount: mc,
    wsOpen: wsOpen
  });
})()
''';

  void _handleState(Map<String, dynamic> state) {
    final ready = state['ready'] == true;
    if (!ready) return;

    final role = (state['role'] as num?)?.toInt() ?? 1;
    final roomName = (state['roomName'] as String?) ?? '';
    final url = (state['url'] as String?) ?? '';
    final memberCount = (state['memberCount'] as num?)?.toInt() ?? 0;
    final wsOpen = state['wsOpen'] == true;

    // role 从 Null 变为 Master(2)/Member(3)：房间创建/加入成功
    if (!_roomAnnounced && role != 1 && roomName.isNotEmpty) {
      _roomAnnounced = true;
      _events.add(RoomUpdateEvent(
        room: Room(
          id: roomName,
          name: roomName,
          members: const [],
          memberCount: memberCount > 0 ? memberCount : (role == 2 ? 1 : 0),
          url: url,
        ),
      ));
    }

    // 已在房间内：状态变化时发更新事件
    if (_roomAnnounced && roomName.isNotEmpty) {
      if (roomName != _lastRoomName ||
          url != _lastUrl ||
          memberCount != _lastMemberCount) {
        _events.add(RoomUpdateEvent(
          room: Room(
            id: roomName,
            name: roomName,
            members: const [],
            memberCount: memberCount,
            url: url,
          ),
        ));
      }
    }

    // WS 状态变化
    if (wsOpen != _lastWsOpen) {
      if (wsOpen) {
        _events.add(const WsOpenEvent());
      }
    }

    // role 变回 Null：退出了房间
    if (_roomAnnounced && role == 1) {
      _roomAnnounced = false;
    }

    _lastRole = role;
    _lastRoomName = roomName;
    _lastUrl = url;
    _lastMemberCount = memberCount;
    _lastWsOpen = wsOpen;
  }

  Future<dynamic> _eval(String js) async {
    return webview.evaluateJavascript(js);
  }

  @override
  Future<Room> createRoom({required String name, String password = ''}) async {
    // 原版 CreateRoom 是 async，但同步设置 role/roomName 后才异步上报，
    // evaluateJavascript 不等 Promise，返回时状态已就绪
    final ready = await _eval(
      'typeof window.videoTogetherExtension === "object" && '
      'window.videoTogetherExtension !== null && '
      'typeof window.videoTogetherExtension.CreateRoom === "function"',
    );
    if (ready != true && ready != 'true') {
      throw StateError('VT 原版脚本未注入，请重试或检查网络');
    }
    await _eval(
      'window.videoTogetherExtension.CreateRoom(${_jsStr(name)}, ${_jsStr(password)})',
    );
    return Room(
      id: name,
      name: name,
      members: const [],
      memberCount: 1,
    );
  }

  @override
  Future<Room> joinRoom({required String name, String password = ''}) async {
    final ready = await _eval(
      'typeof window.videoTogetherExtension === "object" && '
      'window.videoTogetherExtension !== null && '
      'typeof window.videoTogetherExtension.JoinRoom === "function"',
    );
    if (ready != true && ready != 'true') {
      throw StateError('VT 原版脚本未注入，请重试或检查网络');
    }
    await _eval(
      'window.videoTogetherExtension.JoinRoom(${_jsStr(name)}, ${_jsStr(password)})',
    );
    return Room(
      id: name,
      name: name,
      members: const [],
    );
  }

  @override
  Future<void> leaveRoom() async {
    stopPolling();
    try {
      await _eval('window.videoTogetherExtension.exitRoom()');
    } catch (_) {
      // WebView 可能已销毁，静默忽略
    }
  }

  @override
  Future<void> pause() async {
    // 原版 ScheduledTask 自动同步 video，无需手动调
  }

  @override
  Future<void> play() async {
    // 原版 ScheduledTask 自动同步 video，无需手动调
  }

  @override
  Future<void> seek(double seconds) async {
    // 原版 ScheduledTask 自动同步 video，无需手动调
  }

  @override
  Future<void> sendMessage(String text) async {
    // 原版自带聊天 UI，Dart 侧不介入
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
