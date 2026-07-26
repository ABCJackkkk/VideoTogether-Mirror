import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  group('Room', () {
    test('基本构造与字段', () {
      final room = Room(
        id: 'abc123',
        name: '周五电影夜',
        members: const [],
      );
      expect(room.id, 'abc123');
      expect(room.name, '周五电影夜');
      expect(room.members, isEmpty);
      expect(room.currentTime, 0);
      expect(room.duration, 0);
      expect(room.paused, isTrue);
      expect(room.playbackRate, 1.0);
      expect(room.lastUpdateServerTime, 0);
    });

    test('memberCount 由 members 推导', () {
      final room = Room(
        id: 'abc123',
        name: 'test',
        members: [
          const Member(id: 'u1', name: 'A'),
          const Member(id: 'u2', name: 'B'),
        ],
      );
      expect(room.memberCount, 2);
    });

    test('从 VtLite room_update 数据构造 Room', () {
      final room = Room.fromVtLite({
        'name': 'abc',
        'currentTime': 120.5,
        'duration': 3600,
        'paused': false,
        'playbackRate': 1.5,
        'lastUpdateServerTime': 1785095000.0,
        'memberCount': 3,
        'url': 'https://example.com/v',
      });
      expect(room.name, 'abc');
      // VtLite 不直接给 id，使用 name 作为 id
      expect(room.id, 'abc');
      expect(room.currentTime, 120.5);
      expect(room.duration, 3600);
      expect(room.paused, isFalse);
      expect(room.playbackRate, 1.5);
      expect(room.lastUpdateServerTime, 1785095000.0);
      // members 列表为空，memberCount 字段独立保留
      expect(room.members, isEmpty);
      expect(room.memberCount, 3);
    });

    test('copyWith 拷贝并修改字段', () {
      final room = Room(id: 'a', name: 'n', members: const []);
      final updated = room.copyWith(
        name: 'n2',
        currentTime: 10,
        paused: false,
      );
      expect(updated.id, 'a');
      expect(updated.name, 'n2');
      expect(updated.currentTime, 10);
      expect(updated.paused, isFalse);
    });
  });

  group('Member', () {
    test('构造与相等性', () {
      const m1 = Member(id: 'u1', name: 'A');
      const m2 = Member(id: 'u1', name: 'A2');
      expect(m1, m2); // 按 id 判等
      expect(m1.hashCode, m2.hashCode);
    });

    test('toString 包含 id 和 name', () {
      const m = Member(id: 'u1', name: 'A');
      expect(m.toString(), contains('u1'));
      expect(m.toString(), contains('A'));
    });
  });

  group('ChatMessage', () {
    test('基本构造与字段', () {
      final msg = ChatMessage(
        id: 'm1',
        from: const Member(id: 'u1', name: 'A'),
        text: 'hi',
        sentAt: DateTime(2026, 7, 27, 20, 0),
      );
      expect(msg.id, 'm1');
      expect(msg.text, 'hi');
      expect(msg.from.name, 'A');
      expect(msg.voiceId, isNull);
      expect(msg.audioUrl, isNull);
    });

    test('从 VtLite text_message 数据构造 ChatMessage', () {
      final before = DateTime.now();
      final msg = ChatMessage.fromVtLite({
        'msg': 'hello',
        'id': 'msg-1',
        'voiceId': 'v1',
        'audioUrl': 'https://example.com/a.mp3',
      });
      final after = DateTime.now();
      expect(msg.id, 'msg-1');
      expect(msg.text, 'hello');
      expect(msg.voiceId, 'v1');
      expect(msg.audioUrl, 'https://example.com/a.mp3');
      expect(msg.from.id, 'v1'); // voiceId 作为发送者标识
      // sentAt 在 [before, after] 区间内（避免毫秒精度边界）
      expect(msg.sentAt.isAfter(before.subtract(const Duration(milliseconds: 1))), isTrue);
      expect(msg.sentAt.isBefore(after.add(const Duration(milliseconds: 1))), isTrue);
    });

    test('从 VtLite 数据构造时缺少 voiceId/audioUrl 不报错', () {
      final msg = ChatMessage.fromVtLite({
        'msg': 'hi',
        'id': 'm2',
      });
      expect(msg.text, 'hi');
      expect(msg.voiceId, isNull);
      expect(msg.audioUrl, isNull);
    });
  });

  group('SyncState', () {
    test('paused 状态', () {
      const state = SyncState.paused(currentTime: 120.5);
      expect(state.isPlaying, isFalse);
      expect(state.currentTime, 120.5);
    });

    test('playing 状态', () {
      const state = SyncState.playing(currentTime: 120.5);
      expect(state.isPlaying, isTrue);
      expect(state.currentTime, 120.5);
    });
  });
}
