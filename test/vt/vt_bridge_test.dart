import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  group('FakeVTBridge.createRoom', () {
    test('返回房间对象，name 来自参数', () async {
      final bridge = FakeVTBridge();
      final room = await bridge.createRoom(name: 'test');
      expect(room.id, isNotEmpty);
      expect(room.name, 'test');
    });

    test('支持 password 参数（不报错）', () async {
      final bridge = FakeVTBridge();
      final room = await bridge.createRoom(name: 'test', password: 'pwd');
      expect(room.name, 'test');
    });
  });

  group('FakeVTBridge.joinRoom', () {
    test('房间不存在抛 RoomNotFoundException', () async {
      final bridge = FakeVTBridge();
      expect(
        () => bridge.joinRoom(name: 'no-such'),
        throwsA(isA<RoomNotFoundException>()),
      );
    });

    test('先 createRoom 再 joinRoom 同名可成功', () async {
      final bridge = FakeVTBridge();
      await bridge.createRoom(name: 'room1');
      final room = await bridge.joinRoom(name: 'room1');
      expect(room.name, 'room1');
    });
  });

  group('FakeVTBridge.sendMessage', () {
    test('发送后事件流收到 TextMessageEvent', () async {
      final bridge = FakeVTBridge();
      final room = await bridge.createRoom(name: 'test');
      final me = const Member(id: 'u1', name: 'me');
      bridge.bindMember(room.id, me);

      final events = <VTEvent>[];
      bridge.events.listen(events.add);

      await bridge.sendMessage('hello');
      // broadcast StreamController 同步派发
      await Future.delayed(Duration.zero);
      expect(events, anyElement(isA<TextMessageEvent>()));
      final msgEvent =
          events.firstWhere((e) => e is TextMessageEvent) as TextMessageEvent;
      expect(msgEvent.message.text, 'hello');
      expect(msgEvent.message.from, me);
    });

    test('未绑定成员时 sendMessage 静默忽略', () async {
      final bridge = FakeVTBridge();
      await bridge.createRoom(name: 'test');

      final events = <VTEvent>[];
      bridge.events.listen(events.add);

      await bridge.sendMessage('hello');
      await Future.delayed(Duration.zero);
      expect(events.whereType<TextMessageEvent>(), isEmpty);
    });
  });

  group('FakeVTBridge.leaveRoom', () {
    test('不抛异常', () async {
      final bridge = FakeVTBridge();
      await bridge.createRoom(name: 'test');
      await bridge.leaveRoom(); // 不应抛
    });
  });

  group('FakeVTBridge.pause/play/seek', () {
    test('VtLite 自动处理，Fake 中为空操作', () async {
      final bridge = FakeVTBridge();
      final room = await bridge.createRoom(name: 'test');
      final events = <VTEvent>[];
      bridge.events.listen(events.add);

      // 全部不抛异常、不发事件
      await bridge.pause();
      await bridge.play();
      await bridge.seek(60.0);
      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
      // 引用 room 避免 unused warning
      expect(room.name, 'test');
    });
  });

  group('FakeVTBridge.emit (测试辅助)', () {
    test('外部注入 WsOpenEvent 能被监听者收到', () async {
      final bridge = FakeVTBridge();
      final events = <VTEvent>[];
      bridge.events.listen(events.add);

      bridge.emit(const WsOpenEvent());
      await Future.delayed(Duration.zero);
      expect(events, anyElement(isA<WsOpenEvent>()));
    });

    test('外部注入 WsCloseEvent 能被监听者收到', () async {
      final bridge = FakeVTBridge();
      final events = <VTEvent>[];
      bridge.events.listen(events.add);

      bridge.emit(const WsCloseEvent(wasOpen: true));
      await Future.delayed(Duration.zero);
      expect(events, anyElement(isA<WsCloseEvent>()));
    });
  });

  group('RoomNotFoundException', () {
    test('toString 包含房间名', () {
      final e = RoomNotFoundException('no-such');
      expect(e.toString(), contains('no-such'));
    });
  });
}
