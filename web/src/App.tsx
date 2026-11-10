import { LazyMotion, domAnimation } from 'motion/react'
import { BetaNote } from '@/components/BetaNote'
import { FeatureRow } from '@/components/FeatureRow'
import { Footer } from '@/components/Footer'
import { Journey } from '@/components/Journey'
import { Proof } from '@/components/Proof'
import { Questions } from '@/components/Questions'
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
        <Questions />
        <BetaNote />
        <Footer />
      </main>
    </LazyMotion>
  )
}
