import 'package:videotogether/vt/vt_models.dart';

/// VT 事件基类
///
/// VtLite 通过 `window.flutter_inappwebview.callHandler('vtEvent', {event, data})`
/// 把事件转发到 Dart 侧。Dart 侧收到的 JSON 形状为：
/// `{event: "room_update"|"text_message"|"ws_open"|"ws_close"|"error"|"reconnecting", data: {...}}`
sealed class VTEvent {
  /// 事件名（与 VtLite 的 event 字段一致）
  String get name;

  const VTEvent();

  /// 从 VtLite 转发的 JSON 解析事件
  factory VTEvent.fromJson(Map<String, dynamic> json) {
    final event = (json['event'] as String?) ?? '';
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (event) {
      case 'room_update':
        return RoomUpdateEvent(room: Room.fromVtLite(data));
      case 'text_message':
        return TextMessageEvent(message: ChatMessage.fromVtLite(data));
      case 'ws_open':
        return const WsOpenEvent();
      case 'ws_close':
        return WsCloseEvent(
          wasOpen: (data['wasOpen'] as bool?) ?? false,
        );
      case 'reconnecting':
        return ReconnectingEvent(
          attempt: (data['attempt'] as num?)?.toInt() ?? 0,
          delayMs: (data['delayMs'] as num?)?.toInt() ?? 0,
        );
      case 'error':
        return ErrorEvent(
          message: (data['message'] as String?) ?? '',
          detail: (data['error'] as String?) ?? '',
        );
      default:
        return UnknownEvent(name: event, raw: json);
    }
  }
}

/// 房间状态更新事件（对应 VtLite 的 room_update）
class RoomUpdateEvent extends VTEvent {
  final Room room;
  const RoomUpdateEvent({required this.room});

  @override
  String get name => 'room_update';
}

/// 文字消息事件（对应 VtLite 的 text_message）
class TextMessageEvent extends VTEvent {
  final ChatMessage message;
  const TextMessageEvent({required this.message});

  @override
  String get name => 'text_message';
}

/// WebSocket 连接已建立（对应 VtLite 的 ws_open）
class WsOpenEvent extends VTEvent {
  const WsOpenEvent();

  @override
  String get name => 'ws_open';
}

/// WebSocket 连接已断开（对应 VtLite 的 ws_close）
class WsCloseEvent extends VTEvent {
  /// 断开前 WS 是否曾经成功 open 过
  final bool wasOpen;
  const WsCloseEvent({this.wasOpen = false});

  @override
  String get name => 'ws_close';
}

/// 正在尝试重连（对应 VtLite 的 reconnecting）
class ReconnectingEvent extends VTEvent {
  /// 第几次尝试（从 1 开始）
  final int attempt;
  /// 本次重连等待毫秒数
  final int delayMs;
  const ReconnectingEvent({required this.attempt, required this.delayMs});

  @override
  String get name => 'reconnecting';
}

/// 错误事件（对应 VtLite 的 error）
class ErrorEvent extends VTEvent {
  /// 错误类型标识：password_error / room_not_found / server_error /
  /// sync_time_failed / ws_* / member_sync_error 等
  final String message;
  /// 详细错误信息（来自服务端或异常字符串）
  final String detail;

  const ErrorEvent({this.message = '', this.detail = ''});

  /// 是否是密码错误
  bool get isPasswordError => message == 'password_error';

  /// 是否是房间不存在
  bool get isRoomNotFound => message == 'room_not_found';

  /// 用户可读的错误描述
  String get userMessage {
    switch (message) {
      case 'password_error':
        return '房间密码错误';
      case 'room_not_found':
        return '房间不存在，请检查房间名';
      case 'server_error':
        return '服务器错误：$detail';
      case 'ws_all_urls_failed':
        return '无法连接同步服务器，请检查网络';
      case 'ws_construct_failed':
        return 'WebSocket 创建失败：$detail';
      case 'ws_message_handler_error':
        return '消息处理异常：$detail';
      case 'ws_not_open':
        return '连接未建立，请稍候';
      case 'sync_time_failed':
        return '时间同步失败，进度可能有偏差';
      case 'member_sync_error':
        return '同步播放状态失败';
      default:
        return detail.isNotEmpty ? detail : '未知错误';
    }
  }

  @override
  String get name => 'error';
}

/// 未知事件类型
class UnknownEvent extends VTEvent {
  @override
  final String name;
  final Map<String, dynamic> raw;
  const UnknownEvent({required this.name, required this.raw});
}
