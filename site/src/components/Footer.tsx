export function Footer() {
  return (
    <footer className="bg-vt-bg py-12 px-6 border-t border-wandor-text/10">
      <div className="max-w-[1200px] mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <span className="font-display text-2xl text-black">VideoTogether</span>
          <span className="text-wandor-muted text-sm">· 异地同看</span>
        </div>
        <p className="text-wandor-muted text-sm">
          基于 VideoTogether 协议 · CC BY-NC 4.0
        </p>
        <div className="flex items-center gap-5 text-sm text-wandor-muted">
          <a href="/downloads/app-release.apk" target="_blank" rel="noopener noreferrer" className="hover:text-wandor-text transition-colors">Android APK</a>
          <a href="https://apps.apple.com/cn/app/videotogether/id6443755429" target="_blank" rel="noopener noreferrer" className="hover:text-wandor-text transition-colors">iOS App Store</a>
        </div>
      </div>
    </footer>
  )
}
