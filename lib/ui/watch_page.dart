import 'dart:async';
import 'dart:collection' show UnmodifiableListView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/ui/chat_overlay.dart';
import 'package:videotogether/ui/room_bar.dart';
import 'package:videotogether/vt/vt_webview_bridge.dart';
import 'package:videotogether/webview/app_webview_controller.dart';
import 'package:videotogether/webview/vt_injector.dart';

class WatchPage extends StatefulWidget {
  final String videoUrl;
  final String nickname;
  final bool isLocalVideo;
  final bool create;
  final String roomName;
  final String password;

  const WatchPage({
    super.key,
    required this.videoUrl,
    required this.nickname,
    required this.create,
    required this.roomName,
    this.isLocalVideo = false,
    this.password = '',
  });

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  late final AppWebViewController _webviewCtrl;
  late final VTWebViewBridge _bridge;
  RoomStore? _store;
  bool _errorHandled = false;
  bool _loaded = false;
  bool _loading = false;
  int _progress = 0;
  String _currentLoadedUrl = '';
  String? _localVideoHtml;
  String? _localVideoBaseUrl;
  bool _roomInited = false;

  // vt-lite.js 内容：预加载后通过 initialUserScripts 注入到所有 frame（含 iframe）
  String? _vtJs;

  // 黑屏诊断：进房后轮询页面是否有 <video>，超时给出引导提示
  Timer? _videoCheckTimer;
  bool _videoTimeout = false;

  // 调试浮层：长按 WebView 显示诊断信息（URL/iframe/video/VtLite 状态）
  bool _showDebug = false;
  String _debugInfo = '采集中...';

