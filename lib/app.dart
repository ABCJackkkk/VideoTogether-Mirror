import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/ui/home_page.dart';
import 'package:videotogether/ui/watch_page.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_webview_bridge.dart';
import 'package:videotogether/webview/app_webview_controller.dart';
import 'package:videotogether/webview/vt_injector.dart';

/// App 根 widget：注入 [RoomStore] 并配置 [MaterialApp]。
///
/// 主题遵循 Aui 规范（暖沙色调）：
/// - 主背景 #F7F5F2、强调色 #8B7355、主文字 #2C2C2C
/// - 输入框 4px 圆角、focus 边框 #8B7355
/// - FilledButton 4px 圆角、背景 #2C2C2C、文字 #F7F5F2、letterSpacing 0.15em
class VideoTogetherApp extends StatelessWidget {
  const VideoTogetherApp({super.key});

  /// 真实 App 用 [VTWebViewBridge]；测试时由测试代码注入 [FakeVTBridge]。
  RoomStore _buildStore() {
    final webview = AppWebViewController();
    final injector = VTInjector(js: _JsAdapter(webview));
    final bridge = VTWebViewBridge(webview: webview, injector: injector);
    return RoomStore(bridge: bridge);
  }

  Future<void> _onStart(
    BuildContext context, {
    required String url,
    required bool create,
    String? roomId,
    required String nickname,
  }) async {
    final store = context.read<RoomStore>();
    if (create) {
      // VtLite 协议下房间名即房间唯一标识；创建时以昵称作为房间名
      await store.createRoom(name: nickname);
    } else {
      // 加入时 roomId 即对方告知的房间名
      await store.joinRoom(name: roomId ?? '');
    }
    if (!context.mounted) return;
    if (store.state == RoomStoreState.inRoom) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WatchPage(videoUrl: url, nickname: nickname),
        ),
      );
    } else if (store.state == RoomStoreState.error && context.mounted) {
      final err = store.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err != null ? '$err' : '进入房间失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => _buildStore(),
      child: MaterialApp(
        title: '异地同看',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: Builder(
          builder: (ctx) => HomePage(
            onStart: ({
              required String url,
              required bool create,
              String? roomId,
              required String nickname,
            }) =>
                _onStart(
              ctx,
              url: url,
              create: create,
              roomId: roomId,
              nickname: nickname,
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B7355),
        primary: const Color(0xFF8B7355),
        surface: const Color(0xFFF7F5F2),
        onSurface: const Color(0xFF2C2C2C),
      ),
      fontFamily: 'serif',
      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: Color(0xFF2C2C2C),
          letterSpacing: 0.02,
          height: 1.8,
        ),
        bodyMedium: TextStyle(
          color: Color(0xFF2C2C2C),
          letterSpacing: 0.02,
          height: 1.8,
        ),
        titleLarge: TextStyle(
          color: Color(0xFF2C2C2C),
          letterSpacing: 0.2,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Color(0xFF8B7355)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2C2C2C),
          foregroundColor: const Color(0xFFF7F5F2),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          textStyle: const TextStyle(letterSpacing: 0.15),
        ),
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
