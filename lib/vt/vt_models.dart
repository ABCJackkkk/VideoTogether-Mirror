/// VT 数据模型
library;

/// 房间成员
class Member {
  final String id;
  final String name;

  const Member({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Member && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Member($id, $name)';
}

/// 房间
///
/// 同时承载 Dart 侧管理用的 [members] 列表与 VtLite 协议下上报的播放状态字段
/// （[currentTime]/[duration]/[paused]/[playbackRate]/[lastUpdateServerTime]）。
/// VtLite 协议中房间的成员数通过 [memberCount] 字段直接下发，与 [members] 列表
/// 解耦：当从 room_update 事件构造时 [members] 为空，[memberCount] 为真实值；
/// 当 Dart 侧自行维护时 [memberCount] 由 [members] 推导。
class Room {
  final String id;
  final String name;
  final List<Member> members;

  /// 视频当前播放时间（秒）
  final double currentTime;

  /// 视频总时长（秒）
  final double duration;

  /// 是否暂停
  final bool paused;

  /// 播放倍速
  final double playbackRate;

  /// 服务端最近一次收到房主上报的时间戳（秒）
  final double lastUpdateServerTime;

  /// 协议下发的成员数；若为 null 则由 [members] 推导
  final int? _memberCount;

  const Room({
    required this.id,
    required this.name,
    required this.members,
    this.currentTime = 0,
    this.duration = 0,
    this.paused = true,
    this.playbackRate = 1.0,
    this.lastUpdateServerTime = 0,
    int? memberCount,
  }) : _memberCount = memberCount;

  int get memberCount => _memberCount ?? members.length;

  /// 从 VtLite room_update 事件的 data 构造 Room
  factory Room.fromVtLite(Map<String, dynamic> data) {
    final name = (data['name'] as String?) ?? '';
    return Room(
      id: name, // VtLite 协议不直接给 id，房间名即唯一标识
      name: name,
      members: const [],
      currentTime: (data['currentTime'] as num?)?.toDouble() ?? 0,
      duration: (data['duration'] as num?)?.toDouble() ?? 0,
      paused: (data['paused'] as bool?) ?? true,
      playbackRate: (data['playbackRate'] as num?)?.toDouble() ?? 1.0,
      lastUpdateServerTime:
          (data['lastUpdateServerTime'] as num?)?.toDouble() ?? 0,
      memberCount: (data['memberCount'] as num?)?.toInt(),
    );
  }

  Room copyWith({
    String? id,
    String? name,
    List<Member>? members,
    double? currentTime,
    double? duration,
    bool? paused,
    double? playbackRate,
    double? lastUpdateServerTime,
    int? memberCount,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      members: members ?? this.members,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      paused: paused ?? this.paused,
      playbackRate: playbackRate ?? this.playbackRate,
      lastUpdateServerTime:
          lastUpdateServerTime ?? this.lastUpdateServerTime,
      memberCount: memberCount ?? _memberCount,
    );
  }

  @override
  String toString() =>
      'Room(id=$id, name=$name, memberCount=$memberCount, currentTime=$currentTime, paused=$paused)';
}

/// 聊天消息
class ChatMessage {
  final String id;
  final Member from;
  final String text;
  final DateTime sentAt;

  /// VtLite 文字消息协议字段：语音合成用的 voiceId（可作为发送者标识）
  final String? voiceId;

  /// VtLite 文字消息协议字段：可选的 TTS 音频 URL
  final String? audioUrl;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.sentAt,
    this.voiceId,
    this.audioUrl,
  });

  /// 从 VtLite text_message 事件的 data 构造 ChatMessage
  ///
  /// VtLite 协议字段：{msg, id, voiceId, audioUrl?}，不含发送者昵称与时间戳。
  /// 这里用 voiceId 作为发送者 id 与 name，sentAt 取本地当前时间。
  factory ChatMessage.fromVtLite(Map<String, dynamic> data) {
    final voiceId = data['voiceId'] as String?;
    final fromId = voiceId ?? (data['id'] as String?) ?? '';
    return ChatMessage(
      id: (data['id'] as String?) ?? '',
      from: Member(id: fromId, name: fromId),
      text: (data['msg'] as String?) ?? '',
      sentAt: DateTime.now(),
      voiceId: voiceId,
      audioUrl: data['audioUrl'] as String?,
    );
  }

  @override
  String toString() => 'ChatMessage(id=$id, from=$from, text=$text)';
}

/// 视频同步状态
sealed class SyncState {
  final double currentTime;
  const SyncState({required this.currentTime});

  bool get isPlaying;

  const factory SyncState.paused({required double currentTime}) =
      PausedSyncState;
  const factory SyncState.playing({required double currentTime}) =
      PlayingSyncState;
}

class PausedSyncState extends SyncState {
  const PausedSyncState({required super.currentTime});
  @override
  bool get isPlaying => false;
}

class PlayingSyncState extends SyncState {
  const PlayingSyncState({required super.currentTime});
  @override
  bool get isPlaying => true;
}
