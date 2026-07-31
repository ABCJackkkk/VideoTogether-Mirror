// Service Worker — 简单缓存策略
// 静态资源立即缓存；视频/直播流走网络

const CACHE_NAME = "videotogether-v1";
const PRECACHE = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./vt-lite.js",
  "./manifest.json",
  "./icon-192.png",
  "./icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      cache.addAll(PRECACHE).catch(() => {})
    )
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  // 仅处理 GET
  if (req.method !== "GET") return;

  const url = new URL(req.url);

  // 视频/媒体流不走缓存
  if (req.destination === "video" || req.destination === "audio") return;
  // blob: 不走 SW
  if (url.protocol === "blob:") return;
  // VT 服务器、YouTube、外部资源：直接走网络
  if (url.origin !== self.location.origin) return;

  // 同源静态资源：cache-first
  event.respondWith(
    caches.match(req).then((cached) =>
      cached || fetch(req).then((res) => {
        // 缓存新资源
        if (res && res.status === 200 && res.type === "basic") {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached)
    )
  );
});
