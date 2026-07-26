import 'package:flutter/material.dart';

/// 首页：粘贴视频网址 + 输入昵称 + 选择创建或加入房间。
///
/// 视觉遵循 Aui（Ins 风简约、暖沙色调）规范：
/// - 主背景 #F7F5F2、顶栏暖背景 #F0ECE6
/// - 输入框 4px 圆角，边框 #E0DCD6，focus 边框 #8B7355
/// - 主按钮 4px 圆角，背景 #2C2C2C，文字 #F7F5F2，letterSpacing 0.15em
/// - 入场为交错淡入（fadeUp，1.2s，间隔 0.3s）
class HomePage extends StatefulWidget {
  /// 点击创建/加入房间时触发。
  ///
  /// - [url]：视频网页地址
  /// - [create]：true=创建房间，false=加入房间
  /// - [roomId]：加入时由用户填入的房间名（VtLite 协议下房间名即唯一标识）；
  ///   创建时为 null
  /// - [nickname]：本端昵称
  final Future<void> Function({
    required String url,
    required bool create,
    String? roomId,
    required String nickname,
  }) onStart;

  const HomePage({super.key, required this.onStart});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _urlCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(text: '匿名');
  bool _joining = false;
  bool _busy = false;

  // Aui 色板
  static const Color _kBgWarm = Color(0xFFF0ECE6);
  static const Color _kBgPaper = Color(0xFFF7F5F2);
  static const Color _kTextPrimary = Color(0xFF2C2C2C);
  static const Color _kTextSecondary = Color(0xFF6B6B6B);
  static const Color _kAccent = Color(0xFF8B7355);
  static const Color _kBorder = Color(0xFFE0DCD6);

  // 交错淡入动画：每个块延迟 0.3s 出现，单块时长 1.2s
  late final AnimationController _fadeCtrl;
  final List<Animation<double>> _fadeAnims = [];
  static const int _animBlockCount = 5;
  static const Duration _blockDuration = Duration(milliseconds: 1200);
  static const Duration _stagger = Duration(milliseconds: 300);
  static final Duration _totalDuration =
      _blockDuration + _stagger * (_animBlockCount - 1);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: _totalDuration,
    )..forward();
    final totalMs = _totalDuration.inMilliseconds;
    for (var i = 0; i < _animBlockCount; i++) {
      final beginMs = (_stagger * i).inMilliseconds;
      final endMs = beginMs + _blockDuration.inMilliseconds;
      _fadeAnims.add(
        CurvedAnimation(
          parent: _fadeCtrl,
          curve: Interval(
            beginMs / totalMs,
            endMs / totalMs,
            curve: Curves.easeInOutCubic,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _roomCtrl.dispose();
    _nameCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _start({required bool create}) async {
    final url = _urlCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请粘贴视频网址')),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入昵称')),
      );
      return;
    }
    if (!create && _roomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入房间号')),
      );
      return;
    }
    setState(() => _busy = true);
    await widget.onStart(
      url: url,
      create: create,
      roomId:
          _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
      nickname: name,
    );
    if (mounted) setState(() => _busy = false);
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(
        color: _kTextSecondary,
        letterSpacing: 0.02,
      ),
      hintStyle: const TextStyle(
        color: Color(0xFF9A9A9A),
        letterSpacing: 0.02,
      ),
      filled: true,
      fillColor: _kBgPaper,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: _kBorder),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: _kAccent, width: 1.2),
      ),
    );
  }

  Widget _fadeBlock({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _fadeAnims[index],
      builder: (ctx, _) {
        final v = _fadeAnims[index].value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgPaper,
      appBar: AppBar(
        backgroundColor: _kBgWarm,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '异地同看',
          style: TextStyle(
            color: _kTextPrimary,
            letterSpacing: 0.2,
            fontSize: 18,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _fadeBlock(
                  index: 0,
                  child: TextField(
                    controller: _urlCtrl,
                    decoration: _fieldDecoration(
                      labelText: '视频网址',
                      hintText: '粘贴 B站 / YouTube 等视频网页地址',
                    ),
                    style: const TextStyle(
                      color: _kTextPrimary,
                      letterSpacing: 0.02,
                      height: 1.8,
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(height: 16),
                _fadeBlock(
                  index: 1,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: _fieldDecoration(labelText: '昵称'),
                    style: const TextStyle(
                      color: _kTextPrimary,
                      letterSpacing: 0.02,
                      height: 1.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _fadeBlock(
                  index: 2,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      checkboxTheme: CheckboxThemeData(
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _kAccent;
                          }
                          return null;
                        }),
                      ),
                    ),
                    child: CheckboxListTile(
                      value: _joining,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        '我要加入已有房间',
                        style: TextStyle(
                          color: _kTextSecondary,
                          fontSize: 14,
                          letterSpacing: 0.02,
                        ),
                      ),
                      onChanged: (v) =>
                          setState(() => _joining = v ?? false),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  child: _joining
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _fadeBlock(
                            index: 3,
                            child: TextField(
                              controller: _roomCtrl,
                              decoration: _fieldDecoration(
                                labelText: '房间号',
                                hintText: '对方告知的房间号',
                              ),
                              style: const TextStyle(
                                color: _kTextPrimary,
                                letterSpacing: 0.02,
                                height: 1.8,
                              ),
                              autocorrect: false,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 32),
                _fadeBlock(
                  index: 4,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kTextPrimary,
                      foregroundColor: _kBgPaper,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(4)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        letterSpacing: 0.15,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _start(create: !_joining),
                    child: Text(
                      _busy
                          ? '进入中...'
                          : (_joining ? '加入房间' : '创建房间'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
