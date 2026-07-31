// ==UserScript==
// @name         VtLite 一起看
// @namespace    https://github.com/avideotogether/vt-lite
// @version      1.0.0
// @description  异地同看视频 - 在任意视频页面注入同步控件，跟 Android App / PWA 互通
// @author       avideotogether
// @match        *://*/*
// @grant        none
// @run-at       document-idle
// @license      MIT
// ==/UserScript==

(function () {
  "use strict";

  // 防止重复注入
  if (window.__VtLiteUserScript) return;
  window.__VtLiteUserScript = true;

  // ============ 配置 ============
  var API_HOST = "https://vt.panghair.com:5000";
  var WS_URLS = [
    "wss://vt.panghair.com:5000/ws?language=zh-cn",
    "wss://dogyun.2gether.video/ws?language=zh-cn"
  ];
  var ROLE = { NULL: "null", MASTER: "master", MEMBER: "member" };

  // ============ 状态 ============
  var ws = null;
  var wsReady = false;
  var timeOffset = 0;
  var roomName = "";
  var password = "";
  var role = ROLE.NULL;
  var memberCount = 0;
  var masterTimer = null;
  var videoElement = null;
  var intentionalClose = false;
  var destroyed = false;
  var tempUser = "vt_" + Date.now() + "_" + uuid();
  var listeners = {};
  var messages = []; // 聊天消息缓存

  // ============ 工具函数 ============
  function uuid() {
    try {
      if (typeof crypto !== "undefined" && crypto.randomUUID) {
        return crypto.randomUUID();
      }
    } catch (e) {}
    return "xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      var v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function on(event, cb) {
    if (typeof cb !== "function") return;
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(cb);
  }

  function off(event, cb) {
    if (!listeners[event]) return;
    listeners[event] = listeners[event].filter(function (fn) { return fn !== cb; });
  }

  function emit(event, data) {
    var cbs = listeners[event];
    if (cbs) {
      cbs.slice().forEach(function (cb) {
        try { cb(data); } catch (e) {}
      });
    }
  }

  function send(obj) {
    if (ws && ws.readyState === 1) {
      try { ws.send(JSON.stringify(obj)); } catch (e) {}
    }
  }

  async function syncTime() {
    try {
      var resp = await fetch(API_HOST + "/timestamp");
      var r = await resp.json();
      if (r && typeof r.timestamp === "number") {
        timeOffset = r.timestamp - Date.now() / 1000;
      }
    } catch (e) {
      emit("error", { message: "sync_time_failed", error: String(e) });
    }
  }

  // ============ WebSocket 消息处理 ============
  function handleWsMessage(raw) {
    var lines = String(raw).split("\n");
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line) continue;
      var msg;
      try { msg = JSON.parse(line); } catch (e) { continue; }
      if (!msg || !msg.method) continue;
      var data = msg.data || {};
      if (msg.method === "/room/update" ||
          msg.method === "/room/update_member" ||
          msg.method === "/room/join") {
        if (typeof data.memberCount === "number") memberCount = data.memberCount;
        emit("room_update", data);
      } else if (msg.method === "send_txtmsg") {
        messages.push({
          text: data.msg || "",
          id: data.id || uuid(),
          ts: Date.now()
        });
        emit("text_message", data);
      }
    }
  }

  function connectWs(urlIndex) {
    if (destroyed) return;
    if (typeof urlIndex !== "number") urlIndex = 0;
    if (urlIndex >= WS_URLS.length) {
      emit("error", { message: "ws_all_urls_failed" });
      return;
    }
    try {
      ws = new WebSocket(WS_URLS[urlIndex]);
    } catch (e) {
      emit("error", { message: "ws_construct_failed", error: String(e) });
      return;
    }
    ws.onopen = function () {
      wsReady = true;
      emit("ws_open", {});
      if (role === ROLE.MEMBER && roomName) {
        send({ method: "/room/join", data: { name: roomName, password: password } });
      }
    };
    ws.onmessage = function (e) {
      try { handleWsMessage(e.data); } catch (err) {
        emit("error", { message: "ws_message_handler_error", error: String(err) });
      }
    };
    ws.onerror = function () {};
    ws.onclose = function () {
      var wasReady = wsReady;
      var wasIntentional = intentionalClose;
      intentionalClose = false;
      ws = null;
      wsReady = false;
      if (wasIntentional) return;
      if (!wasReady && urlIndex + 1 < WS_URLS.length) {
        connectWs(urlIndex + 1);
        return;
      }
      emit("ws_close", { wasOpen: wasReady });
    };
  }

  // ============ 房主上报循环 ============
  function startMasterTimer() {
    stopMasterTimer();
    masterTimer = setInterval(function () {
      if (role !== ROLE.MASTER || !videoElement) return;
      var v = videoElement;
      var currentTime = 0, paused = true, playbackRate = 1, duration = 0;
      try {
        currentTime = v.currentTime || 0;
        paused = !!v.paused;
        playbackRate = v.playbackRate || 1;
        duration = v.duration || 0;
      } catch (e) { return; }
      send({
        method: "/room/update",
        data: {
          tempUser: tempUser,
          password: password,
          name: roomName,
          playbackRate: playbackRate,
          currentTime: currentTime,
          paused: paused,
          url: (typeof location !== "undefined" && location.href) || "",
          lastUpdateClientTime: Date.now() / 1000 + timeOffset,
          duration: duration,
          protected: !!password,
          videoTitle: (typeof document !== "undefined" && document.title) || "",
          sendLocalTimestamp: Date.now() / 1000,
          m3u8Url: ""
        }
      });
    }, 2000);
  }

  function stopMasterTimer() {
    if (masterTimer) {
      try { clearInterval(masterTimer); } catch (e) {}
      masterTimer = null;
    }
  }

  // ============ 成员同步逻辑 ============
  on("room_update", function (room) {
    if (role !== ROLE.MEMBER || !videoElement || !room) return;
    var v = videoElement;
    try {
      var realCurrent = room.currentTime +
        (Date.now() / 1000 + timeOffset -
          (room.lastUpdateServerTime || 0)) * (room.playbackRate || 1);
      if (typeof v.currentTime === "number" &&
          Math.abs(v.currentTime - realCurrent) > 1) {
        v.currentTime = realCurrent;
      }
      if (v.paused !== !!room.paused) {
        if (room.paused) {
          try { v.pause(); } catch (e) {}
        } else {
          try { v.play().catch(function () {}); } catch (e) {}
        }
      }
      if (typeof room.playbackRate === "number" &&
          v.playbackRate !== room.playbackRate) {
        try { v.playbackRate = room.playbackRate; } catch (e) {}
      }
    } catch (e) {
      emit("error", { message: "member_sync_error", error: String(e) });
    }
  });

  // ============ 公开 API ============
  async function createRoom(name, pwd, videoEl) {
    if (!name) throw new Error("房间名必填");
    stopMasterTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MASTER;
    videoElement = videoEl || null;
    memberCount = 1;
    await syncTime();
    if (!ws) connectWs(0);
    startMasterTimer();
  }

  async function joinRoom(name, pwd, videoEl) {
    if (!name) throw new Error("房间名必填");
    stopMasterTimer();
    roomName = String(name);
    password = String(pwd || "");
    role = ROLE.MEMBER;
    videoElement = videoEl || null;
    memberCount = 0;
    await syncTime();
    if (!ws) connectWs(0);
    send({ method: "/room/join", data: { name: roomName, password: password } });
  }

  function leaveRoom() {
    intentionalClose = true;
    stopMasterTimer();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null;
    wsReady = false;
    roomName = "";
    password = "";
    role = ROLE.NULL;
    memberCount = 0;
  }

  function sendText(msg) {
    if (!ws || !wsReady) {
      emit("error", { message: "ws_not_open" });
      return;
    }
    send({
      method: "send_txtmsg",
      data: { msg: String(msg), id: uuid(), voiceId: "" }
    });
  }

  function getState() {
    return {
      role: role,
      roomName: roomName,
      wsOpen: !!wsReady,
      memberCount: memberCount
    };
  }

  function destroy() {
    destroyed = true;
    intentionalClose = true;
    stopMasterTimer();
    if (ws) { try { ws.close(); } catch (e) {} }
    ws = null;
    wsReady = false;
    roomName = "";
    password = "";
    role = ROLE.NULL;
    memberCount = 0;
    videoElement = null;
    Object.keys(listeners).forEach(function (k) { delete listeners[k]; });
  }

  // 暴露到 window 方便调试
  window.VtLite = {
    on: on, off: off,
    createRoom: createRoom, joinRoom: joinRoom,
    leaveRoom: leaveRoom, sendText: sendText,
    getState: getState, destroy: destroy
  };

  // ============ 自动寻找 video 元素 ============
  // 在 B 站/YouTube/腾讯等站点上，视频元素可能在页面加载后才出现
  function findVideoElement() {
    // 优先找 main video
    var v = document.querySelector("video");
    if (v) return v;
    // YouTube 特殊处理
    var yt = document.querySelector(".html5-main-video");
    if (yt) return yt;
    // B 站特殊处理
    var bili = document.querySelector("#bilibili-player video");
    if (bili) return bili;
    return null;
  }

  // 等 video 元素出现（最多等 30 秒）
  function waitForVideo(cb) {
    var tries = 0;
    function check() {
      var v = findVideoElement();
      if (v) { cb(v); return; }
      tries++;
      if (tries > 60) { // 30 秒
        cb(null);
        return;
      }
      setTimeout(check, 500);
    }
    check();
  }

  // ============ UI 面板 ============
  // 样式注入
  function injectStyles() {
    var css = `
.vtl-panel {
  position: fixed;
  bottom: 16px;
  right: 16px;
  z-index: 2147483647;
  width: 300px;
  background: #F7F5F2;
  border: 1px solid #D4C8B8;
  border-radius: 4px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.12);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 13px;
  color: #2C2418;
  overflow: hidden;
}
.vtl-header {
  padding: 10px 12px;
  background: #8B7355;
  color: #F7F5F2;
  cursor: pointer;
  display: flex;
  justify-content: space-between;
  align-items: center;
  user-select: none;
}
.vtl-header-title {
  font-weight: 600;
  letter-spacing: 0.5px;
}
.vtl-header-status {
  font-size: 11px;
  opacity: 0.85;
}
.vtl-body {
  padding: 12px;
  display: block;
}
.vtl-body.collapsed {
  display: none;
}
.vtl-field {
  margin-bottom: 8px;
}
.vtl-field label {
  display: block;
  font-size: 11px;
  color: #8B7355;
  margin-bottom: 4px;
  letter-spacing: 0.3px;
}
.vtl-field input {
  width: 100%;
  box-sizing: border-box;
  padding: 6px 8px;
  border: 1px solid #D4C8B8;
  border-radius: 3px;
  background: #FFFFFF;
  color: #2C2418;
  font-size: 13px;
  font-family: inherit;
}
.vtl-field input:focus {
  outline: none;
  border-color: #8B7355;
}
.vtl-btn {
  width: 100%;
  padding: 8px;
  background: #2C2418;
  color: #F7F5F2;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  font-size: 13px;
  font-family: inherit;
  letter-spacing: 0.5px;
}
.vtl-btn:disabled {
  background: #C4B8A8;
  cursor: not-allowed;
}
.vtl-tab-row {
  display: flex;
  margin-bottom: 10px;
  border-bottom: 1px solid #D4C8B8;
}
.vtl-tab {
  flex: 1;
  padding: 6px;
  text-align: center;
  cursor: pointer;
  color: #8B7355;
  font-size: 12px;
  border-bottom: 2px solid transparent;
}
.vtl-tab.active {
  color: #2C2418;
  border-bottom-color: #8B7355;
  font-weight: 600;
}
.vtl-msgs {
  max-height: 160px;
  overflow-y: auto;
  padding: 6px;
  background: #FFFFFF;
  border: 1px solid #E8DFD0;
  border-radius: 3px;
  margin-bottom: 8px;
  font-size: 12px;
}
.vtl-msg {
  margin-bottom: 4px;
  word-wrap: break-word;
}
.vtl-msg-meta {
  font-size: 10px;
  color: #8B7355;
  margin-right: 6px;
}
.vtl-chat-input {
  display: flex;
  gap: 4px;
}
.vtl-chat-input input {
  flex: 1;
  padding: 5px 8px;
  border: 1px solid #D4C8B8;
  border-radius: 3px;
  font-size: 12px;
  font-family: inherit;
}
.vtl-chat-input button {
  padding: 5px 10px;
  background: #8B7355;
  color: #F7F5F2;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  font-size: 12px;
}
.vtl-info {
  font-size: 11px;
  color: #8B7355;
  margin-top: 6px;
  line-height: 1.5;
}
.vtl-error {
  color: #B8431D;
  font-size: 11px;
  margin-top: 4px;
}
`;
    var style = document.createElement("style");
    style.textContent = css;
    document.head.appendChild(style);
  }

  // 构建 UI
  function buildPanel() {
    var panel = document.createElement("div");
    panel.className = "vtl-panel";
    panel.innerHTML = `
      <div class="vtl-header" id="vtlHeader">
        <span class="vtl-header-title">一起看</span>
        <span class="vtl-header-status" id="vtlStatus">未连接</span>
      </div>
      <div class="vtl-body" id="vtlBody">
        <div class="vtl-tab-row">
          <div class="vtl-tab active" data-tab="create">创建房间</div>
          <div class="vtl-tab" data-tab="join">加入房间</div>
        </div>
        <div class="vtl-field">
          <label>昵称</label>
          <input type="text" id="vtlName" placeholder="你的昵称" />
        </div>
        <div class="vtl-field">
          <label>房间名</label>
          <input type="text" id="vtlRoom" placeholder="房间名" />
        </div>
        <div class="vtl-field">
          <label>密码（可选）</label>
          <input type="password" id="vtlPwd" placeholder="留空表示无密码" />
        </div>
        <button class="vtl-btn" id="vtlAction">创建房间</button>
        <div class="vtl-info" id="vtlInfo"></div>
        <div class="vtl-error" id="vtlError"></div>
        <hr style="border:none;border-top:1px solid #E8DFD0;margin:10px 0;" />
        <div class="vtl-msgs" id="vtlMsgs"></div>
        <div class="vtl-chat-input">
          <input type="text" id="vtlChatInput" placeholder="发消息..." />
          <button id="vtlChatSend">发送</button>
        </div>
      </div>
    `;
    document.body.appendChild(panel);

    // 折叠/展开
    var body = panel.querySelector("#vtlBody");
    var header = panel.querySelector("#vtlHeader");
    var collapsed = false;
    header.addEventListener("click", function () {
      collapsed = !collapsed;
      body.style.display = collapsed ? "none" : "block";
    });

    // Tab 切换
    var currentTab = "create";
    var tabs = panel.querySelectorAll(".vtl-tab");
    var actionBtn = panel.querySelector("#vtlAction");
    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        tabs.forEach(function (t) { t.classList.remove("active"); });
        tab.classList.add("active");
        currentTab = tab.dataset.tab;
        actionBtn.textContent = currentTab === "create" ? "创建房间" : "加入房间";
      });
    });

    // 创建/加入
    actionBtn.addEventListener("click", async function () {
      var name = panel.querySelector("#vtlName").value.trim();
      var room = panel.querySelector("#vtlRoom").value.trim();
      var pwd = panel.querySelector("#vtlPwd").value.trim();
      var errEl = panel.querySelector("#vtlError");
      errEl.textContent = "";

      if (!name) { errEl.textContent = "请输入昵称"; return; }
      if (!room) { errEl.textContent = "请输入房间名"; return; }

      actionBtn.disabled = true;
      actionBtn.textContent = "处理中...";

      var v = findVideoElement();
      if (!v) {
        errEl.textContent = "未找到视频元素，请先打开视频页面";
        actionBtn.disabled = false;
        actionBtn.textContent = currentTab === "create" ? "创建房间" : "加入房间";
        return;
      }

      try {
        if (currentTab === "create") {
          await createRoom(room, pwd, v);
        } else {
          await joinRoom(room, pwd, v);
        }
        panel.querySelector("#vtlInfo").textContent =
          (currentTab === "create" ? "已创建" : "已加入") + " 房间：" + room;
      } catch (e) {
        errEl.textContent = "失败：" + e.message;
      }
      actionBtn.disabled = false;
      actionBtn.textContent = currentTab === "create" ? "创建房间" : "加入房间";
    });

    // 发送消息
    function sendChat() {
      var input = panel.querySelector("#vtlChatInput");
      var text = input.value.trim();
      if (!text) return;
      // 本地昵称
      var name = panel.querySelector("#vtlName").value.trim() || "匿名";
      var full = "[" + name + "] " + text;
      sendText(full);
      // 本地回显
      messages.push({ text: full, id: uuid(), ts: Date.now(), self: true });
      renderMessages();
      input.value = "";
    }
    panel.querySelector("#vtlChatSend").addEventListener("click", sendChat);
    panel.querySelector("#vtlChatInput").addEventListener("keydown", function (e) {
      if (e.key === "Enter") sendChat();
    });

    // 状态更新
    on("ws_open", function () {
      panel.querySelector("#vtlStatus").textContent = "已连接";
    });
    on("ws_close", function () {
      panel.querySelector("#vtlStatus").textContent = "已断开";
    });
    on("room_update", function (data) {
      var count = data.memberCount || 0;
      panel.querySelector("#vtlStatus").textContent = "在线 " + count + " 人";
    });
    on("text_message", function () {
      renderMessages();
    });
    on("error", function (e) {
      if (e && e.message) {
        panel.querySelector("#vtlError").textContent = "错误：" + e.message;
      }
    });

    function renderMessages() {
      var box = panel.querySelector("#vtlMsgs");
      box.innerHTML = "";
      messages.slice(-50).forEach(function (m) {
        var div = document.createElement("div");
        div.className = "vtl-msg";
        var time = new Date(m.ts).toLocaleTimeString().slice(0, 5);
        div.innerHTML = '<span class="vtl-msg-meta">' + time + '</span>' +
          escapeHtml(m.text);
        box.appendChild(div);
      });
      box.scrollTop = box.scrollHeight;
    }

    function escapeHtml(s) {
      return String(s).replace(/[&<>"']/g, function (c) {
        return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
      });
    }
  }

  // ============ 启动 ============
  function start() {
    if (!document.body) {
      setTimeout(start, 200);
      return;
    }
    injectStyles();
    buildPanel();
  }

  // 等 DOM 就绪
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
