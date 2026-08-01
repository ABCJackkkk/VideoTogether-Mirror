import { useEffect, useRef } from 'react'
import { Download, Smartphone, Apple, ChevronDown } from 'lucide-react'

function NavButton({ children, href }: { children: React.ReactNode; href: string }) {
  return (
    <a
      href={href}
      className="bg-transparent border-none cursor-pointer font-sans text-[15px] font-medium uppercase text-wandor-text tracking-[0.04em] transition-opacity hover:opacity-55"
    >
      {children}
    </a>
  )
}

export function Hero() {
  const videoRef = useRef<HTMLVideoElement>(null)

  useEffect(() => {
    const v = videoRef.current
    if (!v) return
    v.muted = true
    const play = () => v.play().catch(() => setTimeout(play, 300))
    play()
  }, [])

  const apkSize = '24 MB'

  return (
    <section className="relative min-h-svh w-full overflow-hidden">
      {/* 背景视频 */}
      <video
        ref={videoRef}
        className="absolute inset-0 w-full h-full object-cover z-0"
        src="/bg-original.mp4"
        preload="auto"
        autoPlay
        muted
        loop
        playsInline
      />

      {/* 顶部白色渐变遮罩 */}
      <div
        className="absolute inset-x-0 top-0 h-[687px] pointer-events-none z-[1]"
        style={{
          background:
            'linear-gradient(180deg, rgba(255,255,255,1) 0%, rgba(255,255,255,0) 100%)',
        }}
      />

      {/* 内容层 */}
      <div className="relative z-[2] max-w-[1360px] mx-auto">
        {/* 顶部导航 */}
        <nav className="flex items-center justify-between px-20 pt-6 pb-4 max-md:px-6 max-md:pt-5">
          <span className="font-display text-[40px] text-black leading-none select-none max-md:text-[32px]">
            VideoTogether
          </span>

          <div className="absolute left-1/2 -translate-x-1/2 flex gap-8 max-md:hidden">
            <NavButton href="#platforms">平台</NavButton>
            <NavButton href="#features">特性</NavButton>
            <NavButton href="#faq">FAQ</NavButton>
          </div>

          <a
            href="https://ghfast.top/https://github.com/ABCJackkkk/VideoTogether-Mirror/releases/latest/download/app-release.apk"
            target="_blank"
            rel="noopener noreferrer"
            className="bg-wandor-dark text-[#fafafa] cursor-pointer font-sans text-[15px] font-medium uppercase tracking-[0.04em] px-5 py-3.5 rounded-full transition-all hover:bg-[#333] active:scale-95 no-underline"
          >
            下载 Android
          </a>
        </nav>

        {/* Hero 主体 */}
        <div className="flex flex-col items-center px-6 pt-16 pb-24 text-center">
          <h1 className="font-sans text-[clamp(40px,6vw,68px)] font-medium text-wandor-text leading-[1.05] tracking-[-0.04em] max-w-[820px] mb-5">
            一起看片，无关距离
          </h1>
          <p className="font-sans text-xl font-medium text-wandor-muted leading-relaxed max-w-[560px] mb-10">
            同步播放 · 实时聊天 · 多端可用
            <br />
            给远方的朋友按下同步播放键
          </p>

          {/* 液态玻璃下载卡 */}
          <div className="relative w-[701px] max-md:w-[calc(100vw-48px)] bg-white/[0.06] border-[3px] border-white rounded-[44px] shadow-[0_0_4px_0_rgba(0,0,0,0.15)] overflow-hidden backdrop-blur-[20px] p-8 max-md:p-6">
            <p className="font-sans text-lg font-medium text-wandor-text/80 mb-6 text-left">
              选择你的平台，立刻开始
            </p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Android APK */}
              <a
                href="https://ghfast.top/https://github.com/ABCJackkkk/VideoTogether-Mirror/releases/latest/download/app-release.apk"
                target="_blank"
                rel="noopener noreferrer"
                className="group bg-black/70 hover:bg-black backdrop-blur-md border border-white/20 rounded-2xl p-5 flex flex-col items-start transition-all hover:scale-[1.02] active:scale-95 no-underline"
              >
                <Smartphone className="w-6 h-6 text-white mb-3" />
                <span className="text-white font-semibold text-base">Android App</span>
                <span className="text-white/60 text-xs mt-1">APK · {apkSize}</span>
                <span className="mt-4 flex items-center gap-1 text-white/80 text-xs font-medium uppercase tracking-wider group-hover:text-white">
                  <Download className="w-3.5 h-3.5" />
                  下载
                </span>
              </a>

              {/* iOS App */}
              <a
                href="https://apps.apple.com/cn/app/videotogether/id6443755429"
                target="_blank"
                rel="noopener noreferrer"
                className="group bg-black/70 hover:bg-black backdrop-blur-md border border-white/20 rounded-2xl p-5 flex flex-col items-start transition-all hover:scale-[1.02] active:scale-95 no-underline"
              >
                <Apple className="w-6 h-6 text-white mb-3" />
                <span className="text-white font-semibold text-base">iOS App</span>
                <span className="text-white/60 text-xs mt-1">App Store</span>
                <span className="mt-4 flex items-center gap-1 text-white/80 text-xs font-medium uppercase tracking-wider group-hover:text-white">
                  <Download className="w-3.5 h-3.5" />
                  下载
                </span>
              </a>
            </div>

            <p className="text-center text-wandor-text/60 text-xs mt-6">
              Android · iOS 双端互通，输入同一个房间名即可同步
            </p>
          </div>

          {/* 向下提示 */}
          <a
            href="#platforms"
            className="mt-16 flex flex-col items-center text-wandor-muted hover:text-wandor-text transition-colors"
          >
            <span className="text-xs uppercase tracking-[0.2em] mb-2">了解更多</span>
            <ChevronDown className="w-5 h-5 animate-bounce" />
          </a>
        </div>
      </div>
    </section>
  )
}
