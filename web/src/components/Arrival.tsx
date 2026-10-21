import { useCallback, useEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import { easeOut, m, useMotionValueEvent, useReducedMotion, useTransform, type MotionValue } from 'motion/react'
import { ScrambleText } from '@/components/ScrambleText'
import { cn } from '@/lib/utils'
import { CurrentGrid } from './CurrentGrid'
import { LiveNotch, type NotchStatus } from './notch/LiveNotch'
import { TechHeading } from './TechHeading'

/* The other end of the wormhole: as the swirl fades, a section with the words on the left and, on
   the right, a pretend Mac screen with the working notch in it, drawn like the practice notch in the
   app's own window. The screen arrives tipped back and swings upright as you scroll (like Aceternity
   UI's Container Scroll), a light runs around its edge, the heading is built from little squares (and
   a letter turns into a dashed outline when you hover it) and gray wisps of dots blow behind it all.
   The sentence under the heading follows what's open in the notch. Out of sight (and out of reach of
   the keyboard and screen readers) until it starts to show; usable once you've fully arrived.

   Scroll on from there (after a stretch where nothing changes, so there's time to play) and the
   section dissolves into the fabric backdrop (see Journey and FabricGrid). `progress` is the way in
   (0 to 1), `exit` the way out (0 to 1). */

const SHOWING = 0.5
const TITLED = 0.66
const ARRIVED = 0.92
const GONE = 0.96 // how far through the exit it's fully covered, and out of sight

type Props = {
  progress: MotionValue<number>
  exit: MotionValue<number>
  /** Set by "Skip to the notch": put the keyboard on the notch once we get there. */
  focusOnArrival: RefObject<boolean>
}

/** What the notch is showing, in a sentence. */
function describe({ open, module, item }: NotchStatus) {
  if (!open) return 'It’s playing a song and watching your AI agents: the cover sits on the left of the notch, the sound and an agent count on the right.'
  if (module === 'np') return 'Pause, skip or drag through the song, without leaving the app you’re in.'
  if (module === 'agents') return 'Every AI agent at work, in one list. When one asks for permission, answer it right here.'
  if (module === 'menu') return 'The Module Menu holds every module. Your favorites get a tab of their own.'
  if (item === 'text') return 'Notes open right in the notch, to read, change or copy.'
  if (item) return 'Every item opens in place, to check it, copy it or take it off the Shelf.'
  return 'The Shelf keeps files, notes and links for later, even after a restart.'
}

export function Arrival({ progress, exit, focusOnArrival }: Props) {
  const reduce = useReducedMotion() ?? false
  // The screen comes up out of the dark, tipped back, and swings upright as you scroll on.
  const rise = useTransform(progress, [SHOWING, 0.95], [0, 1], { ease: easeOut })
  const screen = useTransform(progress, [SHOWING, 0.64], [0, 1])
  const tilt = useTransform(rise, [0, 1], [reduce ? 0 : 28, 0])
  const screenScale = useTransform(rise, [0, 1], [reduce ? 1 : 0.86, 1])
  const screenY = useTransform(rise, [0, 1], [reduce ? 0 : 90, 0])
  // The heading builds itself once it's in view (see `titled`); then the sentence comes in.
  const words = useTransform(progress, [0.74, 0.86], [0, 1])
  const wordsY = useTransform(words, [0, 1], [24, 0])
  const backdrop = useTransform(progress, [0.55, 0.85], [0, 1])

  const [showing, setShowing] = useState(() => progress.get() > SHOWING)
  const [titled, setTitled] = useState(() => progress.get() > TITLED)
  const [arrived, setArrived] = useState(() => progress.get() > ARRIVED)
  const [leaving, setLeaving] = useState(() => exit.get() > 0.01)
  const [gone, setGone] = useState(() => exit.get() > GONE)
  useMotionValueEvent(progress, 'change', (p) => {
    setShowing(p > SHOWING)
    setTitled(p > TITLED)
    setArrived(p > ARRIVED)
  })
  useMotionValueEvent(exit, 'change', (e) => {
    setLeaving(e > 0.01)
    setGone(e > GONE)
  })

  const [status, setStatus] = useState<NotchStatus>({ open: false, module: 'np', item: null, touch: false })
  const onStatus = useCallback((next: NotchStatus) => setStatus(next), [])
  const sentence = describe(status)

  const sectionRef = useRef<HTMLElement>(null)
  useEffect(() => {
    if (!arrived || !focusOnArrival.current) return
    focusOnArrival.current = false
    sectionRef.current?.querySelector('button')?.focus()
  }, [arrived, focusOnArrival])

  return (
    <>
      {/* Quieter behind the words on wide screens, so they read cleanly. */}
      <m.div
        style={{ opacity: backdrop }}
        className={cn(
          'pointer-events-none absolute inset-0 lg:[mask-image:radial-gradient(ellipse_34%_34%_at_24%_50%,rgb(0_0_0/.3),#000)]', // taste-skill-ignore: a mask, not a visible gradient
          (!showing || gone) && 'invisible',
        )}
      >
        {/* The grid thins out toward the bottom, so it doesn't end in a hard line as the section scrolls away. */}
        <div
          className="absolute inset-0 [mask-image:linear-gradient(to_bottom,#000_70%,transparent)]" // taste-skill-ignore: a mask, not a visible gradient
        >
          <CurrentGrid active={showing && !gone} className="absolute inset-0 overflow-hidden" />
        </div>
      </m.div>
      <section
        ref={sectionRef}
        aria-labelledby="try-title"
        className={cn(
          'absolute inset-0 flex items-center',
          leaving ? 'overflow-hidden' : 'overflow-y-auto', // zooming: nothing may scroll
          (!showing || gone) && 'invisible',
          (!arrived || leaving) && 'pointer-events-none',
        )}
      >
        <div className="mx-auto grid w-full max-w-[86rem] grid-cols-1 items-center gap-9 px-5 py-10 md:px-10 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-[clamp(2.5rem,5vw,5.5rem)] lg:px-[clamp(2rem,4vw,4rem)]">
          <div className="max-w-[34rem]">
            <TechHeading
              id="try-title"
              play={titled}
              className="font-display text-[clamp(2.5rem,4.6vw,4.75rem)] font-bold text-ink"
            />
            <m.p
              style={{ opacity: words, y: wordsY }}
              aria-live="polite"
              className="mt-6 min-h-[4.35em] text-[clamp(1.125rem,.95rem+.55vw,1.4rem)] leading-[1.45] text-ink"
            >
              <ScrambleText key={sentence} text={sentence} pace={12} scrambledClassName="text-white/35" />
            </m.p>
          </div>

          <div className="[perspective:1200px]">
            <m.div style={{ opacity: screen, rotateX: tilt, scale: screenScale, y: screenY }}>
              <Screen beam={arrived}>
                <LiveNotch active={arrived} onStatus={onStatus} />
              </Screen>
            </m.div>
          </div>
        </div>
      </section>
    </>
  )
}

/** A pretend Mac screen in its bezel: black, with the app's faint dot wallpaper, a glow where the
    light catches the notch and a sketched menu bar either side of it. A small light (like Magic UI's
    Border Beam) runs around the bezel while `beam` is on. */
function Screen({ beam, children }: { beam: boolean; children: ReactNode }) {
  return (
    <div data-ui className="relative rounded-[22px] bg-[#161616] p-2">
      <div aria-hidden="true" className={cn('border-beam', !beam && 'border-beam-paused')} />
      <div className="relative aspect-[16/10] min-h-[17.5rem] w-full overflow-hidden rounded-[14px] bg-black">
        <div
          aria-hidden="true"
          className="absolute inset-0 [mask-image:radial-gradient(ellipse_75%_75%_at_50%_0%,#000,transparent)] bg-[radial-gradient(circle,rgba(255,255,255,.16)_.75px,transparent_1.25px)] bg-size-[16px_16px] bg-position-[center_8px]" // taste-skill-ignore: the app's own interface, drawn in the pretend screen
        />
        <div
          aria-hidden="true"
          className="absolute inset-0 bg-[radial-gradient(ellipse_320px_170px_at_50%_0%,rgba(255,255,255,.2),rgba(255,255,255,.07)_45%,transparent),radial-gradient(ellipse_170px_60px_at_50%_0%,rgba(255,255,255,.22),transparent)]" // taste-skill-ignore: the app's own interface, drawn in the pretend screen
        />
        <div aria-hidden="true" className="absolute inset-x-0 top-0 flex h-8 items-center gap-3 px-5 text-white/16">
          <span className="size-[9px] rounded-full bg-current" />
          {[34, 26, 30, 24].map((width) => (
            <span key={width} className="h-[5px] rounded-full bg-current" style={{ width }} />
          ))}
          <span className="flex-1" />
          {[0, 1, 2].map((i) => (
            <span key={i} className="h-[9px] w-[11px] rounded-[2.5px] bg-current" />
          ))}
          <span className="h-[5px] w-11 rounded-full bg-current" />
        </div>
        {children}
      </div>
    </div>
  )
}
