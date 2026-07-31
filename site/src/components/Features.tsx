import { Play, MessageCircle, Lock, RefreshCw, Smartphone, Zap } from 'lucide-react'

const features = [
  {
    icon: Play,
    title: '同步播放',
    desc: '一方播放/暂停/拖动进度，所有端同步跟上。误差在秒级以内。',
  },
  {
    icon: MessageCircle,
    title: '实时聊天',
    desc: '房间内浮层聊天，边看边聊，不用切应用。',
  },
  {
    icon: Lock,
    title: '房间密码',
    desc: '可选密码保护，私密房间只让朋友进。',
  },
  {
    icon: RefreshCw,
    title: '断线重连',
    desc: 'WebSocket 掉线自动恢复，连接状态顶部可见。',
  },
  {
    icon: Smartphone,
    title: '跨端互通',
    desc: 'Android、iOS、网页版都能进同一个房间，完全同步。',
  },
  {
    icon: Zap,
    title: '即开即用',
    desc: '无需注册、无需搭建，输入房间名即刻开始同步观看。',
  },
]

export function Features() {
  return (
    <section id="features" className="py-24 px-6 bg-[#1a1a1a]">
      <div className="max-w-[1200px] mx-auto">
        <div className="text-center mb-16">
          <h2 className="font-sans text-[clamp(32px,4vw,48px)] font-medium text-white leading-tight tracking-[-0.03em] mb-4">
            为远距离观影而生
          </h2>
          <p className="font-sans text-lg text-white/60 max-w-[560px] mx-auto">
            轻量、稳定、跨端互通
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-px bg-white/10 rounded-3xl overflow-hidden">
          {features.map((f) => {
            const Icon = f.icon
            return (
              <div
                key={f.title}
                className="bg-[#1a1a1a] hover:bg-[#222] p-8 transition-colors"
              >
                <div className="w-11 h-11 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center mb-5">
                  <Icon className="w-5 h-5 text-vt-accent" />
                </div>
                <h3 className="font-sans text-xl font-semibold text-white mb-2">
                  {f.title}
                </h3>
                <p className="text-[15px] text-white/60 leading-relaxed">
                  {f.desc}
                </p>
              </div>
            )
          })}
        </div>

        {/* FAQ 小区块 */}
        <div id="faq" className="mt-20 max-w-[760px] mx-auto">
          <h3 className="font-sans text-2xl font-semibold text-white mb-6 text-center">
            常见问题
          </h3>
          <div className="space-y-4">
            {[
              {
                q: 'Android 和 iPhone 能互通吗？',
                a: '当然。Android、iOS、网页版三端都基于 VT 协议，输入同一个房间名就能一起看。',
              },
              {
                q: '能同步 B 站 / 腾讯视频吗？',
                a: 'App 内支持本地文件、YouTube、视频直链同步播放。B 站等外部站点受限于平台策略，建议找直链/本地资源同步播放。',
              },
              {
                q: '需要注册账号吗？',
                a: '不需要。输入房间名就能开始用，没有任何注册流程。',
              },
              {
                q: '支持哪些视频格式？',
                a: 'MP4、MKV、WebM 本地文件均可播放；视频直链支持 MP4；YouTube 支持链接播放。',
              },
            ].map((item, i) => (
              <details
                key={i}
                className="group bg-white/[0.04] border border-white/10 rounded-2xl overflow-hidden"
              >
                <summary className="cursor-pointer list-none px-6 py-5 flex items-center justify-between text-white font-medium text-[15px] hover:bg-white/[0.04]">
                  {item.q}
                  <span className="text-white/40 group-open:rotate-45 transition-transform text-xl leading-none">
                    +
                  </span>
                </summary>
                <p className="px-6 pb-5 text-white/60 text-[14px] leading-relaxed">
                  {item.a}
                </p>
              </details>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
