import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

/// 房间状态机的几个状态
enum RoomStoreState { idle, loading, inRoom, error }

/// WebSocket 连接状态
enum WsStatus { disconnected, connecting, connected, reconnecting }

/// 房间状态管理（ChangeNotifier）
///
/// 监听 [VTBridge.events] 派发的 VtLite 事件：
/// - [RoomUpdateEvent]：刷新 [room] 的播放状态与成员数
/// - [TextMessageEvent]：把消息追加到 [messages]
/// - [WsOpenEvent] / [WsCloseEvent]：更新 [wsStatus]
/// - [ReconnectingEvent]：更新 [wsStatus] 为 reconnecting
/// - [ErrorEvent]：把用户可读错误信息暴露给 [lastError]
class RoomStore extends ChangeNotifier {
  VTBridge? _bridge;
  StreamSubscription<VTEvent>? _eventSub;

  RoomStoreState _state = RoomStoreState.idle;
  Room? _room;
  Object? _error;
  final List<ChatMessage> _messages = [];
  WsStatus _wsStatus = WsStatus.disconnected;
  String? _lastError;

  /// 可在构造时注入 bridge（测试用），或后续 [bindBridge] 绑定（生产用）
  RoomStore({VTBridge? bridge}) {
    if (bridge != null) bindBridge(bridge);
  }

  RoomStoreState get state => _state;
  Room? get room => _room;
  Object? get error => _error;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get wsConnected => _wsStatus == WsStatus.connected;
  WsStatus get wsStatus => _wsStatus;
  String? get lastError => _lastError;

  /// WatchPage 在 WebView 初始化后调用，绑定真实 bridge
  void bindBridge(VTBridge bridge) {
    _eventSub?.cancel();
    _bridge = bridge;
    _eventSub = bridge.events.listen(_handleEvent);
  }

  void clearError() {
    _error = null;
    _state = RoomStoreState.idle;
    _lastError = null;
    notifyListeners();
  }

  Future<void> createRoom({required String name, String password = ''}) async {
    if (_bridge == null) {
      throw StateError('bridge not bound');
    }
    _state = RoomStoreState.loading;
    _error = null;
    _lastError = null;
    _wsStatus = WsStatus.connecting;
    notifyListeners();
    try {
      _room = await _bridge!.createRoom(name: name, password: password);
      _state = RoomStoreState.inRoom;
    } catch (e) {
      _error = e;
      _state = RoomStoreState.error;
    }
    notifyListeners();
  }

  Future<void> joinRoom({required String name, String password = ''}) async {
    if (_bridge == null) {
      throw StateError('bridge not bound');
    }
    _state = RoomStoreState.loading;
    _error = null;
    _lastError = null;
    _wsStatus = WsStatus.connecting;
    notifyListeners();
    try {
      _room = await _bridge!.joinRoom(name: name, password: password);
      _state = RoomStoreState.inRoom;
    } catch (e) {
      _error = e;
      _state = RoomStoreState.error;
    }
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    if (_bridge != null) {
      try { await _bridge!.leaveRoom(); } catch (_) {}
    }
    _room = null;
    _messages.clear();
    _wsStatus = WsStatus.disconnected;
    _error = null;
    _lastError = null;
    _state = RoomStoreState.idle;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_room == null || _bridge == null) return;
    await _bridge!.pause();
  }

  Future<void> play() async {
    if (_room == null || _bridge == null) return;
    await _bridge!.play();
  }

  Future<void> seek(double seconds) async {
    if (_room == null || _bridge == null) return;
    await _bridge!.seek(seconds);
  }

  Future<void> sendMessage(String text) async {
    if (_room == null || text.trim().isEmpty || _bridge == null) return;
    await _bridge!.sendMessage(text);
  }

  void _handleEvent(VTEvent event) {
    switch (event) {
      case RoomUpdateEvent(:final room):
        // 合并而非替换：服务端有时不下发 memberCount（如 /room/update_member 响应），
        // 此时保留旧值，避免显示 0
        if (_room != null && _room!.name == room.name) {
          // 防御：join 等不完整更新（无有效时间戳）不覆盖播放状态，
          // 避免缺字段默认值把当前进度/暂停态重置为 0/暂停
          final hasValidTs = room.lastUpdateServerTime > 0;
          _room = _room!.copyWith(
            currentTime: hasValidTs ? room.currentTime : _room!.currentTime,
            duration: hasValidTs ? room.duration : _room!.duration,
            paused: hasValidTs ? room.paused : _room!.paused,
            playbackRate:
                hasValidTs ? room.playbackRate : _room!.playbackRate,
            lastUpdateServerTime: hasValidTs
                ? room.lastUpdateServerTime
                : _room!.lastUpdateServerTime,
            url: room.url.isEmpty ? _room!.url : room.url,
            memberCount: room.memberCountValue ?? _room!.memberCountValue,
          );
        } else {
          _room = room;
        }
        notifyListeners();
      case TextMessageEvent(:final message):
        _messages.add(message);
        notifyListeners();
      case WsOpenEvent():
        _wsStatus = WsStatus.connected;
        _lastError = null;
        notifyListeners();
      case WsCloseEvent():
        _wsStatus = WsStatus.disconnected;
        notifyListeners();
      case ReconnectingEvent():
        _wsStatus = WsStatus.reconnecting;
        notifyListeners();
      case ErrorEvent(:final userMessage, :final isPasswordError, :final isRoomNotFound):
        if (isPasswordError || isRoomNotFound) {
          _error = userMessage;
          _state = RoomStoreState.error;
        }
        _lastError = userMessage;
        notifyListeners();
      case UnknownEvent():
        break;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
