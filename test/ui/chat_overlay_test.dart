import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/ui/chat_overlay.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  group('ChatOverlay', () {
    testWidgets('初始为收起态显示圆形聊天按钮', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChatOverlay(
                messages: const [],
                onSend: (_) {},
              ),
            ],
          ),
        ),
      ));

      // 收起态：圆形浮动按钮，背景色 #8B7355，白色聊天图标
      expect(find.byIcon(Icons.chat), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.backgroundColor, const Color(0xFF8B7355));
      expect(fab.heroTag, 'chat-toggle');
    });

    testWidgets('点击图标展开聊天面板，显示标题栏与输入框', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChatOverlay(
                messages: const [],
                onSend: (_) {},
              ),
            ],
          ),
        ),
      ));

      // 收起态点击聊天图标
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // 展开后：标题"聊天"、关闭按钮、输入框都可见
      expect(find.text('聊天'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('展开后点关闭按钮回到收起态', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChatOverlay(
                messages: const [],
                onSend: (_) {},
              ),
            ],
          ),
        ),
      ));

      // 展开
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // 点击关闭按钮
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 回到收起态：仅聊天图标可见，无输入框
      expect(find.byIcon(Icons.chat), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('输入文字点发送触发 onSend 并清空输入框', (tester) async {
      String? sent;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChatOverlay(
                messages: const [],
                onSend: (text) => sent = text,
              ),
            ],
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(sent, 'hello');
      // 输入框被清空
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '');
    });

    testWidgets('空文本不触发 onSend', (tester) async {
      var sentCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChatOverlay(
                messages: const [],
                onSend: (_) => sentCount++,
              ),
            ],
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(sentCount, 0);
    });

    testWidgets('消息列表展示发送者名与消息文字', (tester) async {
      final messages = [
        ChatMessage(
          id: 'm1',
          from: const Member(id: 'u1', name: 'Alice'),
          text: '你好',
          sentAt: DateTime(2026, 7, 27, 20, 0),
        ),
        ChatMessage(
          id: 'm2',
          from: const Member(id: 'u2', name: 'Bob'),
          text: '在吗',
          sentAt: DateTime(2026, 7, 27, 20, 1),
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChatOverlay(
                messages: messages,
                onSend: (_) {},
              ),
            ],
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      expect(find.text('你好'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('在吗'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });
}
