/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Geist', 'Noto Sans SC', 'sans-serif'],
        display: ['Special Elite', 'serif'],
      },
      colors: {
        // 保留原 wandor 暖色调
        wandor: {
          dark: '#0a0a0a',
          text: '#1a1a1a',
          muted: '#767676',
          prompt: '#905831',
        },
        // 新增异地同看主题色（暖琥珀）
        vt: {
          bg: '#e8ddd0',
          accent: '#905831',
          accentHover: '#7a4628',
        },
      },
    },
  },
  plugins: [],
}
