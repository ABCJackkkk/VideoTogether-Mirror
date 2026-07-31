import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/ui/home_page.dart';
import 'package:videotogether/ui/watch_page.dart';

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
    return RoomStore(); // bridge 由 WatchPage 初始化时绑定
  }

  Future<void> _onStart(
    BuildContext context, {
    required String url,
    required bool create,
    required String roomName,
    required String nickname,
    String password = '',
    bool isLocalVideo = false,
  }) async {
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchPage(
          videoUrl: url,
          nickname: nickname,
          isLocalVideo: isLocalVideo,
          create: create,
          roomName: roomName,
          password: password,
        ),
      ),
    );
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
              required String roomName,
              required String nickname,
              String password = '',
              bool isLocalVideo = false,
            }) =>
                _onStart(
              ctx,
              url: url,
              create: create,
              roomName: roomName,
              nickname: nickname,
              password: password,
              isLocalVideo: isLocalVideo,
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
