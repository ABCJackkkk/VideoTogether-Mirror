import 'dart:async';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

/// VT 集成层抽象接口
///
/// 真实实现见 [VTWebViewBridge]：通过 WebView 调用 VtLite JS。
/// 测试与 UI 开发用 [FakeVTBridge]。
///
/// VtLite 的播放控制（pause/play/seek）由 JS 自动监听 video 元素并 2 秒上报，
/// **Dart 侧无需手动调**——接口里保留这三个方法仅为兼容性，真实实现为空操作。
abstract class VTBridge {
  /// 创建房间，返回房间对象
  ///
  /// [password] 可空字符串；VtLite 用它决定房间是否受保护。
  Future<Room> createRoom({required String name, String password = ''});

  /// 加入房间，房间不存在抛 [RoomNotFoundException]
  Future<Room> joinRoom({required String name, String password = ''});

  /// 离开当前房间
  Future<void> leaveRoom();

  /// VtLite 自动监听 video 元素，无需手动调（保留接口兼容性）
  Future<void> pause();

  /// VtLite 自动监听 video 元素，无需手动调（保留接口兼容性）
  Future<void> play();

  /// VtLite 自动监听 video 元素，无需手动调（保留接口兼容性）
  Future<void> seek(double seconds);

  /// 发送文字消息
  Future<void> sendMessage(String text);

  /// 事件流（房间状态更新、文字消息、WS 连接状态、错误）
  ///
  /// 事件类型见 [VTEvent] 及其子类。
  Stream<VTEvent> get events;

  void dispose();
}

class RoomNotFoundException implements Exception {
  final String name;
  RoomNotFoundException(this.name);
  @override
  String toString() => '房间不存在: $name';
}

/// 用于测试和 UI 开发的假实现，不依赖 WebView
class FakeVTBridge implements VTBridge {
  final Map<String, Room> _rooms = {};
  final Map<String, Member> _membersInRoom = {};
  final StreamController<VTEvent> _events = StreamController<VTEvent>.broadcast();

  @override
  Stream<VTEvent> get events => _events.stream;

  @override
  Future<Room> createRoom({required String name, String password = ''}) async {
    final id = 'room-${DateTime.now().microsecondsSinceEpoch}';
    final room = Room(
      id: id,
      name: name,
      members: const [],
      memberCount: 1,
    );
    _rooms[name] = room;
    return room;
  }

  @override
  Future<Room> joinRoom({required String name, String password = ''}) async {
    final room = _rooms[name];
    if (room == null) {
      throw RoomNotFoundException(name);
    }
    return room;
  }

  @override
  Future<void> leaveRoom() async {
    // 模拟 VtLite 的 leaveRoom：清空绑定
  }

  @override
  Future<void> pause() async {
    // VtLite 自动处理，Fake 中空操作
  }

  @override
  Future<void> play() async {
    // VtLite 自动处理，Fake 中空操作
  }

  @override
  Future<void> seek(double seconds) async {
    // VtLite 自动处理，Fake 中空操作
  }

  @override
  Future<void> sendMessage(String text) async {
    // 找到当前用户绑定的房间
    String? currentRoomId;
    for (final entry in _membersInRoom.entries) {
      currentRoomId = entry.key;
      break;
    }
    if (currentRoomId == null) return;
    final me = _membersInRoom[currentRoomId];
    if (me == null) return;
    _events.add(TextMessageEvent(
      message: ChatMessage(
        id: 'm-${DateTime.now().microsecondsSinceEpoch}',
        from: me,
        text: text,
        sentAt: DateTime.now(),
      ),
    ));
  }

  /// 测试辅助：把当前用户绑定到房间
  void bindMember(String roomId, Member member) {
    _membersInRoom[roomId] = member;
  }

  /// 测试辅助：直接派发事件到事件流
  void emit(VTEvent event) {
    _events.add(event);
  }

  @override
  void dispose() {
    _events.close();
  }
}
