import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// 首页：粘贴视频网址或选择本地文件 + 输入昵称 + 房间名/密码 + 选择创建或加入房间。
///
/// 视觉遵循 Aui（Ins 风简约、暖沙色调）规范：
/// - 主背景 #F7F5F2、顶栏暖背景 #F0ECE6
/// - 输入框 4px 圆角，边框 #E0DCD6，focus 边框 #8B7355
/// - 主按钮 4px 圆角，背景 #2C2C2C，文字 #F7F5F2，letterSpacing 0.15em
/// - 入场为交错淡入（fadeUp，1.2s，间隔 0.3s）
class HomePage extends StatefulWidget {
  /// 点击创建/加入房间时触发。
  ///
  /// - [url]：视频网页地址，或本地视频文件的路径（当 [isLocalVideo] 为 true）
  /// - [create]：true=创建房间，false=加入房间
  /// - [roomName]：房间名，创建时自拟，加入时填对方告知的房间名
  /// - [password]：房间密码，可选；创建时设密，加入时需匹配
  /// - [nickname]：本端昵称
  /// - [isLocalVideo]：是否为本地视频文件
  final Future<void> Function({
    required String url,
    required bool create,
    required String roomName,
    required String nickname,
    String password,
    bool isLocalVideo,
  }) onStart;

  const HomePage({super.key, required this.onStart});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _urlCtrl = TextEditingController();
  final _roomNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(text: '匿名');
  bool _joining = false;
  bool _busy = false;
  bool _isLocalVideo = false;
  String? _localFilePath;
  String? _localFileName;

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
  static const int _animBlockCount = 7; // URL/本地文件 + 昵称 + 房间名 + 密码 + 本地视频切换 + 加入房间 + 按钮
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
    _roomNameCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocalVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    setState(() {
      _localFilePath = file.path;
      _localFileName = file.name;
    });
  }

  Future<void> _start({required bool create}) async {
    final url = _isLocalVideo ? (_localFilePath ?? '') : _urlCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final roomName = _roomNameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    // 房主必填视频网址或本地文件；加入方可不填（会自动跟随房主的视频 URL）
    if (create && url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isLocalVideo ? '请选择本地视频文件' : '请粘贴视频网址')),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入昵称')),
      );
      return;
    }
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入房间名')),
      );
      return;
    }
    setState(() => _busy = true);
    await widget.onStart(
      url: url,
      create: create,
      roomName: roomName,
      nickname: name,
      password: password,
      isLocalVideo: _isLocalVideo,
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
                // 视频网址：加入方隐藏（房主上报后自动跳转）；本地视频模式替换为文件选择
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  child: _joining
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _isLocalVideo
                                ? _fadeBlock(
                                    index: 0,
                                    child: _localVideoPicker(),
                                  )
                                : _fadeBlock(
                                    index: 0,
                                    child: TextField(
                                      controller: _urlCtrl,
                                      decoration: _fieldDecoration(
                                        labelText: '视频网址',
                                        hintText:
                                            '粘贴 B站 / YouTube 等视频网页地址',
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
                          ],
                        ),
                ),
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
                const SizedBox(height: 16),
                _fadeBlock(
                  index: 2,
                  child: TextField(
                    controller: _roomNameCtrl,
                    decoration: _fieldDecoration(
                      labelText: '房间名',
                      hintText: _joining ? '对方告知的房间名' : '自拟一个房间名',
                    ),
                    style: const TextStyle(
                      color: _kTextPrimary,
                      letterSpacing: 0.02,
                      height: 1.8,
                    ),
                    autocorrect: false,
                  ),
                ),
                const SizedBox(height: 16),
                _fadeBlock(
                  index: 3,
                  child: TextField(
                    controller: _passwordCtrl,
                    decoration: _fieldDecoration(
                      labelText: '房间密码',
                      hintText: '可选，留空表示无密码',
                    ),
                    style: const TextStyle(
                      color: _kTextPrimary,
                      letterSpacing: 0.02,
                      height: 1.8,
                    ),
                    obscureText: true,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(height: 8),
                // 本地视频开关（创建房间时可用）
                _fadeBlock(
                  index: 4,
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
                      value: _isLocalVideo,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        '播放本地视频文件',
                        style: TextStyle(
                          color: _kTextSecondary,
                          fontSize: 14,
                          letterSpacing: 0.02,
                        ),
                      ),
                      onChanged: _joining
                          ? null
                          : (v) => setState(() {
                                _isLocalVideo =
                                    v ?? false;
                                if (!_isLocalVideo) {
                                  _localFilePath = null;
                                  _localFileName = null;
                                }
                              }),
                    ),
                  ),
                ),
                _fadeBlock(
                  index: 5,
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
                const SizedBox(height: 32),
                _fadeBlock(
                  index: 6,
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

  /// 本地视频选择按钮 + 已选文件名
  Widget _localVideoPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _pickLocalVideo,
          icon: const Icon(Icons.video_library,
              color: _kAccent, size: 20),
          label: const Text(
            '选择视频文件',
            style: TextStyle(
              color: _kAccent,
              letterSpacing: 0.02,
              fontSize: 14,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _kAccent),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ),
        if (_localFileName != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.movie, color: _kAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _localFileName!,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 13,
                      letterSpacing: 0.02,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() {
                    _localFilePath = null;
                    _localFileName = null;
                  }),
                  child: const Icon(Icons.close,
                      color: _kTextSecondary, size: 16),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
