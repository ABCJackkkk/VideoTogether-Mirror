import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/ui/chat_overlay.dart';
import 'package:videotogether/ui/room_bar.dart';
import 'package:videotogether/vt/vt_webview_bridge.dart';
import 'package:videotogether/webview/app_webview_controller.dart';
import 'package:videotogether/webview/vt_injector.dart';

/// 观影页：组合 WebView + 顶栏 + 聊天浮层。
///
/// 顶栏 [RoomBar] 在 [RoomStore.room] 不为空时显示；
/// 剩余空间用 [InAppWebView] 铺满，上面叠 [ChatOverlay]。
/// WebView 加载完成后通过 [VTWebViewBridge.onPageLoaded] 注入 VtLite JS。
class WatchPage extends StatefulWidget {
  final String videoUrl;
  final String nickname;

  const WatchPage({super.key, required this.videoUrl, required this.nickname});

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  late final AppWebViewController _webviewCtrl;
  late final VTWebViewBridge _bridge;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _webviewCtrl = AppWebViewController();
    final injector = VTInjector(js: _JsAdapter(_webviewCtrl));
    _bridge = VTWebViewBridge(webview: _webviewCtrl, injector: injector);
  }

  @override
  void dispose() {
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
      body: Column(
        children: [
          Consumer<RoomStore>(
            builder: (ctx, store, _) {
              if (store.room == null) {
                return const SizedBox.shrink();
              }
              return RoomBar(
                room: store.room!,
                onLeave: () => _onLeave(store),
              );
            },
          ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(widget.videoUrl)),
                  onWebViewCreated: _webviewCtrl.attach,
                  onLoadStop: (controller, url) async {
                    if (_loaded) return;
                    _loaded = true;
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await _bridge.onPageLoaded();
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('同步注入失败: $e')),
                      );
                    }
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    final url = action.request.url.toString();
                    if (!url.startsWith('http')) {
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                ),
                Consumer<RoomStore>(
                  builder: (ctx, store, _) => ChatOverlay(
                    messages: store.messages,
                    onSend: (text) => store.sendMessage(text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 把 [AppWebViewController] 适配成 [JsEvaluator]，
/// 让 [VTInjector] 通过业务层封装调用 WebView 的 evaluateJavascript。
class _JsAdapter implements JsEvaluator {
  final AppWebViewController _ctrl;
  _JsAdapter(this._ctrl);

  @override
  Future<dynamic> evaluate(String source) async {
    return _ctrl.evaluateJavascript(source);
  }
}
