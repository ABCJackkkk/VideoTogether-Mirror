import { Smartphone, Apple } from 'lucide-react'

const platforms = [
  {
    icon: Smartphone,
    title: 'Android',
    subtitle: '原生 App',
    desc: '安装即用，支持本地视频、YouTube、视频直链同步播放。WebSocket 断线自动重连。',
    action: { label: '下载 APK', href: '/downloads/app-release.apk', download: true },
    badge: '推荐',
  },
  {
    icon: Apple,
    title: 'iPhone',
    subtitle: 'iOS App',
    desc: '原生 iOS 体验，跟 Android 互通。支持本地视频、YouTube、视频直链同步播放。',
    action: { label: 'App Store', href: 'https://apps.apple.com/cn/app/videotogether/id6443755429', download: false },
    badge: 'iOS',
  },
]

export function Platforms() {
  return (
    <section id="platforms" className="py-24 px-6 bg-vt-bg">
      <div className="max-w-[1200px] mx-auto">
        <div className="text-center mb-16">
          <h2 className="font-sans text-[clamp(32px,4vw,48px)] font-medium text-wandor-text leading-tight tracking-[-0.03em] mb-4">
            双端互通，同一个房间
          </h2>
          <p className="font-sans text-lg text-wandor-muted max-w-[560px] mx-auto">
            不管你和朋友用 Android 还是 iPhone，输入同一个房间名就能一起看
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-[900px] mx-auto">
          {platforms.map((p) => {
            const Icon = p.icon
            return (
              <div
                key={p.title}
                className="relative bg-white/70 hover:bg-white border border-wandor-text/10 rounded-3xl p-8 transition-all hover:shadow-lg hover:-translate-y-1"
              >
                <span className="absolute top-6 right-6 text-[11px] font-semibold uppercase tracking-wider text-vt-accent bg-vt-accent/10 px-2.5 py-1 rounded-full">
                  {p.badge}
                </span>

                <div className="w-12 h-12 rounded-2xl bg-wandor-dark flex items-center justify-center mb-5">
                  <Icon className="w-6 h-6 text-white" />
                </div>

                <h3 className="font-sans text-2xl font-semibold text-wandor-text mb-1">
                  {p.title}
                </h3>
                <p className="text-sm text-wandor-muted mb-4">{p.subtitle}</p>
                <p className="text-[15px] text-wandor-text/80 leading-relaxed mb-6">
                  {p.desc}
                </p>

                <a
                  href={p.action.href}
                  {...(p.action.download ? { download: true } : {})}
                  className="inline-flex items-center gap-2 bg-wandor-dark text-white text-sm font-medium uppercase tracking-wider px-5 py-3 rounded-full hover:bg-[#333] active:scale-95 transition-all no-underline"
                >
                  {p.action.label}
                </a>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}
