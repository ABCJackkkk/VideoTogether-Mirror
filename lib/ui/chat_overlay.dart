import 'package:flutter/material.dart';
import 'package:videotogether/vt/vt_models.dart';

/// 聊天浮层：VT 风格可收起/展开。
///
/// 视觉遵循 Aui 规范：
/// - 收起态：右下角圆形 56px 浮动按钮，暖棕色 #8B7355，白色聊天图标
/// - 展开态：右侧 70% 宽 × 50% 高的卡片，圆角 16px，背景 #F7F5F2，边框 #E0DCD6
/// - 标题栏（"聊天" + 关闭按钮）→ 消息列表 → 输入栏（4px 圆角输入框 + 发送按钮）
///
/// 必须放在 [Stack] 内使用（内部用 [Positioned] 定位）。
class ChatOverlay extends StatefulWidget {
  final List<ChatMessage> messages;
  final ValueChanged<String> onSend;

  const ChatOverlay({
    super.key,
    required this.messages,
    required this.onSend,
  });

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  bool _expanded = false;
  final _inputCtrl = TextEditingController();

  // Aui 色板
  static const Color _kBgPaper = Color(0xFFF7F5F2);
  static const Color _kTextPrimary = Color(0xFF2C2C2C);
  static const Color _kTextSecondary = Color(0xFF6B6B6B);
  static const Color _kAccent = Color(0xFF8B7355);
  static const Color _kBorder = Color(0xFFE0DCD6);

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _expand() => setState(() => _expanded = true);

  void _collapse() => setState(() => _expanded = false);

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _inputCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          heroTag: 'chat-toggle',
          backgroundColor: _kAccent,
          elevation: 2,
          onPressed: _expand,
          child: const Icon(Icons.chat, color: _kBgPaper),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    return Positioned(
      right: 0,
      bottom: 0,
      width: size.width * 0.7,
      height: size.height * 0.5,
      child: Card(
        margin: const EdgeInsets.all(8),
        color: _kBgPaper,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _kBorder, width: 1),
        ),
        child: Column(
          children: [
            // 标题栏
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    '聊天',
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 14,
                      letterSpacing: 0.15,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextSecondary),
                  tooltip: '关闭',
                  onPressed: _collapse,
                ),
              ],
            ),
            const Divider(height: 1, color: _kBorder),
            // 消息列表
            Expanded(
              child: widget.messages.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无消息',
                        style: TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 12,
                          letterSpacing: 0.02,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: widget.messages.length,
                      itemBuilder: (ctx, i) {
                        final m = widget.messages[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            m.text,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 14,
                              letterSpacing: 0.02,
                              height: 1.6,
                            ),
                          ),
                          subtitle: Text(
                            m.from.name,
                            style: const TextStyle(
                              color: _kTextSecondary,
                              fontSize: 11,
                              letterSpacing: 0.02,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: _kBorder),
            // 输入栏
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 14,
                        letterSpacing: 0.02,
                        height: 1.6,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '发消息...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 14,
                          letterSpacing: 0.02,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: _kBgPaper,
                        enabledBorder: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(4)),
                          borderSide: BorderSide(color: _kBorder),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(4)),
                          borderSide: BorderSide(color: _kAccent),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: _kAccent),
                    tooltip: '发送',
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