  @override
  void initState() {
    super.initState();
    _webviewCtrl = AppWebViewController();
    final injector = VTInjector(js: _JsAdapter(_webviewCtrl));
    _bridge = VTWebViewBridge(webview: _webviewCtrl, injector: injector)
      ..nickname = widget.nickname;

    if (widget.isLocalVideo && widget.videoUrl.isNotEmpty) {
      final path = widget.videoUrl.replaceAll('\\', '/');
      final lastSep = path.lastIndexOf('/');
      final dir = path.substring(0, lastSep + 1);
      final fileName = path.substring(lastSep + 1);
      _localVideoBaseUrl = 'file:///$dir';
      _localVideoHtml = '<!DOCTYPE html>'
          '<html><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">'
          '<style>html,body,body>*{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}'
          'video{object-fit:contain;width:100%;height:100%}</style></head>'
          '<body><video id="video" src="$fileName" controls autoplay playsinline></video></body></html>';
    }

    // 加入方不填视频网址，加载空白 HTML 让 onLoadStop 触发
    // 不用 about:blank，因为部分 WebView release 版 JS 桥接注入不完整
    if (!widget.isLocalVideo && widget.videoUrl.isEmpty) {
      _localVideoHtml = '<!DOCTYPE html>'
          '<html><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width,initial-scale=1">'
          '<style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000}</style>'
          '</head><body></body></html>';
      _localVideoBaseUrl = 'about:blank';
    }

    _currentLoadedUrl = widget.videoUrl;

    // 预加载 vt-lite.js：通过 initialUserScripts(forMainFrameOnly:false) 注入到
    // 所有 frame（含 iframe），子 frame 运行轻量代理脚本找 video 并 postMessage 上报，
    // 主 frame 运行完整 VtLite 通过 postMessage 控制子 frame video（跨域也能工作）
    rootBundle.loadString('assets/vt-lite.js').then((js) {
      if (mounted) setState(() => _vtJs = js);
    });

    // 仅绑定 bridge，不立即调用 createRoom/joinRoom：
    // 此时 WebView 尚未创建，VtLite JS 未注入，调用会静默失败。
    // 房间操作统一在 onLoadStop 注入 VtLite JS 后执行。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<RoomStore>();
      _store = store;
      store.addListener(_onStoreChanged);
      store.bindBridge(_bridge);
    });
  }

  /// 监听 RoomStore：进入房间失败（房间不存在/密码错误）时提示并返回
  void _onStoreChanged() {
    final store = _store;
    if (store == null || !mounted) return;
    if (store.state == RoomStoreState.error && !_errorHandled) {
      _errorHandled = true;
      final msg = store.lastError ?? '进入房间失败';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      Navigator.of(context).pop();
    }
  }

  /// 在 VtLite JS 注入完成后调用 createRoom/joinRoom
  /// （由 onLoadStop 触发，保证 window.VtLite 已存在）
  Future<void> _initRoom() async {
    if (_roomInited) return;
    _roomInited = true;
    final store = context.read<RoomStore>();
    try {
      if (widget.create) {
        await store.createRoom(
            name: widget.roomName, password: widget.password);
      } else {
        await store.joinRoom(
            name: widget.roomName, password: widget.password);
      }
      // 进房成功后启动"是否有可播放视频"检测，黑屏时给出引导
      _startVideoCheck();
    } catch (e) {
      _errorHandled = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('进入房间失败: $e')));
      Navigator.of(context).pop();
    }
  }

  /// 每 500ms 检查页面是否有可播放视频（video 元素且有画面）；15 秒超时提示。
  /// 影视站（如 laifu8）需用户点击选集才加载视频，仅检测 video 存在会漏判黑屏：
  /// video 标签在但 videoWidth=0（没画面）时仍需引导用户点击播放。
  void _startVideoCheck() {
    _videoCheckTimer?.cancel();
    _videoTimeout = false;
    var tries = 0;
    // 检测 video 是否有画面：递归查找 iframe（含同源子 frame），videoWidth>0 表示已出帧
    const js = '(function(){function find(d){try{var v=d.querySelector("video");'
        'if(v)return v;var fs=d.querySelectorAll("iframe");'
        'for(var i=0;i<fs.length;i++){try{var s=fs[i].contentDocument;'
        'if(s){v=find(s);if(v)return v;}}catch(e){}}}catch(e){}return null}'
        'var v=find(document);if(!v)return "none";'
        'if(v.videoWidth>0||v.readyState>=2)return "playing";return "empty";})()';
    _videoCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _evalJs(js).then((result) {
        // evaluateJavascript 返回 JSON 编码字符串："playing" 带引号，
        // 用 contains 宽松匹配避免误判
        final s = result?.toString() ?? '';
        if (s.contains('playing')) {
          t.cancel();
          if (_videoTimeout && mounted) setState(() => _videoTimeout = false);
          return;
        }
        tries++;
        // 15 秒（30 次）后超时；影视站加载慢，比 10 秒宽裕
        if (tries >= 30) {
          t.cancel();
          if (mounted) setState(() => _videoTimeout = true);
        }
      });
    });
  }

  Future<dynamic> _evalJs(String js) async {
    try {
      return await _webviewCtrl.evaluateJavascript(js);
    } catch (_) {
      return null;
    }
  }

  /// 采集页面诊断信息：URL、iframe 数量、video 位置/尺寸、VtLite 状态
  Future<void> _collectDebugInfo() async {
    final js = '''
(function(){
  var out = [];
  out.push("URL: " + location.href);
  out.push("readyState: " + document.readyState);
  // 主 frame video
  var v = document.querySelector("video");
  out.push("主frame video: " + (v ? (v.videoWidth + "x" + v.videoHeight + " ready=" + v.readyState + " paused=" + v.paused + " src=" + (v.currentSrc||v.src||"无")) : "无"));
  // iframe 数量与同源访问
  var fs = document.querySelectorAll("iframe");
  out.push("iframe 数量: " + fs.length);
  for (var i = 0; i < fs.length; i++) {
    var f = fs[i];
    var info = "  iframe[" + i + "] src=" + (f.src||"无");
    try {
      var sv = f.contentDocument.querySelector("video");
      if (sv) info += " | video: " + sv.videoWidth + "x" + sv.videoHeight + " ready=" + sv.readyState;
      else info += " | video: 无";
    } catch(e) { info += " | 跨域无法访问"; }
    out.push(info);
  }
  // VtLite 状态
  var vt = window.VtLite;
  if (vt) {
    out.push("VtLite: 存在, createRoom=" + (typeof vt.createRoom) + ", _isFrameAgent=" + !!vt._isFrameAgent);
    try {
      var st = vt.getState ? vt.getState() : null;
      if (st) out.push("VtLite state: " + JSON.stringify(st));
    } catch(e) { out.push("VtLite state 读取失败: " + e); }
  } else {
    out.push("VtLite: 不存在");
  }
  return out.join("\\n");
})()
''';
    final result = await _evalJs(js);
    final s = result?.toString() ?? 'null';
    // evaluateJavascript 返回 JSON 编码字符串（带引号），去掉首尾引号
    var cleaned = s;
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
      // 反转义
      cleaned = cleaned.replaceAll('\\n', '\n').replaceAll('\\"', '"');
    }
    if (mounted) setState(() => _debugInfo = cleaned);
  }

  @override
  void dispose() {
    _videoCheckTimer?.cancel();
    _store?.removeListener(_onStoreChanged);
    // 返回/退出时主动离开房间：停止上报/心跳定时器、断开 WS，
    // 避免残留连接继续占用房间或反复重连
    _bridge.leaveRoom();
    _bridge.dispose();
    super.dispose();
  }

  Future<void> _onLeave(RoomStore store) async {
    await store.leaveRoom();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      body: Consumer<RoomStore>(
        builder: (ctx, store, _) {
          // error 时 UI 仍然显示，顶栏/底部正常渲染，
          // 由 _initRoom 的 catch 负责 snackbar + pop
          final isConnecting = store.state == RoomStoreState.loading ||
              store.state == RoomStoreState.idle;

          return Column(
            children: [
              if (store.room != null) ...[
                _AutoFollowHostUrl(
                  store: store,
                  currentLoadedUrl: _currentLoadedUrl,
                  onFollow: (hostUrl) async {
                    if (!mounted) return;
                    _currentLoadedUrl = hostUrl;
                    _loaded = false;
                    // 跳转新 URL 后 JS 上下文重置，VtLite 需重新注入+重新 joinRoom
                    _roomInited = false;
                    _bridge.reset();
                    final messenger = ScaffoldMessenger.of(context);
                    // 提示加入方：影视站可能需手动点击播放/选集
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('正在加载房主视频页…如未自动播放请点击网页中的播放按钮或选集'),
                        duration: Duration(seconds: 4),
                      ),
                    );
                    try {
                      await _webviewCtrl.loadUrl(hostUrl);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('加载房主视频失败: $e')),
                      );
                    }
                  },
                ),
                RoomBar(
                  room: store.room!,
                  wsStatus: store.wsStatus,
                  onLeave: () => _onLeave(store),
                ),
              ] else
                _buildConnectingBar(isConnecting),
              Expanded(
                child: Stack(
                  children: [
                    if (_vtJs != null)
                      InAppWebView(
                        // forMainFrameOnly:false → 脚本注入到所有 frame（含 iframe）
                        // 子 frame 运行轻量代理找 video + postMessage 上报，
                        // 主 frame 运行完整 VtLite 通过 postMessage 控制（跨域也能工作）
                        initialUserScripts: UnmodifiableListView([
                          UserScript(
                            groupName: 'vt-lite',
                            source: _vtJs!,
                            // AT_DOCUMENT_END：等 DOM 解析完再注入，
                            // AT_DOCUMENT_START 时 document.body 可能不存在，
                            // vt-lite.js 里的 setInterval/DOM 操作会失败
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_END,
                            forMainFrameOnly: false,
                          ),
                        ]),
                        initialUrlRequest:
                          (widget.isLocalVideo || widget.videoUrl.isEmpty)
                              ? null
                              : URLRequest(url: WebUri(widget.videoUrl)),
                      initialData: (_localVideoHtml != null)
                          ? InAppWebViewInitialData(
                              data: _localVideoHtml!,
                              baseUrl: WebUri(_localVideoBaseUrl!),
                            )
                          : null,
                      onWebViewCreated: _webviewCtrl.attach,
                      onLoadStart: (controller, url) {
                        if (url != null) _currentLoadedUrl = url.toString();
                        setState(() {
                          _loading = true;
                          _progress = 0;
                        });
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() {
                          _progress = progress;
                          if (progress >= 100) _loading = false;
                        });
                      },
                      onLoadStop: (controller, url) async {
                        if (url != null) _currentLoadedUrl = url.toString();
                        if (mounted) setState(() => _loading = false);
                        // await 前获取 messenger，避免 async gap 后使用 context
                        final messenger = ScaffoldMessenger.of(context);
                        // 页面整页跳转（新域名/新文档）后 JS 上下文会重置，
                        // VtLite 随之丢失：检测到缺失时重新注入并重新进房
                        final hasVt = await _bridge.hasVtLite();
                        if (!hasVt) {
                          _loaded = false;
                          _roomInited = false;
                          _bridge.reset();
                        }
                        if (_loaded || !mounted) return;
                        _loaded = true;
                        // 注入 VtLite JS（无 video 也注入，内部自动轮询）
                        try {
                          await _bridge.onPageLoaded();
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('同步注入失败: $e')),
                          );
                        }
                        // 注入完成后发起 createRoom/joinRoom（统一入口，
                        // 避免重复调用导致角色被重置、定时器混乱）
                        await _initRoom();
                      },
                      onReceivedError: (controller, request, error) async {
                        // 已进房后页面加载失败（如跟随房主跳转的网页打不开）：
                        // 明确提示，避免成员侧一直黑屏无反馈
                        if (_loaded && _roomInited && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('房主视频页面加载失败。建议双方改用视频直链（.mp4 地址）或本地文件，B站/腾讯网页在 App 内可能被限制。'),
                              duration: Duration(seconds: 5),
                            ),
                          );
                          return;
                        }
                        // 初始页加载失败时仍尝试注入 JS（initialData 空白页可注入）
                        // 保证加入方/本地视频方房间流程能继续
                        if (_loaded) return;
                        _loaded = true;
                        setState(() => _loading = false);
                        try {
                          await _bridge.onPageLoaded();
                        } catch (_) {}
                        await _initRoom();
                      },
                      shouldOverrideUrlLoading: (controller, action) async {
                        final url = action.request.url.toString();
                        if (url.startsWith('intent://') ||
                            url.startsWith('market://') ||
                            url.startsWith('tel:') ||
                            url.startsWith('mailto:')) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                    )
                    else
                      const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF8B7355),
                        ),
                      ),
                    if (_loading)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress / 100 : null,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF8B7355),
                          ),
                        ),
                      ),
                    if (_loading)
                      const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF8B7355),
                        ),
                      ),
                    Consumer<RoomStore>(
                      builder: (ctx, store, _) => ChatOverlay(
                        messages: store.messages,
                        onSend: (text) => store.sendMessage(text),
                      ),
                    ),
                    if (_videoTimeout && store.room != null)
                      _buildVideoTimeoutOverlay(),
                    if (isConnecting && store.room == null)
                      _buildConnectingOverlay(),
                    // 调试按钮：右下角小圆点，点击采集诊断信息
                    Positioned(
                      right: 12,
                      bottom: 80,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _showDebug = !_showDebug;
                            _debugInfo = '采集中...';
                          });
                          if (_showDebug) _collectDebugInfo();
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.bug_report,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    if (_showDebug)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 120,
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _debugInfo,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontFamily: 'monospace',
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectingBar(bool isConnecting) {
    return Container(
      height: 56,
      color: const Color(0xFFF0ECE6),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF8B7355),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isConnecting ? '连接中...' : '等待房主',
            style: const TextStyle(
              color: Color(0xFF6B6B6B),
              fontSize: 14,
              letterSpacing: 0.02,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(
                color: Color(0xFF6B6B6B),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingOverlay() {
    return Container(
      color: const Color(0x99F7F5F2),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF8B7355),
              ),
            ),
            SizedBox(height: 16),
            Text(
              '正在连接房间...',
              style: TextStyle(
                color: Color(0xFF6B6B6B),
                fontSize: 14,
                letterSpacing: 0.02,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 进房成功但 10 秒内页面没有出现可播放视频（黑屏）时的引导层
  Widget _buildVideoTimeoutOverlay() {
    return Container(
      color: const Color(0xCCF7F5F2),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.live_tv, size: 40, color: Color(0xFF8B7355)),
              const SizedBox(height: 12),
              const Text(
                '未检测到可播放视频',
                style: TextStyle(
                  color: Color(0xFF2C2C2C),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '已连上房间，但视频还没开始播放。\n'
                '请尝试点击网页中的播放按钮或选集；\n'
                '若仍不行，建议双方改用视频直链（.mp4）或本地文件。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B6B6B),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _videoTimeout = false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF8B7355)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                ),
                child: const Text(
                  '知道了',
                  style: TextStyle(color: Color(0xFF8B7355), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JsAdapter implements JsEvaluator {
  final AppWebViewController _ctrl;
  _JsAdapter(this._ctrl);

  @override
  Future<dynamic> evaluate(String source) async {
    return _ctrl.evaluateJavascript(source);
  }
}

class _AutoFollowHostUrl extends StatefulWidget {
  final RoomStore store;
  final String currentLoadedUrl;
  final Future<void> Function(String hostUrl) onFollow;

  const _AutoFollowHostUrl({
    required this.store,
    required this.currentLoadedUrl,
    required this.onFollow,
  });

  @override
  State<_AutoFollowHostUrl> createState() => _AutoFollowHostUrlState();
}

class _AutoFollowHostUrlState extends State<_AutoFollowHostUrl> {
  String? _lastFollowedUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFollow());
  }

  @override
  void didUpdateWidget(covariant _AutoFollowHostUrl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store.room?.url != widget.store.room?.url) {
      _checkFollow();
    }
  }

  void _checkFollow() {
    final hostUrl = widget.store.room?.url;
    if (hostUrl == null || hostUrl.isEmpty) return;
    if (hostUrl.startsWith('file://')) return;
    if (hostUrl == widget.currentLoadedUrl) return;
    if (hostUrl == _lastFollowedUrl) return;
    _lastFollowedUrl = hostUrl;
    widget.onFollow(hostUrl);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
