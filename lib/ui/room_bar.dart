import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:videotogether/vt/vt_models.dart';

/// 观影页顶栏：显示房间名、成员数、复制房间名、离开按钮。
///
/// 视觉遵循 Aui 规范：
/// - 暖背景 #F0ECE6，padding 12×8
/// - 房间名 14px #2C2C2C 单行省略
/// - 成员数 12px #6B6B6B
/// - 图标按钮颜色 #6B6B6B
///
/// VtLite 协议下房间名即房间唯一标识（无单独房间号），复制的是 [Room.name]。
class RoomBar extends StatelessWidget {
  final Room room;
  final VoidCallback onLeave;

  const RoomBar({super.key, required this.room, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFFF0ECE6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                    color: Color(0xFF2C2C2C),
                    fontSize: 14,
                    letterSpacing: 0.02,
                    height: 1.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '成员 ${room.memberCount}',
                  style: const TextStyle(
                    color: Color(0xFF6B6B6B),
                    fontSize: 12,
                    letterSpacing: 0.02,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Color(0xFF6B6B6B)),
            tooltip: '复制房间号',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: room.name));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('房间号已复制')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF6B6B6B)),
            tooltip: '离开房间',
            onPressed: onLeave,
          ),
        ],
      ),
    );
  }
}
