# 异地同看视频 App 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一款 Flutter 双端 App，让朋友异地同步看网页视频，复用 VideoTogether（VT）开源 JS + 公共服务器，零自建后端。

**Architecture:** Flutter App 内用 `flutter_inappwebview` 打开视频网页，网页 `<video>` 元素出现后注入 VT 开源客户端 JS。VT JS 自动连接 `wss://api2.videotogether.com` 完成视频同步与文字聊天。Dart 层通过 JS 桥调用 VT API、监听 VT 事件刷新 UI。

**Tech Stack:** Flutter、flutter_inappwebview 6.x、VideoTogether 开源客户端 JS（MIT）、ChangeNotifier 状态管理。无后端依赖。

**Spec:** `docs/superpowers/specs/2026-07-27-videotogether-mobile-app-design.md`

---

## 文件结构

```
avideotogether/
├── pubspec.yaml                          # 依赖声明
├── assets/
│   └── vt-client.js                      # VT 开源客户端 JS（打包后单文件）
├── lib/
│   ├── main.dart                         # App 入口
│   ├── app.dart                          # MaterialApp + 路由
│   ├── ui/
│   │   ├── home_page.dart                # 首页：粘贴网址、创建/加入房间
│   │   ├── watch_page.dart               # 观影页：WebView + 顶栏 + 聊天浮层
│   │   ├── chat_overlay.dart             # 聊天悬浮面板
│   │   └── room_bar.dart                 # 顶栏：房间号、成员、邀请
│   ├── webview/
│   │   ├── app_webview_controller.dart   # WebView 控制层封装
│   │   └── vt_injector.dart              # VT JS 注入逻辑（轮询等 video）
│   ├── vt/
│   │   ├── vt_bridge.dart                # VT 集成层：Dart 调 JS + 事件回调
│   │   ├── vt_events.dart                # VT 事件类型定义
│   │   └── vt_models.dart                # Room/Member/ChatMessage 模型
│   └── state/
│       └── room_store.dart               # 房间状态管理（ChangeNotifier）
├── test/
│   ├── vt/
│   │   ├── vt_models_test.dart
│   │   └── vt_bridge_test.dart
│   ├── webview/
│   │   └── vt_injector_test.dart
│   ├── state/
│   │   └── room_store_test.dart
│   └── ui/
│       └── chat_overlay_test.dart
└── scripts/
    └── fetch_vt_client.ps1               # 拉取并打包 VT 客户端 JS 的脚本
```

**职责边界**：
- `ui/`：纯 widgets，不直接碰 WebView/JS
- `webview/`：WebView 封装与 JS 注入，不碰业务逻辑
- `vt/`：VT API 的 Dart 抽象，对上提供业务方法，对下调 webview 层
- `state/`：房间状态，连接 vt 层与 ui 层

---

## Task 0: 确认 VT 客户端 JS 的实际 API

**Files:**
- Create: `docs/notes/vt-api.md`（记录 VT 实际暴露的 JS 函数名与事件名）

**说明**：本计划后续代码假设 VT 客户端 JS 暴露 `window.VideoTogether.*` API。实际函数名必须以 VT 仓库源码为准。此任务先做核实，后续任务如发现 API 名不符，以本任务记录为准回填。

- [ ] **Step 1: clone VT 仓库到临时目录**

Run:
```powershell
cd d:\avideotogether
git clone --depth 1 https://github.com/VideoTogether/VideoTogether.git .vt-tmp
```
Expected: 仓库克隆成功，`.vt-tmp/` 出现源码

- [ ] **Step 2: 浏览源码定位客户端入口**

在 `.vt-tmp/` 中找客户端入口（通常是 `extension/` 或 `client/` 目录下的 `content.js` / `inject.js`）。搜索 `window.VideoTogether`、`createRoom`、`joinRoom`、`sendMessage` 等关键字。

Run:
```powershell
# 用 Grep 工具搜索，不要用 findstr
# 在 .vt-tmp 内搜索 "window.VideoTogether =" 或 "VideoTogether ="
```

- [ ] **Step 3: 记录实际 API 到 `docs/notes/vt-api.md`**

记录：
- 全局对象名（如 `window.VideoTogether`）
- 创建房间函数名与参数
- 加入房间函数名与参数
- 离开房间函数名
- 发送消息函数名
- 播放/暂停/跳转函数名
- 事件回调机制（如何向 Dart 通报状态变化）
- WebSocket 服务器地址（确认是 `wss://api2.videotogether.com`）

如 API 名与本计划假设不符，回填后续任务的代码。

- [ ] **Step 4: 清理临时目录**

Run:
```powershell
Remove-Item -Recurse -Force .vt-tmp
```

- [ ] **Step 5: Commit**

```powershell
git add docs/notes/vt-api.md
git commit -m "docs: 记录 VideoTogether 客户端 JS 实际 API"
```

---

## Task 1: Flutter 项目脚手架

**Files:**
- Create: 整个 Flutter 项目骨架（`pubspec.yaml`、`lib/main.dart`、`test/widget_test.dart`）

- [ ] **Step 1: 创建 Flutter 项目**

Run:
```powershell
cd d:\avideotogether
flutter create . --project-name videotogether --platforms=android,ios
```
Expected: 生成 Flutter 项目，`pubspec.yaml`、`lib/main.dart` 等就位

- [ ] **Step 2: 添加 flutter_inappwebview 依赖**

修改 `pubspec.yaml` 的 `dependencies:` 段，添加：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.0.0
```

- [ ] **Step 3: 拉取依赖**

Run:
```powershell
flutter pub get
```
Expected: 依赖安装成功，无报错

- [ ] **Step 4: 配置 assets 目录**

在 `pubspec.yaml` 添加：

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/
```

并创建空目录 `assets/`（放一个 `.gitkeep`）。

- [ ] **Step 5: Android 配置允许 HTTP（部分视频站需要）**

修改 `android/app/src/main/AndroidManifest.xml`，在 `<application>` 标签加 `android:usesCleartextTraffic="true"`。

- [ ] **Step 6: iOS 配置允许 HTTP**

修改 `ios/Runner/Info.plist`，在 `<dict>` 内添加：

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

- [ ] **Step 7: 跑通空 App**

Run:
```powershell
flutter run -d windows
```
Expected: 默认 Flutter 计数器示例 App 启动

- [ ] **Step 8: Commit**

