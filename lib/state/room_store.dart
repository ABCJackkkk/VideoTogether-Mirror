import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

/// 房间状态机的几个状态
enum RoomStoreState { idle, loading, inRoom, error }

/// 房间状态管理（ChangeNotifier）
///
/// 监听 [VTBridge.events] 派发的 VtLite 事件：
/// - [RoomUpdateEvent]：刷新 [room] 的播放状态与成员数
/// - [TextMessageEvent]：把消息追加到 [messages]
/// - [WsOpenEvent] / [WsCloseEvent]：更新 [wsConnected]
class RoomStore extends ChangeNotifier {
  final VTBridge _bridge;
  StreamSubscription<VTEvent>? _eventSub;

  RoomStoreState _state = RoomStoreState.idle;
  Room? _room;
  Object? _error;
  final List<ChatMessage> _messages = [];
  bool _wsConnected = false;

  RoomStore({required VTBridge bridge}) : _bridge = bridge {
    _eventSub = _bridge.events.listen(_handleEvent);
  }

  RoomStoreState get state => _state;
  Room? get room => _room;
  Object? get error => _error;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get wsConnected => _wsConnected;

  Future<void> createRoom({required String name, String password = ''}) async {
    _state = RoomStoreState.loading;
    _error = null;
    notifyListeners();
    try {
      _room = await _bridge.createRoom(name: name, password: password);
      _state = RoomStoreState.inRoom;
    } catch (e) {
      _error = e;
      _state = RoomStoreState.error;
    }
    notifyListeners();
  }

  Future<void> joinRoom({required String name, String password = ''}) async {
    _state = RoomStoreState.loading;
    _error = null;
    notifyListeners();
    try {
      _room = await _bridge.joinRoom(name: name, password: password);
      _state = RoomStoreState.inRoom;
    } catch (e) {
      _error = e;
      _state = RoomStoreState.error;
    }
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    await _bridge.leaveRoom();
    _room = null;
    _messages.clear();
    _wsConnected = false;
    _state = RoomStoreState.idle;
    notifyListeners();
  }

  /// VtLite 自动监听 video 元素并上报，调用此方法为空操作（保留接口一致性）
  Future<void> pause() async {
    if (_room == null) return;
    await _bridge.pause();
  }

  /// VtLite 自动监听 video 元素并上报，调用此方法为空操作（保留接口一致性）
  Future<void> play() async {
    if (_room == null) return;
    await _bridge.play();
  }

  /// VtLite 自动监听 video 元素并上报，调用此方法为空操作（保留接口一致性）
  Future<void> seek(double seconds) async {
    if (_room == null) return;
    await _bridge.seek(seconds);
  }

  Future<void> sendMessage(String text) async {
    if (_room == null || text.trim().isEmpty) return;
    await _bridge.sendMessage(text);
  }

  void _handleEvent(VTEvent event) {
    switch (event) {
      case RoomUpdateEvent(:final room):
        // 用事件中的 Room 覆盖本地状态；若 name 一致则保留本地 id
        _room = room.name == _room?.name
            ? room.copyWith(id: _room!.id)
            : room;
        notifyListeners();
      case TextMessageEvent(:final message):
        _messages.add(message);
        notifyListeners();
      case WsOpenEvent():
        _wsConnected = true;
        notifyListeners();
      case WsCloseEvent():
        _wsConnected = false;
        notifyListeners();
      case ErrorEvent():
        // 错误事件目前不改变 store 状态，仅由 UI 层自行监听 events 流处理
        break;
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
