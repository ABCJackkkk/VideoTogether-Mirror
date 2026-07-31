import { Hero } from '@/components/Hero'
import { Platforms } from '@/components/Platforms'
import { Features } from '@/components/Features'
import { Footer } from '@/components/Footer'

function App() {
  return (
    <div className="min-h-svh w-full overflow-x-hidden">
      <Hero />
      <Platforms />
      <Features />
      <Footer />
    </div>
  )
}

export default App
