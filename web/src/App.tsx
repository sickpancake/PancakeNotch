import { LazyMotion, domAnimation } from 'motion/react'
import { FeatureRow } from '@/components/FeatureRow'
import { Footer } from '@/components/Footer'
import { Journey } from '@/components/Journey'
import { Proof } from '@/components/Proof'
import { ScrollWords } from '@/components/ScrollWords'
import { TopBar } from '@/components/TopBar'

// Motion's smaller build: animations and exits only (no dragging or layout animations).
export function App() {
  return (
    <LazyMotion features={domAnimation} strict>
      <TopBar />
      <main>
        <Journey />
        <ScrollWords />
        <FeatureRow />
        <Proof />
        <Footer />
      </main>
    </LazyMotion>
  )
}