```powershell
git add .
git commit -m "chore: Flutter 项目脚手架 + flutter_inappwebview 依赖"
```

---

## Task 2: 拉取并打包 VT 客户端 JS

**Files:**
- Create: `scripts/fetch_vt_client.ps1`
- Create: `assets/vt-client.js`

- [ ] **Step 1: 写打包脚本 `scripts/fetch_vt_client.ps1`**

```powershell
# 拉取 VideoTogether 客户端 JS 并打包成单文件
$ErrorActionPreference = "Stop"
$tmp = ".vt-build-tmp"

if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
git clone --depth 1 https://github.com/VideoTogether/VideoTogether.git $tmp

# 定位客户端入口文件（根据 Task 0 的记录调整路径）
$src = Join-Path $tmp "extension"
Push-Location $src

# 若仓库有 webpack 配置，用它打包；否则手动拼接
if (Test-Path "webpack.config.js") {
    npm install
    npm run build
    # 假设输出到 dist/vt-client.js（按实际调整）
    Copy-Item "dist/vt-client.js" "..\..\assets\vt-client.js" -Force
} else {
    # 退路：拼接所有 content script 源文件
    Get-ChildItem -Filter "*.js" | ForEach-Object {
        Get-Content $_.FullName
        "`n;"
    } | Out-File "..\..\assets\vt-client.js" -Encoding utf8
}

