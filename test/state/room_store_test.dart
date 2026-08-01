import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  test('createRoom 后 store 处于 inRoom 状态', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    expect(store.state, RoomStoreState.inRoom);
    expect(store.room?.name, 'test');
    expect(store.wsConnected, isFalse); // 未收到 ws_open 事件
  });

  test('joinRoom 不存在房间后 store 处于 error 状态', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.joinRoom(name: 'no-such');
    expect(store.state, RoomStoreState.error);
    expect(store.error, isA<RoomNotFoundException>());
  });

  test('收到 TextMessageEvent 后消息列表增加', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    final me = const Member(id: 'u1', name: 'me');
    bridge.bindMember(store.room!.id, me);

    final before = store.messages.length;
    await store.sendMessage('hello');
    // Fake bridge 同步发出事件，store 监听后应刷新
    await Future.delayed(Duration.zero);
    expect(store.messages.length, before + 1);
    expect(store.messages.last.text, 'hello');
  });

  test('leaveRoom 后 store 回到 idle', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    await store.leaveRoom();
    expect(store.state, RoomStoreState.idle);
    expect(store.room, isNull);
    expect(store.messages, isEmpty);
  });

  test('收到 WsOpenEvent 后 wsConnected=true', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    expect(store.wsConnected, isFalse);

    bridge.emit(const WsOpenEvent());
    await Future.delayed(Duration.zero);
    expect(store.wsConnected, isTrue);
  });

  test('收到 WsCloseEvent 后 wsConnected=false', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    bridge.emit(const WsOpenEvent());
    await Future.delayed(Duration.zero);
    expect(store.wsConnected, isTrue);

    bridge.emit(const WsCloseEvent());
    await Future.delayed(Duration.zero);
    expect(store.wsConnected, isFalse);
  });

  test('收到 RoomUpdateEvent 后 room 状态更新', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');

    bridge.emit(const RoomUpdateEvent(room: Room(
      id: 'test',
      name: 'test',
      members: [],
      currentTime: 120.5,
      duration: 3600,
      paused: false,
      playbackRate: 1.5,
      lastUpdateServerTime: 1785095000.0,
      memberCount: 3,
    )));
    await Future.delayed(Duration.zero);

    expect(store.room, isNotNull);
    expect(store.room!.currentTime, 120.5);
    expect(store.room!.paused, isFalse);
    expect(store.room!.playbackRate, 1.5);
    expect(store.room!.memberCount, 3);
  });

  test('收到 RoomUpdateEvent 后仍保留在 inRoom 状态', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');

    bridge.emit(const RoomUpdateEvent(
      room: Room(id: 'test', name: 'test', members: [], memberCount: 2),
    ));
    await Future.delayed(Duration.zero);

    expect(store.state, RoomStoreState.inRoom);
  });

  test('无有效时间戳的 room_update 不覆盖播放状态（join 响应防御）', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');

    // 先收到真实房主状态
    bridge.emit(const RoomUpdateEvent(room: Room(
      id: 'test',
      name: 'test',
      members: [],
      currentTime: 300.0,
      duration: 600,
      paused: false,
      playbackRate: 1.0,
      lastUpdateServerTime: 1785095000.0,
      memberCount: 3,
    )));
    await Future.delayed(Duration.zero);
    expect(store.room!.currentTime, 300.0);
    expect(store.room!.paused, isFalse);

    // join 成功响应：无 lastUpdateServerTime，currentTime 默认 0、paused 默认 true
    bridge.emit(const RoomUpdateEvent(room: Room(
      id: 'test',
      name: 'test',
      members: [],
      memberCount: 4,
    )));
    await Future.delayed(Duration.zero);

    // 播放状态必须保留，只更新成员数
    expect(store.room!.currentTime, 300.0);
    expect(store.room!.paused, isFalse);
    expect(store.room!.memberCount, 4);
  });

  test('leaveRoom 后 error 与 lastError 被清空', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');

    bridge.emit(const ErrorEvent(message: 'room_not_found'));
    await Future.delayed(Duration.zero);
    expect(store.state, RoomStoreState.error);

    await store.leaveRoom();
    expect(store.state, RoomStoreState.idle);
    expect(store.error, isNull);
    expect(store.lastError, isNull);
  });

  test('sendMessage 空文本不发送', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    final me = const Member(id: 'u1', name: 'me');
    bridge.bindMember(store.room!.id, me);

    await store.sendMessage('   ');
    await Future.delayed(Duration.zero);
    expect(store.messages, isEmpty);
  });

  test('leaveRoom 时 wsConnected 重置为 false', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    bridge.emit(const WsOpenEvent());
    await Future.delayed(Duration.zero);
    expect(store.wsConnected, isTrue);

    await store.leaveRoom();
    expect(store.wsConnected, isFalse);
  });

  test('dispose 后不再处理事件', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    store.dispose();

    // 不应抛异常
    bridge.emit(const WsOpenEvent());
    await Future.delayed(Duration.zero);
  });
}
