import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  group('VTEvent.fromJson (VtLite {event, data} 格式)', () {
    test('解析 room_update 事件', () {
      final event = VTEvent.fromJson({
        'event': 'room_update',
        'data': {
          'name': 'abc',
          'currentTime': 120.5,
          'duration': 3600,
          'paused': true,
          'playbackRate': 1.0,
          'lastUpdateServerTime': 1785095000.0,
          'memberCount': 2,
          'url': 'https://example.com/v',
        },
      });
      expect(event, isA<RoomUpdateEvent>());
      final r = (event as RoomUpdateEvent).room;
      expect(r.name, 'abc');
      expect(r.currentTime, 120.5);
      expect(r.paused, isTrue);
      expect(r.memberCount, 2);
    });

    test('解析 text_message 事件', () {
      final event = VTEvent.fromJson({
        'event': 'text_message',
        'data': {
          'msg': 'hello',
          'id': 'msg-1',
          'voiceId': 'v1',
        },
      });
      expect(event, isA<TextMessageEvent>());
      final m = (event as TextMessageEvent).message;
      expect(m.id, 'msg-1');
      expect(m.text, 'hello');
      expect(m.voiceId, 'v1');
    });

    test('解析 ws_open 事件', () {
      final event = VTEvent.fromJson({
        'event': 'ws_open',
        'data': {},
      });
      expect(event, isA<WsOpenEvent>());
    });

    test('解析 ws_close 事件', () {
      final event = VTEvent.fromJson({
        'event': 'ws_close',
        'data': {'wasOpen': true},
      });
      expect(event, isA<WsCloseEvent>());
      expect((event as WsCloseEvent).wasOpen, isTrue);
    });

    test('解析 error 事件', () {
      final event = VTEvent.fromJson({
        'event': 'error',
        'data': {'message': 'ws_not_open'},
      });
      expect(event, isA<ErrorEvent>());
      expect((event as ErrorEvent).message, 'ws_not_open');
    });

    test('未知事件类型解析为 UnknownEvent', () {
      final event = VTEvent.fromJson({
        'event': 'whatever',
        'data': {'foo': 1},
      });
      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).name, 'whatever');
    });

    test('缺少 event 字段时解析为 UnknownEvent', () {
      final event = VTEvent.fromJson({'data': {'foo': 1}});
      expect(event, isA<UnknownEvent>());
    });

    test('data 为空对象时 room_update 仍能构造（用默认值）', () {
      final event = VTEvent.fromJson({
        'event': 'room_update',
        'data': {},
      });
      expect(event, isA<RoomUpdateEvent>());
      final r = (event as RoomUpdateEvent).room;
      expect(r.currentTime, 0);
      expect(r.paused, isTrue);
    });
  });

  group('VTEvent 类型字段', () {
    test('RoomUpdateEvent 暴露 room 字段', () {
      final event = VTEvent.fromJson({
        'event': 'room_update',
        'data': {'name': 'x', 'paused': false},
      }) as RoomUpdateEvent;
      expect(event.room, isA<Room>());
      expect(event.name, 'room_update');
    });

    test('TextMessageEvent 暴露 message 字段', () {
      final event = VTEvent.fromJson({
        'event': 'text_message',
        'data': {'msg': 'hi', 'id': 'm1'},
      }) as TextMessageEvent;
      expect(event.message, isA<ChatMessage>());
      expect(event.name, 'text_message');
    });

    test('WsCloseEvent.wasOpen 默认 false', () {
      final event = VTEvent.fromJson({
        'event': 'ws_close',
        'data': {},
      }) as WsCloseEvent;
      expect(event.wasOpen, isFalse);
    });

    test('ErrorEvent.message 缺省时为空字符串', () {
      final event = VTEvent.fromJson({
        'event': 'error',
        'data': {},
      }) as ErrorEvent;
      expect(event.message, '');
    });
  });
}
