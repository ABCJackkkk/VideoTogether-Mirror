// app.js — 异地同看 PWA 主逻辑
// 依赖：window.VtLite（见 vt-lite.js）

(function () {
  "use strict";

  // ===== DOM 引用 =====
  const $ = (id) => document.getElementById(id);
  const homePage = $("homePage");
  const watchPage = $("watchPage");
  const topbar = $("topbar");
  const fileInput = $("fileInput");
  const fileDropHint = $("fileDropHint");
  const fileName = $("fileName");
  const urlInput = $("urlInput");
  const nicknameInput = $("nicknameInput");
  const roomNameInput = $("roomNameInput");
  const passwordInput = $("passwordInput");
  const joinCheckbox = $("joinCheckbox");
  const startBtn = $("startBtn");
  const videoStage = $("videoStage");
  const roomNameDisplay = $("roomNameDisplay");
  const memberCount = $("memberCount");
  const copyBtn = $("copyBtn");
  const leaveBtn = $("leaveBtn");
  const chatToggle = $("chatToggle");
  const chatPanel = $("chatPanel");
  const chatCloseBtn = $("chatCloseBtn");
  const chatMessages = $("chatMessages");
  const chatInput = $("chatInput");
  const chatSendBtn = $("chatSendBtn");
  const toastEl = $("toast");

  // ===== 状态 =====
  let videoEl = null;       // <video> 元素（mp4/本地文件）
  let ytIframe = null;      // YouTube iframe
  let ytPlayer = null;      // YouTube Player 实例
  let ytPoller = null;      // YouTube 状态轮询定时器
  let currentVideoSrc = null; // 'file' | 'url' | 'youtube'
  let selectedFile = null;
  let nickname = "";

  // ===== 工具 =====
  function showToast(msg, duration) {
    toastEl.textContent = msg;
    toastEl.classList.remove("hidden");
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => toastEl.classList.add("hidden"), duration || 2200);
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]));
  }

  // 解析 YouTube 视频ID（支持 youtu.be/xxx、watch?v=xxx、embed/xxx）
  function parseYouTubeId(url) {
    if (!url) return null;
    const m = url.match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|embed\/|shorts\/))([\w-]{11})/);
    return m ? m[1] : null;
  }

  // ===== 视频加载 =====
  function clearVideoStage() {
    videoStage.innerHTML = '<div class="placeholder">正在加载视频...</div>';
    if (videoEl) { try { videoEl.pause(); } catch (e) {} videoEl = null; }
    if (ytIframe) { if (ytIframe.parentNode) ytIframe.parentNode.removeChild(ytIframe); ytIframe = null; ytPlayer = null; }
    if (ytPoller) { clearInterval(ytPoller); ytPoller = null; }
  }

  // 加载本地文件 / mp4 直链
  function loadVideoElement(src) {
    clearVideoStage();
    const v = document.createElement("video");
    v.src = src;
    v.controls = true;
    v.playsInline = true;
    v.setAttribute("playsinline", "");
    v.style.width = "100%";
    v.style.height = "100%";
    v.style.objectFit = "contain";
    v.style.background = "#000";
    videoStage.innerHTML = "";
    videoStage.appendChild(v);
    videoEl = v;
    currentVideoSrc = src.startsWith("blob:") ? "file" : "url";
    return v;
  }

  // 加载 YouTube embed
  function loadYouTube(videoId) {
    clearVideoStage();
    const iframe = document.createElement("iframe");
    iframe.src = `https://www.youtube.com/embed/${videoId}?enablejsapi=1&playsinline=1`;
    iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture";
    iframe.allowFullscreen = true;
    videoStage.innerHTML = "";
    videoStage.appendChild(iframe);
    ytIframe = iframe;
    currentVideoSrc = "youtube";

    // 等待 YT API 准备好
    if (!window.YT) {
      const tag = document.createElement("script");
      tag.src = "https://www.youtube.com/iframe_api";
      document.head.appendChild(tag);
    }
    window.onYouTubeIframeAPIReady = window.onYouTubeIframeAPIReady || function () {};
    // 轮询创建 YT.Player
    let tries = 0;
    const wait = setInterval(() => {
      tries++;
      if (window.YT && window.YT.Player) {
        clearInterval(wait);
        ytPlayer = new YT.Player(iframe, {
          events: { onReady: () => {} }
        });
      } else if (tries > 50) {
        clearInterval(wait);
      }
    }, 200);
  }

  // YouTube 兼容的"假 video"对象，让 VtLite 能调用 play/pause/seek
  // VtLite 只读 currentTime/paused/playbackRate/duration，调用 play()/pause()
  function makeYoutubePseudoVideo() {
    return {
      get currentTime() { return ytPlayer ? (ytPlayer.getCurrentTime() || 0) : 0; },
      set currentTime(v) { if (ytPlayer) try { ytPlayer.seekTo(v, true); } catch (e) {} },
      get paused() { return ytPlayer ? (ytPlayer.getPlayerState() === 2 || ytPlayer.getPlayerState() === 0) : true; },
      get playbackRate() { return ytPlayer ? (ytPlayer.getPlaybackRate() || 1) : 1; },
      get duration() { return ytPlayer ? (ytPlayer.getDuration() || 0) : 0; },
      play() { if (ytPlayer) try { ytPlayer.playVideo(); } catch (e) {} return Promise.resolve(); },
      pause() { if (ytPlayer) try { ytPlayer.pauseVideo(); } catch (e) {} },
    };
  }

  // ===== VtLite 事件绑定 =====
  // 本地已回显的消息 id（服务端广播回来时按 id 去重，避免自己的消息显示两次）
  const myMsgIds = new Set();

  VtLite.on("ws_open", () => {
    showToast("已连接到同步服务器");
  });
  VtLite.on("ws_close", () => {
    showToast("与同步服务器连接断开，正在重连...");
  });
  VtLite.on("text_message", (msg) => {
    if (msg.id && myMsgIds.has(msg.id)) return;
    appendChatMessage(msg.voiceId || "匿名", msg.text);
  });

  let followedUrl = null; // 已跟随的房主视频 URL
  VtLite.on("room_update", (room) => {
    if (room.name) roomNameDisplay.textContent = room.name;
    memberCount.textContent = String(room.memberCount || 0);
    // 成员自动跟随房主视频 URL（仅支持 mp4/webm 直链与 YouTube）
    try {
      const st = VtLite.getState();
      if (st.role === "member" && room.url && room.url !== followedUrl) {
        const ytId = parseYouTubeId(room.url);
        const isDirect = /^https?:\/\/.+\.(mp4|webm|ogg)(\?.*)?$/i.test(room.url);
        if (ytId) {
          followedUrl = room.url;
          loadYouTube(ytId);
          waitYtReady().then(() => VtLite.setVideo(makeYoutubePseudoVideo()));
          showToast("已跟随房主视频");
        } else if (isDirect) {
          followedUrl = room.url;
          const v = loadVideoElement(room.url);
          VtLite.setVideo(v);
          showToast("已跟随房主视频");
        }
      }
    } catch (e) {}
  });
  VtLite.on("error", (err) => {
    console.warn("VtLite error:", err);
    if (err && err.message) {
      const map = {
        password_error: "房间密码错误",
        room_not_found: "房间不存在，请检查房间名",
        ws_all_urls_failed: "无法连接同步服务器，请检查网络",
        ws_construct_failed: "WebSocket 创建失败",
        ws_not_open: "连接未建立，请稍候",
        sync_time_failed: "时间同步失败，进度可能有偏差",
        member_sync_error: "同步播放状态失败"
      };
      showToast(map[err.message] || (err.error ? "同步错误：" + err.error : "同步错误"), 3200);
    }
  });

  // 等待 YouTube 播放器就绪
  function waitYtReady() {
    return new Promise((resolve) => {
      let tries = 0;
      const wait = setInterval(() => {
        tries++;
        if (ytPlayer && typeof ytPlayer.getCurrentTime === "function") {
          clearInterval(wait); resolve();
        } else if (tries > 50) {
          clearInterval(wait); resolve();
        }
      }, 200);
    });
  }

  // ===== 聊天 =====
  function appendChatMessage(sender, text) {
    const empty = chatMessages.querySelector(".empty");
    if (empty) empty.remove();
    const div = document.createElement("div");
    div.className = "chat-msg";
    div.innerHTML = `<div class="sender">${escapeHtml(sender)}</div><div class="text">${escapeHtml(text)}</div>`;
    chatMessages.appendChild(div);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  function sendChat() {
    const text = chatInput.value.trim();
    if (!text) return;
    VtLite.setNickname(nickname || "匿名");
    const id = VtLite.sendText(text);
    if (id) myMsgIds.add(id);
    appendChatMessage(nickname || "我", text);
    chatInput.value = "";
  }

  // ===== 开始流程 =====
  async function start() {
    nickname = nicknameInput.value.trim();
    const roomName = roomNameInput.value.trim();
    const password = passwordInput.value.trim();
    const isJoining = joinCheckbox.checked;

    if (!roomName) { showToast("请输入房间名"); return; }
    if (!nickname) { showToast("请输入昵称"); return; }

    // 决定视频源
    let videoReady = false;
    if (selectedFile) {
      loadVideoElement(URL.createObjectURL(selectedFile));
      videoReady = true;
    } else {
      const url = urlInput.value.trim();
      if (!url) {
        // 加入方可留空视频：等房主上报 URL 后自动跟随加载
        if (isJoining) {
          videoReady = false;
        } else {
          showToast("请选择视频文件或粘贴视频链接");
          return;
        }
      } else {
        const ytId = parseYouTubeId(url);
        if (ytId) {
          loadYouTube(ytId);
          videoReady = true;
        } else if (/^https?:\/\/.+\.(mp4|webm|ogg)(\?.*)?$/i.test(url)) {
          loadVideoElement(url);
          videoReady = true;
        } else {
          showToast("仅支持 mp4/webm 直链或 YouTube 链接");
          return;
        }
      }
    }

    // 切换到观影页
    homePage.classList.add("hidden");
    watchPage.classList.remove("hidden");
    topbar.classList.remove("hidden");
    chatToggle.classList.remove("hidden");
    roomNameDisplay.textContent = roomName;

    // 决定 VtLite 用哪个 video
    let vtVideo = null;
    if (currentVideoSrc === "youtube") {
      // 等 ytPlayer 准备好
      showToast("正在连接 YouTube...");
      await waitYtReady();
      vtVideo = makeYoutubePseudoVideo();
    } else if (videoEl) {
      vtVideo = videoEl;
    }

    try {
      if (isJoining) {
        await VtLite.joinRoom(roomName, password, vtVideo);
        showToast("已加入房间");
      } else {
        await VtLite.createRoom(roomName, password, vtVideo);
        showToast("房间已创建，邀请朋友加入吧");
      }
    } catch (e) {
      showToast("连接房间失败：" + (e.message || e));
    }
  }

  // ===== 离开房间 =====
  function leave() {
    VtLite.leaveRoom();
    clearVideoStage();
    homePage.classList.remove("hidden");
    watchPage.classList.add("hidden");
    topbar.classList.add("hidden");
    chatToggle.classList.add("hidden");
    chatPanel.classList.add("hidden");
    chatMessages.innerHTML = '<div class="empty">暂无消息</div>';
    selectedFile = null;
    followedUrl = null;
    myMsgIds.clear();
    fileName.textContent = "";
    fileDropHint.textContent = "点击选择本地视频文件（mp4 / mkv / webm）";
    urlInput.value = "";
  }

  // ===== 事件绑定 =====
  fileInput.addEventListener("change", (e) => {
    const f = e.target.files[0];
    if (!f) return;
    selectedFile = f;
    fileName.textContent = f.name;
    fileDropHint.textContent = "已选择文件，可点击重新选择";
  });

  joinCheckbox.addEventListener("change", (e) => {
    startBtn.textContent = e.target.checked ? "加入房间" : "创建房间";
    if (e.target.checked) {
      roomNameInput.placeholder = "对方告知的房间名";
    } else {
      roomNameInput.placeholder = "创建时自拟，加入时填对方告知的房间名";
    }
  });

  startBtn.addEventListener("click", start);

  copyBtn.addEventListener("click", async () => {
    const name = roomNameDisplay.textContent;
    if (!name || name === "—") return;
    try {
      await navigator.clipboard.writeText(name);
      showToast("房间名已复制");
    } catch (e) {
      // fallback
      const ta = document.createElement("textarea");
      ta.value = name; document.body.appendChild(ta); ta.select();
      try { document.execCommand("copy"); showToast("房间名已复制"); } catch (_) { showToast("复制失败"); }
      document.body.removeChild(ta);
    }
  });

  leaveBtn.addEventListener("click", leave);

  chatToggle.addEventListener("click", () => {
    chatToggle.classList.add("hidden");
    chatPanel.classList.remove("hidden");
    chatInput.focus();
  });

  chatCloseBtn.addEventListener("click", () => {
    chatPanel.classList.add("hidden");
    chatToggle.classList.remove("hidden");
  });

  chatSendBtn.addEventListener("click", sendChat);
  chatInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendChat();
    }
  });

  // ===== Service Worker 注册（PWA 离线） =====
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("sw.js").catch(() => {});
    });
  }

  // iOS Safari standalone 模式提示
  if (window.navigator.standalone) {
    document.body.classList.add("standalone");
  }
})();