Pop-Location
Remove-Item -Recurse -Force $tmp
Write-Host "vt-client.js 打包完成 -> assets/vt-client.js"
```

- [ ] **Step 2: 运行脚本**

Run:
```powershell
cd d:\avideotogether
powershell -ExecutionPolicy Bypass -File scripts\fetch_vt_client.ps1
```
Expected: `assets/vt-client.js` 生成，文件非空

- [ ] **Step 3: 验证 JS 文件有效**

Run:
```powershell
# 检查文件大小 > 1KB
(Get-Item assets\vt-client.js).Length
```
Expected: 大于 1024 字节

- [ ] **Step 4: 在 JS 末尾追加 Dart 回调桥接代码**

在 `assets/vt-client.js` 末尾追加（让 VT 事件能回调到 Dart）：

```javascript
// === Dart 桥接：把 VT 事件转发到 Flutter ===
(function() {
  // 监听 VT 状态变化（具体钩子名按 Task 0 记录调整）
  // 这里假设 VT 有 onStateChange 回调
  if (typeof window.VideoTogether !== 'undefined' && window.VideoTogether.onStateChange) {
    const orig = window.VideoTogether.onStateChange;
    window.VideoTogether.onStateChange = function(state) {
      // 转发给 Flutter
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onVTEvent', state);
      }
      if (orig) return orig(state);
    };
  }
})();
```

- [ ] **Step 5: Commit**

```powershell
git add scripts/fetch_vt_client.ps1 assets/vt-client.js pubspec.yaml
git commit -m "feat: 拉取并打包 VideoTogether 客户端 JS 到 assets"
```

---

## Task 3: VT 数据模型

**Files:**
- Create: `lib/vt/vt_models.dart`
- Test: `test/vt/vt_models_test.dart`

- [ ] **Step 1: 写失败测试 `test/vt/vt_models_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  group('Room', () {
    test('从房间号构造 Room', () {
      final room = Room(id: 'abc123', name: '周五电影夜', members: const []);
      expect(room.id, 'abc123');
      expect(room.name, '周五电影夜');
      expect(room.members, isEmpty);
    });

    test('成员数计算', () {
      final room = Room(
        id: 'abc123',
        name: 'test',
        members: [
          Member(id: 'u1', name: 'A'),
          Member(id: 'u2', name: 'B'),
        ],
      );
      expect(room.memberCount, 2);
    });
  });

  group('ChatMessage', () {
    test('构造与字段', () {
      final msg = ChatMessage(
        id: 'm1',
        from: Member(id: 'u1', name: 'A'),
        text: 'hi',
        sentAt: DateTime(2026, 7, 27, 20, 0),
      );
      expect(msg.text, 'hi');
      expect(msg.from.name, 'A');
    });
  });

  group('SyncState', () {
    test('paused 状态', () {
      const state = SyncState.paused(currentTime: 120.5);
      expect(state.isPlaying, isFalse);
      expect(state.currentTime, 120.5);
    });

    test('playing 状态', () {
      const state = SyncState.playing(currentTime: 120.5);
      expect(state.isPlaying, isTrue);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```powershell
flutter test test/vt/vt_models_test.dart
```
Expected: FAIL（`vt_models.dart` 不存在）

- [ ] **Step 3: 实现 `lib/vt/vt_models.dart`**

```dart
/// VT 数据模型
library;

/// 房间成员
class Member {
  final String id;
  final String name;

  const Member({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Member && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Member($id, $name)';
}

/// 房间
class Room {
  final String id;
  final String name;
  final List<Member> members;

  const Room({
    required this.id,
    required this.name,
    required this.members,
  });

  int get memberCount => members.length;

  Room copyWith({String? id, String? name, List<Member>? members}) => Room(
        id: id ?? this.id,
        name: name ?? this.name,
        members: members ?? this.members,
      );
}

/// 聊天消息
class ChatMessage {
  final String id;
  final Member from;
  final String text;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.sentAt,
  });
}

/// 视频同步状态
sealed class SyncState {
  final double currentTime;
  const SyncState({required this.currentTime});

  bool get isPlaying;

  const factory SyncState.paused({required double currentTime}) =
      PausedSyncState;
  const factory SyncState.playing({required double currentTime}) =
      PlayingSyncState;
}

class PausedSyncState extends SyncState {
  const PausedSyncState({required super.currentTime});
  @override
  bool get isPlaying => false;
}

class PlayingSyncState extends SyncState {
  const PlayingSyncState({required super.currentTime});
  @override
  bool get isPlaying => true;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```powershell
flutter test test/vt/vt_models_test.dart
```
Expected: PASS（3 个测试全过）

- [ ] **Step 5: Commit**

```powershell
git add lib/vt/vt_models.dart test/vt/vt_models_test.dart
git commit -m "feat: VT 数据模型（Room/Member/ChatMessage/SyncState）"
```

---

## Task 4: VT 事件类型

**Files:**
- Create: `lib/vt/vt_events.dart`
- Test: `test/vt/vt_events_test.dart`

- [ ] **Step 1: 写失败测试 `test/vt/vt_events_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  test('从 JSON 解析 paused 事件', () {
    final event = VTEvent.fromJson({
      'type': 'paused',
      'time': 120.5,
      'by': 'A',
    });
    expect(event, isA<PausedEvent>());
    final p = event as PausedEvent;
    expect(p.time, 120.5);
    expect(p.by, 'A');
  });

  test('从 JSON 解析 memberJoined 事件', () {
    final event = VTEvent.fromJson({
      'type': 'memberJoined',
      'member': {'id': 'u2', 'name': 'B'},
    });
    expect(event, isA<MemberJoinedEvent>());
    expect((event as MemberJoinedEvent).member.name, 'B');
  });

  test('从 JSON 解析 chatMessage 事件', () {
    final event = VTEvent.fromJson({
      'type': 'chatMessage',
      'message': {
        'id': 'm1',
        'from': {'id': 'u1', 'name': 'A'},
        'text': 'hi',
        'sentAt': '2026-07-27T20:00:00',
      },
    });
    expect(event, isA<ChatMessageEvent>());
    expect((event as ChatMessageEvent).message.text, 'hi');
  });

  test('未知事件类型解析为 UnknownEvent', () {
    final event = VTEvent.fromJson({'type': 'whatever'});
    expect(event, isA<UnknownEvent>());
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```powershell
flutter test test/vt/vt_events_test.dart
```
Expected: FAIL（`vt_events.dart` 不存在）

- [ ] **Step 3: 实现 `lib/vt/vt_events.dart`**

```dart
import 'package:videotogether/vt/vt_models.dart';

/// VT 事件基类
sealed class VTEvent {
  const VTEvent();

  factory VTEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'paused':
        return PausedEvent(
          time: (json['time'] as num).toDouble(),
          by: json['by'] as String? ?? '',
        );
      case 'played':
        return PlayedEvent(
          time: (json['time'] as num).toDouble(),
          by: json['by'] as String? ?? '',
        );
      case 'seeked':
        return SeekedEvent(
          time: (json['time'] as num).toDouble(),
          by: json['by'] as String? ?? '',
        );
      case 'memberJoined':
        return MemberJoinedEvent(
          member: Member(
            id: (json['member'] as Map)['id'] as String,
            name: (json['member'] as Map)['name'] as String,
          ),
        );
      case 'memberLeft':
        return MemberLeftEvent(
          memberId: (json['memberId'] as String?) ?? '',
        );
      case 'chatMessage':
        final m = json['message'] as Map;
        return ChatMessageEvent(
          message: ChatMessage(
            id: m['id'] as String,
            from: Member(
              id: (m['from'] as Map)['id'] as String,
              name: (m['from'] as Map)['name'] as String,
            ),
            text: m['text'] as String,
            sentAt: DateTime.parse(m['sentAt'] as String),
          ),
        );
      default:
        return UnknownEvent(raw: json);
    }
  }
}

class PausedEvent extends VTEvent {
  final double time;
  final String by;
  const PausedEvent({required this.time, required this.by});
}

class PlayedEvent extends VTEvent {
  final double time;
  final String by;
  const PlayedEvent({required this.time, required this.by});
}

class SeekedEvent extends VTEvent {
  final double time;
  final String by;
  const SeekedEvent({required this.time, required this.by});
}

class MemberJoinedEvent extends VTEvent {
  final Member member;
  const MemberJoinedEvent({required this.member});
}

class MemberLeftEvent extends VTEvent {
  final String memberId;
  const MemberLeftEvent({required this.memberId});
}

class ChatMessageEvent extends VTEvent {
  final ChatMessage message;
  const ChatMessageEvent({required this.message});
}

class UnknownEvent extends VTEvent {
  final Map<String, dynamic> raw;
  const UnknownEvent({required this.raw});
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```powershell
flutter test test/vt/vt_events_test.dart
```
Expected: PASS（4 个测试全过）

- [ ] **Step 5: Commit**

```powershell
git add lib/vt/vt_events.dart test/vt/vt_events_test.dart
git commit -m "feat: VT 事件类型与 JSON 解析"
```

---

## Task 5: VT Bridge 接口（抽象）+ 假实现

**Files:**
- Create: `lib/vt/vt_bridge.dart`
- Test: `test/vt/vt_bridge_test.dart`

**说明**：先定义抽象接口 + 一个 Fake 实现（用于 UI/State 层测试），真实实现放 Task 8。

- [ ] **Step 1: 写失败测试 `test/vt/vt_bridge_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  test('FakeVTBridge.createRoom 返回房间对象', () async {
    final bridge = FakeVTBridge();
    final room = await bridge.createRoom(name: 'test');
    expect(room.id, isNotEmpty);
    expect(room.name, 'test');
  });

  test('FakeVTBridge.joinRoom 房间不存在抛 RoomNotFoundException', () async {
    final bridge = FakeVTBridge();
    expect(
      () => bridge.joinRoom(roomId: 'no-such', name: 'test'),
      throwsA(isA<RoomNotFoundException>()),
    );
  });

  test('FakeVTBridge.sendMessage 后事件流能收到 chatMessage', () async {
    final bridge = FakeVTBridge();
    final room = await bridge.createRoom(name: 'test');
    final me = Member(id: 'u1', name: 'me');
    bridge.bindMember(room.id, me);

    final events = <VTEvent>[];
    bridge.events.listen(events.add);

    await bridge.sendMessage(room.id, 'hello');
    expect(events, anyElement(isA<ChatMessageEvent>()));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```powershell
flutter test test/vt/vt_bridge_test.dart
```
Expected: FAIL（`vt_bridge.dart` 不存在）

- [ ] **Step 3: 实现 `lib/vt/vt_bridge.dart`**

```dart
import 'dart:async';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

/// VT 集成层抽象接口
abstract class VTBridge {
  /// 创建房间，返回房间对象
  Future<Room> createRoom({required String name});

  /// 加入房间，房间不存在抛 RoomNotFoundException
  Future<Room> joinRoom({required String roomId, required String name});

  /// 离开房间
  Future<void> leaveRoom(String roomId);

  /// 发送播放控制
  Future<void> pause(String roomId);
  Future<void> play(String roomId);
  Future<void> seek(String roomId, double seconds);

  /// 发送文字消息
  Future<void> sendMessage(String roomId, String text);

  /// 事件流（成员变化、状态变化、新消息）
  Stream<VTEvent> get events;

  void dispose();
}

class RoomNotFoundException implements Exception {
  final String roomId;
  RoomNotFoundException(this.roomId);
  @override
  String toString() => '房间不存在: $roomId';
}

/// 用于测试和 UI 开发的假实现，不依赖 WebView
class FakeVTBridge implements VTBridge {
  final Map<String, Room> _rooms = {};
  final Map<String, Member> _membersInRoom = {};
  final StreamController<VTEvent> _events = StreamController.broadcast();

  @override
  Stream<VTEvent> get events => _events.stream;

  @override
  Future<Room> createRoom({required String name}) async {
    final id = 'room-${DateTime.now().millisecondsSinceEpoch}';
    final room = Room(id: id, name: name, members: const []);
    _rooms[id] = room;
    return room;
  }

  @override
  Future<Room> joinRoom({required String roomId, required String name}) async {
    if (!_rooms.containsKey(roomId)) {
      throw RoomNotFoundException(roomId);
    }
    return _rooms[roomId]!;
  }

  @override
  Future<void> leaveRoom(String roomId) async {}

  @override
  Future<void> pause(String roomId) async {
    _events.add(PausedEvent(time: 0, by: _membersInRoom[roomId]?.name ?? ''));
  }

  @override
  Future<void> play(String roomId) async {
    _events.add(PlayedEvent(time: 0, by: _membersInRoom[roomId]?.name ?? ''));
  }

  @override
  Future<void> seek(String roomId, double seconds) async {
    _events.add(SeekedEvent(time: seconds, by: _membersInRoom[roomId]?.name ?? ''));
  }

  @override
  Future<void> sendMessage(String roomId, String text) async {
    final me = _membersInRoom[roomId];
    if (me == null) return;
    _events.add(ChatMessageEvent(
      message: ChatMessage(
        id: 'm-${DateTime.now().millisecondsSinceEpoch}',
        from: me,
        text: text,
        sentAt: DateTime.now(),
      ),
    ));
  }

  /// 测试辅助：把当前用户绑定到房间
  void bindMember(String roomId, Member member) {
    _membersInRoom[roomId] = member;
  }

  @override
  void dispose() {
    _events.close();
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```powershell
flutter test test/vt/vt_bridge_test.dart
```
Expected: PASS（3 个测试全过）

- [ ] **Step 5: Commit**

```powershell
git add lib/vt/vt_bridge.dart test/vt/vt_bridge_test.dart
git commit -m "feat: VT Bridge 抽象接口 + Fake 实现"
```

---

## Task 6: WebView 控制层封装

**Files:**
- Create: `lib/webview/app_webview_controller.dart`

**说明**：封装 `flutter_inappwebview` 的 `InAppWebViewController`，提供 loadUrl / injectJS / registerHandler 三个高层方法。不写单元测试（依赖平台 WebView，跑不起来的），靠 Task 8 集成验证。

- [ ] **Step 1: 实现 `lib/webview/app_webview_controller.dart`**

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 对 InAppWebViewController 的业务层封装
class AppWebViewController {
  InAppWebViewController? _raw;

  /// 由 InAppWebView widget 的 onCreate回调注入
  void attach(InAppWebViewController controller) {
    _raw = controller;
    // 桌面 UA，规避移动端反爬
    controller.setSettings(
      settings: InAppWebViewSettings(
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
    );
  }

  void detach() => _raw = null;

  Future<void> loadUrl(String url) async {
    await _raw?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// 注入一段 JS，返回其执行结果
  Future<dynamic> evaluateJavascript(String source) async {
    return _raw?.evaluateJavascript(source: source);
  }

  /// 注册 Dart 侧 handler，供 JS 通过 callHandler 调用
  void registerHandler(String name, Future<dynamic> Function(List<dynamic>) handler) {
    _raw?.addJavaScriptHandler(handlerName: name, callback: handler);
  }

  /// 拦截 App 唤起 scheme，只放行 http/https
  void configureUrlInterception() {
    _raw?.setSettings(settings: InAppWebViewSettings(
      useShouldOverrideUrlLoading: true,
    ));
  }

  bool get isAttached => _raw != null;
}
```

- [ ] **Step 2: 检查静态分析**

Run:
```powershell
flutter analyze lib/webview/app_webview_controller.dart
```
Expected: 无 error（warning 可接受）

- [ ] **Step 3: Commit**

```powershell
git add lib/webview/app_webview_controller.dart
git commit -m "feat: WebView 控制层封装"
```

---

## Task 7: VT JS 注入逻辑

**Files:**
- Create: `lib/webview/vt_injector.dart`
- Test: `test/webview/vt_injector_test.dart`

**说明**：`VTInjector` 负责"等 `<video>` 出现 → 读 assets/vt-client.js → 注入"。轮询逻辑可测试（mock evaluateJavascript）。

- [ ] **Step 1: 写失败测试 `test/webview/vt_injector_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/webview/vt_injector.dart';

class _FakeJsEvaluator implements JsEvaluator {
  final List<String> calls = [];
  int _videoQueryCount = 0;

  @override
  Future<dynamic> evaluate(String source) async {
    calls.add(source);
    if (source.contains('querySelector("video")')) {
      _videoQueryCount++;
      return _videoQueryCount >= 2; // 第二次轮询时返回 true
    }
    return null;
  }
}

class _FakeAssetsLoader implements AssetsLoader {
  @override
  Future<String> loadString(String path) async => 'console.log("vt");';
}

void main() {
  test('轮询直到 video 元素出现后注入 VT JS', () async {
    final js = _FakeJsEvaluator();
    final assets = _FakeAssetsLoader();
    final injector = VTInjector(js: js, assets: assets);

    await injector.waitForVideoAndInject();

    // 应该有 querySelector 调用 + 注入调用
    expect(js.calls.any((c) => c.contains('querySelector("video")')), isTrue);
    expect(js.calls.any((c) => c.contains('console.log("vt")')), isTrue);
  });

  test('超时（10 秒内无 video）后抛 VideoNotFoundException', () async {
    final js = _FakeJsEvaluator()
      ..alwaysReturnFalse = true;
    final assets = _FakeAssetsLoader();
    final injector = VTInjector(
      js: js,
      assets: assets,
      pollInterval: const Duration(milliseconds: 10),
      maxAttempts: 3,
    );

    expect(
      injector.waitForVideoAndInject,
      throwsA(isA<VideoNotFoundException>()),
    );
  });
}
```

注：`_FakeJsEvaluator` 需加 `bool alwaysReturnFalse = false;` 字段，并在 `evaluate` 里 `if (alwaysReturnFalse) return false;`。补全：

```dart
class _FakeJsEvaluator implements JsEvaluator {
  final List<String> calls = [];
  int _videoQueryCount = 0;
  bool alwaysReturnFalse = false;

  @override
  Future<dynamic> evaluate(String source) async {
    if (alwaysReturnFalse) return false;
    calls.add(source);
    if (source.contains('querySelector("video")')) {
      _videoQueryCount++;
      return _videoQueryCount >= 2;
    }
    return null;
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```powershell
flutter test test/webview/vt_injector_test.dart
```
Expected: FAIL（`vt_injector.dart` 不存在）

- [ ] **Step 3: 实现 `lib/webview/vt_injector.dart`**

```dart
import 'package:flutter/services.dart' show rootBundle;

/// JS 执行器抽象（便于测试）
abstract class JsEvaluator {
  Future<dynamic> evaluate(String source);
}

/// Assets 读取抽象（便于测试）
abstract class AssetsLoader {
  Future<String> loadString(String path);
}

class _RootBundleAssetsLoader implements AssetsLoader {
  @override
  Future<String> loadString(String path) => rootBundle.loadString(path);
}

class VideoNotFoundException implements Exception {
  @override
  String toString() => '未检测到可同步的视频元素';
}

class VTInjector {
  final JsEvaluator js;
  final AssetsLoader assets;
  final Duration pollInterval;
  final int maxAttempts;

  VTInjector({
    required this.js,
    AssetsLoader? assets,
    this.pollInterval = const Duration(milliseconds: 500),
    this.maxAttempts = 20,
  }) : assets = assets ?? _RootBundleAssetsLoader();

  /// 轮询直到 <video> 出现，然后注入 VT JS
  Future<void> waitForVideoAndInject() async {
    for (var i = 0; i < maxAttempts; i++) {
      final has = await js.evaluate('!!document.querySelector("video")');
      if (has == true) {
        final vtJs = await assets.loadString('assets/vt-client.js');
        await js.evaluate(vtJs);
        return;
      }
      await Future.delayed(pollInterval);
    }
    throw VideoNotFoundException();
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```powershell
flutter test test/webview/vt_injector_test.dart
```
Expected: PASS（2 个测试全过）

- [ ] **Step 5: Commit**

```powershell
git add lib/webview/vt_injector.dart test/webview/vt_injector_test.dart
git commit -m "feat: VT JS 注入逻辑（轮询等 video + 注入）"
```

---

## Task 8: VT Bridge 真实实现

**Files:**
- Create: `lib/vt/vt_webview_bridge.dart`

**说明**：把 VTBridge 接口用 AppWebViewController + VTInjector 真正实现。靠 Task 13 集成测试验证。

- [ ] **Step 1: 实现 `lib/vt/vt_webview_bridge.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';
import 'package:videotogether/webview/app_webview_controller.dart';
import 'package:videotogether/webview/vt_injector.dart';

/// VTBridge 的 WebView 实现
class VTWebViewBridge implements VTBridge {
  final AppWebViewController webview;
  final VTInjector injector;
  final StreamController<VTEvent> _events = StreamController.broadcast();
  String? _currentRoomId;
  bool _injected = false;

  VTWebViewBridge({required this.webview, required this.injector}) {
    // 注册 Dart 侧 handler，VT JS 通过 callHandler('onVTEvent', json) 回调
    webview.registerHandler('onVTEvent', (args) async {
      if (args.isEmpty) return;
      final raw = args.first;
      if (raw is String) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _events.add(VTEvent.fromJson(json));
        } catch (_) {}
      } else if (raw is Map) {
        _events.add(VTEvent.fromJson(raw.cast()));
      }
    });
  }

  @override
  Stream<VTEvent> get events => _events.stream;

  /// 在网页加载完后调用：注入 VT JS
  Future<void> onPageLoaded() async {
    if (_injected) return;
    await injector.waitForVideoAndInject();
    _injected = true;
  }

  Future<dynamic> _call(String js) async {
    return webview.evaluateJavascript(js);
  }

  @override
  Future<Room> createRoom({required String name}) async {
    final result = await _call(
      'window.VideoTogether.createRoom(${jsonEncode(name)})',
    );
    // 假设返回 {id: "...", name: "..."}
    final map = (result is String ? jsonDecode(result) : result) as Map;
    _currentRoomId = map['id'] as String;
    return Room(
      id: _currentRoomId!,
      name: map['name'] as String? ?? name,
      members: const [],
    );
  }

  @override
  Future<Room> joinRoom({required String roomId, required String name}) async {
    final result = await _call(
      'window.VideoTogether.joinRoom(${jsonEncode(roomId)}, ${jsonEncode(name)})',
    );
    if (result == null) {
      throw RoomNotFoundException(roomId);
    }
    final map = (result is String ? jsonDecode(result) : result) as Map;
    _currentRoomId = roomId;
    return Room(
      id: roomId,
      name: map['name'] as String? ?? '',
      members: const [],
    );
  }

  @override
  Future<void> leaveRoom(String roomId) async {
    await _call('window.VideoTogether.leaveRoom()');
    _currentRoomId = null;
  }

  @override
  Future<void> pause(String roomId) async {
    await _call('window.VideoTogether.pause()');
  }

  @override
  Future<void> play(String roomId) async {
    await _call('window.VideoTogether.play()');
  }

  @override
  Future<void> seek(String roomId, double seconds) async {
    await _call('window.VideoTogether.seek($seconds)');
  }

  @override
  Future<void> sendMessage(String roomId, String text) async {
    await _call(
      'window.VideoTogether.sendMessage(${jsonEncode(text)})',
    );
  }

  @override
  void dispose() {
    _events.close();
  }
}
```

- [ ] **Step 2: 静态分析**

Run:
```powershell
flutter analyze lib/vt/vt_webview_bridge.dart
```
Expected: 无 error

- [ ] **Step 3: Commit**

```powershell
git add lib/vt/vt_webview_bridge.dart
git commit -m "feat: VT WebView Bridge 真实实现"
```

---

## Task 9: 房间状态管理

**Files:**
- Create: `lib/state/room_store.dart`
- Test: `test/state/room_store_test.dart`

- [ ] **Step 1: 写失败测试 `test/state/room_store_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  test('createRoom 后 store 处于 inRoom 状态', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    expect(store.state, RoomStoreState.inRoom);
    expect(store.room?.name, 'test');
  });

  test('joinRoom 不存在房间后 store 处于 error 状态', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.joinRoom(roomId: 'no-such', name: 'me');
    expect(store.state, RoomStoreState.error);
    expect(store.error, isA<RoomNotFoundException>());
  });

  test('收到 ChatMessageEvent 后消息列表增加', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    final me = Member(id: 'u1', name: 'me');
    bridge.bindMember(store.room!.id, me);

    final before = store.messages.length;
    await store.sendMessage('hello');
    // Fake bridge 同步发出事件，store 监听后应刷新
    await Future.delayed(Duration.zero);
    expect(store.messages.length, before + 1);
  });

  test('leaveRoom 后 store 回到 idle', () async {
    final bridge = FakeVTBridge();
    final store = RoomStore(bridge: bridge);
    await store.createRoom(name: 'test');
    await store.leaveRoom();
    expect(store.state, RoomStoreState.idle);
    expect(store.room, isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```powershell
flutter test test/state/room_store_test.dart
```
Expected: FAIL（`room_store.dart` 不存在）

- [ ] **Step 3: 实现 `lib/state/room_store.dart`**

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_events.dart';
import 'package:videotogether/vt/vt_models.dart';

enum RoomStoreState { idle, loading, inRoom, error }

class RoomStore extends ChangeNotifier {
  final VTBridge _bridge;
  StreamSubscription<VTEvent>? _eventSub;

  RoomStoreState _state = RoomStoreState.idle;
  Room? _room;
  Object? _error;
  final List<ChatMessage> _messages = [];

  RoomStore({required VTBridge bridge}) : _bridge = bridge {
    _eventSub = _bridge.events.listen(_handleEvent);
  }

  RoomStoreState get state => _state;
  Room? get room => _room;
  Object? get error => _error;
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> createRoom({required String name}) async {
    _state = RoomStoreState.loading;
    _error = null;
    notifyListeners();
    try {
      _room = await _bridge.createRoom(name: name);
      _state = RoomStoreState.inRoom;
    } catch (e) {
      _error = e;
      _state = RoomStoreState.error;
    }
    notifyListeners();
  }

  Future<void> joinRoom({required String roomId, required String name}) async {
    _state = RoomStoreState.loading;
    _error = null;
    notifyListeners();
    try {
      _room = await _bridge.joinRoom(roomId: roomId, name: name);
      _state = RoomStoreState.inRoom;
    } catch (e) {
      _error = e;
      _state = RoomStoreState.error;
    }
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    if (_room == null) return;
    await _bridge.leaveRoom(_room!.id);
    _room = null;
    _messages.clear();
    _state = RoomStoreState.idle;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_room == null) return;
    await _bridge.pause(_room!.id);
  }

  Future<void> play() async {
    if (_room == null) return;
    await _bridge.play(_room!.id);
  }

  Future<void> seek(double seconds) async {
    if (_room == null) return;
    await _bridge.seek(_room!.id, seconds);
  }

  Future<void> sendMessage(String text) async {
    if (_room == null || text.trim().isEmpty) return;
    await _bridge.sendMessage(_room!.id, text);
  }

  void _handleEvent(VTEvent event) {
    switch (event) {
      case ChatMessageEvent(:final message):
        _messages.add(message);
        notifyListeners();
      case MemberJoinedEvent(:final member):
        _room = _room?.copyWith(members: [...?_room?.members, member]);
        notifyListeners();
      case MemberLeftEvent(:final memberId):
        _room = _room?.copyWith(
          members: _room?.members.where((m) => m.id != memberId).toList() ?? [],
        );
        notifyListeners();
      default:
        // 播放/暂停/跳转事件由 VT JS 直接控制 WebView 内 video，无需 store 处理
        break;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```powershell
flutter test test/state/room_store_test.dart
```
Expected: PASS（4 个测试全过）

- [ ] **Step 5: Commit**

```powershell
git add lib/state/room_store.dart test/state/room_store_test.dart
git commit -m "feat: 房间状态管理 RoomStore"
```

---

## Task 10: 首页 UI

**Files:**
- Create: `lib/ui/home_page.dart`

**说明**：首页有"粘贴视频网址"+"创建房间 / 加入房间"两个入口。不写 widget 测试（UI 层手动验证更快）。

- [ ] **Step 1: 实现 `lib/ui/home_page.dart`**

```dart
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
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

class _HomePageState extends State<HomePage> {
  final _urlCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(text: '匿名');
  bool _joining = false;
  bool _busy = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _roomCtrl.dispose();
    _nameCtrl.dispose();
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
    setState(() => _busy = true);
    await widget.onStart(
      url: url,
      create: create,
      roomId: _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
      nickname: name,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('异地同看')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '视频网址',
                hintText: '粘贴 B站/YouTube 等视频网页地址',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _joining,
              title: const Text('我要加入已有房间'),
              onChanged: (v) => setState(() => _joining = v ?? false),
            ),
            if (_joining)
              TextField(
                controller: _roomCtrl,
                decoration: const InputDecoration(
                  labelText: '房间号',
                  border: OutlineInputBorder(),
                ),
              ),
            const Spacer(),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _start(create: !_joining),
              child: Text(_busy
                  ? '进入中...'
                  : (_joining ? '加入房间' : '创建房间')),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 静态分析**

Run:
```powershell
flutter analyze lib/ui/home_page.dart
```
Expected: 无 error

- [ ] **Step 3: Commit**

```powershell
git add lib/ui/home_page.dart
git commit -m "feat: 首页 UI（粘贴网址 + 创建/加入房间）"
```

---

## Task 11: 顶栏 UI

**Files:**
- Create: `lib/ui/room_bar.dart`

- [ ] **Step 1: 实现 `lib/ui/room_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:videotogether/vt/vt_models.dart';

class RoomBar extends StatelessWidget {
  final Room room;
  final VoidCallback onLeave;

  const RoomBar({super.key, required this.room, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black87,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '房间号: ${room.id}  ·  成员 ${room.memberCount}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: '复制房间号',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: room.id));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('房间号已复制')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: '离开房间',
            onPressed: onLeave,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 静态分析**

Run:
```powershell
flutter analyze lib/ui/room_bar.dart
```
Expected: 无 error

- [ ] **Step 3: Commit**

```powershell
git add lib/ui/room_bar.dart
git commit -m "feat: 顶栏 UI（房间号/成员/复制/离开）"
```

---

## Task 12: 聊天浮层 UI

**Files:**
- Create: `lib/ui/chat_overlay.dart`
- Test: `test/ui/chat_overlay_test.dart`

- [ ] **Step 1: 写失败测试 `test/ui/chat_overlay_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videotogether/ui/chat_overlay.dart';
import 'package:videotogether/vt/vt_models.dart';

void main() {
  testWidgets('点击图标展开聊天面板', (tester) async {
    final messages = <ChatMessage>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatOverlay(
          messages: messages,
          onSend: (_) {},
        ),
      ),
    ));
    // 初始为收起态：floating button
    expect(find.byIcon(Icons.chat), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat));
    await tester.pumpAndSettle();
    // 展开后有输入框
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('输入文字点发送触发 onSend', (tester) async {
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatOverlay(
          messages: const [],
          onSend: (text) => sent = text,
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.chat));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send));
    expect(sent, 'hello');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```powershell
flutter test test/ui/chat_overlay_test.dart
```
Expected: FAIL（`chat_overlay.dart` 不存在）

- [ ] **Step 3: 实现 `lib/ui/chat_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:videotogether/vt/vt_models.dart';

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

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

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
          child: const Icon(Icons.chat),
          onPressed: () => setState(() => _expanded = true),
        ),
      );
    }
    return Positioned(
      right: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.7,
      height: MediaQuery.of(context).size.height * 0.5,
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('聊天', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _expanded = false),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.messages.length,
                itemBuilder: (ctx, i) {
                  final m = widget.messages[i];
                  return ListTile(
                    dense: true,
                    title: Text(m.text),
                    subtitle: Text(m.from.name,
                        style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '发消息...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
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
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```powershell
flutter test test/ui/chat_overlay_test.dart
```
Expected: PASS（2 个测试全过）

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/chat_overlay.dart test/ui/chat_overlay_test.dart
git commit -m "feat: 聊天浮层 UI"
```

---

## Task 13: 观影页（组合 WebView + 顶栏 + 聊天浮层）

**Files:**
- Create: `lib/ui/watch_page.dart`

- [ ] **Step 1: 实现 `lib/ui/watch_page.dart`**

```dart
import 'package:flutter/material.dart';
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

  const WatchPage({super.key, required this.videoUrl, required this.nickname});

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  late final AppWebViewController _webviewCtrl;
  late final VTWebViewBridge _bridge;
  late final VTInjector _injector;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _webviewCtrl = AppWebViewController();
    _injector = VTInjector(
      js: _JsAdapter(_webviewCtrl),
    );
    _bridge = VTWebViewBridge(webview: _webviewCtrl, injector: _injector);
    // 把 bridge 接到 store
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomStore>(); // store 由上层提供
    });
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶栏
          Consumer<RoomStore>(
            builder: (ctx, store, _) {
              if (store.room == null) {
                return const SizedBox.shrink();
              }
              return RoomBar(
                room: store.room!,
                onLeave: () async {
                  await store.leaveRoom();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              );
            },
          ),
          // WebView 铺满剩余空间
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
                    try {
                      await _bridge.onPageLoaded();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('同步注入失败: $e')),
                        );
                      }
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
                // 聊天浮层
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

/// 把 AppWebViewController 适配成 JsEvaluator
class _JsAdapter implements JsEvaluator {
  final AppWebViewController _ctrl;
  _JsAdapter(this._ctrl);

  @override
  Future<dynamic> evaluate(String source) async {
    return _ctrl.evaluateJavascript(source);
  }
}
```

注：此处 `JsEvaluator` 需从 `vt_injector.dart` import。如 `flutter_inappwebview` 6.x 的 `InAppWebView` widget 与 `URLRequest` API 名有差异，按实际版本调整。

- [ ] **Step 2: 添加 provider 依赖**

修改 `pubspec.yaml`：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.0.0
  provider: ^6.1.0
```

Run:
```powershell
flutter pub get
```

- [ ] **Step 3: 静态分析**

Run:
```powershell
flutter analyze lib/ui/watch_page.dart
```
Expected: 无 error

- [ ] **Step 4: Commit**

```powershell
git add lib/ui/watch_page.dart pubspec.yaml pubspec.lock
git commit -m "feat: 观影页组合（WebView + 顶栏 + 聊天浮层）"
```

---

## Task 14: App 入口与路由

**Files:**
- Modify: `lib/main.dart`
- Create: `lib/app.dart`

- [ ] **Step 1: 实现 `lib/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:videotogether/state/room_store.dart';
import 'package:videotogether/ui/home_page.dart';
import 'package:videotogether/ui/watch_page.dart';
import 'package:videotogether/vt/vt_bridge.dart';
import 'package:videotogether/vt/vt_webview_bridge.dart';
import 'package:videotogether/webview/app_webview_controller.dart';
import 'package:videotogether/webview/vt_injector.dart';

class VideoTogetherApp extends StatelessWidget {
  const VideoTogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => _buildStore(),
      child: MaterialApp(
        title: '异地同看',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: HomePage(
          onStart: ({
            required String url,
            required bool create,
            String? roomId,
            required String nickname,
          }) async {
            final store = context.read<RoomStore>();
            if (create) {
              await store.createRoom(name: nickname);
            } else {
              await store.joinRoom(roomId: roomId ?? '', name: nickname);
            }
            if (!context.mounted) return;
            if (store.state == RoomStoreState.inRoom) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    WatchPage(videoUrl: url, nickname: nickname),
              ));
            }
          },
        ),
      ),
    );
  }

  /// 真实 App 用 VTWebViewBridge；测试时由测试代码注入 FakeVTBridge
  RoomStore _buildStore() {
    final webview = AppWebViewController();
    final injector = VTInjector(js: _JsAdapter(webview));
    final bridge = VTWebViewBridge(webview: webview, injector: injector);
    return RoomStore(bridge: bridge);
  }
}

class _JsAdapter implements JsEvaluator {
  final AppWebViewController _ctrl;
  _JsAdapter(this._ctrl);
  @override
  Future<dynamic> evaluate(String source) => _ctrl.evaluateJavascript(source);
}
```

- [ ] **Step 2: 改写 `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:videotogether/app.dart';

void main() => runApp(const VideoTogetherApp());
```

- [ ] **Step 3: 跑通 App**

Run:
```powershell
flutter run -d windows
```
Expected: 首页显示，能进入观影页（不连真实服务器也能跑 UI）

- [ ] **Step 4: Commit**

```powershell
git add lib/main.dart lib/app.dart
git commit -m "feat: App 入口与路由"
```

---

## Task 15: 双端集成验证（手动）

**Files:**
- 无新增文件

**说明**：跑两个模拟器或一台真机 + 一个模拟器，开同一房间验证同步。

- [ ] **Step 1: 启动两个 Android 模拟器**

Run:
```powershell
flutter devices
```
Expected: 列出至少 2 个可用设备

- [ ] **Step 2: 设备 A 创建房间**

- 在设备 A 上 `flutter run -d <deviceA>`
- 粘贴一个 B站视频网址（如 `https://www.bilibili.com/video/BV1xx411c7mD`）
- 输入昵称"A"，点"创建房间"
- 记录房间号

- [ ] **Step 3: 设备 B 加入房间**

- 在设备 B 上 `flutter run -d <deviceB>`
- 粘贴同一视频网址
- 勾选"加入房间"，输入 A 的房间号
- 输入昵称"B"，点"加入房间"

- [ ] **Step 4: 验证同步**

- A 点播放 → B 也播放
- A 点暂停 → B 也暂停
- A 拉进度条到 5:00 → B 也跳到 5:00
- A 发文字"hi" → B 收到"hi"

- [ ] **Step 5: 记录验证结果**

在 `docs/notes/integration-test-<date>.md` 记录通过/失败项。

- [ ] **Step 6: Commit**

```powershell
git add docs/notes/integration-test-*.md
git commit -m "test: 双端集成验证记录"
```

---

## Task 16: 站点适配测试矩阵（手动）

**Files:**
- Create: `docs/notes/site-compat-<date>.md`

按 spec §8.1 矩阵逐站测试，记录结果：

- [ ] **Step 1: B站测试**

粘贴 `https://www.bilibili.com/video/...`，验证同步。记录：✅/⚠️/❌ + 备注

- [ ] **Step 2: YouTube 测试**

粘贴 `https://www.youtube.com/watch?v=...`，验证同步。

- [ ] **Step 3: 腾讯视频测试**

粘贴 `https://v.qq.com/x/cover/...`，验证同步。如失败，记录失败点（DRM/iframe/UA）。

- [ ] **Step 4: 优酷测试**

粘贴 `https://v.youku.com/...`，验证同步。

- [ ] **Step 5: 本地 mp4 基准测试**

起一个本地 HTTP 服务放一个 mp4，App 打开 `http://localhost:8080/test.mp4`，验证同步（这是基准，必须通过）。

- [ ] **Step 6: 记录到 `docs/notes/site-compat-<date>.md` 并 Commit**

```powershell
git add docs/notes/site-compat-*.md
git commit -m "test: 站点适配测试矩阵结果"
```

---

## Self-Review

### 1. Spec 覆盖检查

| Spec 需求 | 对应 Task |
|---|---|
| F1 粘贴网址进入观影页 | Task 10, 13 |
| F2 创建房间 | Task 5, 8, 9, 14 |
| F3 加入房间 | Task 5, 8, 9, 14 |
| F4 视频同步（播放/暂停/跳转/倍速） | Task 8（VT JS 自动处理）+ Task 15 验证 |
| F5 文字聊天 | Task 5, 9, 12 |
| F6 顶栏（房间号/成员/邀请） | Task 11 |
| F7 离开房间 | Task 9, 11, 13 |
| 双端 Android + iOS | Task 1 配置 + Task 15 验证（iOS 需另外在 Mac 上跑） |
| 关键技术点：反爬 | Task 6（UA 伪装）+ Task 13（URL 拦截） |
| 关键技术点：VT JS 注入时机 | Task 7 |
| 关键技术点：VT JS 自打包进 assets | Task 2 |
| 错误处理：网页加载失败 | Task 13 onLoadStop 异常捕获 + SnackBar |
| 错误处理：VT 服务器连不上 | VT JS 内部处理，UI 层暂未做黄条提示（已知 gap） |
| 错误处理：找不到 video | Task 7 VideoNotFoundException |
| 测试策略 | Task 3,4,5,7,9,12 单元测试 + Task 15 集成 + Task 16 站点矩阵 |

**已知 gap**：错误处理中"VT 服务器连不上时顶栏黄条提示"未单独做任务。VT 服务器不可用时 VT JS 自身会断连重试，UI 层若要加黄条需监听 `bridge.events` 的连接状态事件。MVP 阶段先不做，留作迭代项。

### 2. 占位符扫描

- Task 0 的"按实际调整路径"是必要的灵活性（VT 仓库结构需运行时确认），不是占位符
- Task 2 末尾的 Dart 桥接代码注明"按 Task 0 记录调整"——同上
- 其余步骤均有完整代码

### 3. 类型一致性

- `RoomStore` 在 Task 9 定义的方法名（createRoom/joinRoom/leaveRoom/pause/play/seek/sendMessage）与 Task 5 的 VTBridge 接口一致
- `VTEvent` 子类名（PausedEvent/PlayedEvent/SeekedEvent/MemberJoinedEvent/MemberLeftEvent/ChatMessageEvent）在 Task 4 定义，Task 9 `_handleEvent` 引用一致
- `JsEvaluator.evaluate` 在 Task 7 定义，Task 13 `_JsAdapter` 实现一致
- `AppWebViewController` 方法名（attach/loadUrl/evaluateJavascript/registerHandler）在 Task 6 定义，Task 8/13 引用一致

类型一致性 OK。

---

## 执行选择

计划已保存到 `docs/superpowers/plans/2026-07-27-videotogether-mobile-app.md`。两种执行方式：

1. **Subagent 驱动（推荐）**：每个 Task 派一个新子代理执行，任务间我做 review，迭代快、上下文干净
2. **当前会话内执行**：在当前对话里逐任务执行，带 checkpoint 复核

选哪种？
