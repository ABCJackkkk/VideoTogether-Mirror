import 'package:videotogether/vt/vt_models.dart';

/// VT 事件基类
///
/// VtLite 通过 `window.flutter_inappwebview.callHandler('vtEvent', {event, data})`
/// 把事件转发到 Dart 侧。Dart 侧收到的 JSON 形状为：
/// `{event: "room_update"|"text_message"|"ws_open"|"ws_close"|"error", data: {...}}`
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
      case 'error':
        return ErrorEvent(
          message: (data['message'] as String?) ?? '',
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

/// 错误事件（对应 VtLite 的 error）
class ErrorEvent extends VTEvent {
  final String message;
  const ErrorEvent({this.message = ''});

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
