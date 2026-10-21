import { useLayoutEffect, useRef, useState } from 'react'
import { easeIn, m, useMotionTemplate, useMotionValueEvent, useReducedMotion, useTransform, type MotionValue } from 'motion/react'
import appIcon from '@/assets/app-icon.png'
import { cn } from '@/lib/utils'
import { DitherSwirl } from './DitherSwirl'
import { FloatingIcon } from './FloatingIcon'

/* The first screen. The intro takes 5 seconds: the name fades in at the centre, slides to its place,
   then the swirl, the subtitle and the icon fade in together. Everything moves on a long glide: it
   starts right away and slows into a long, soft landing. With Reduce Motion everything simply fades
   in and the swirl holds still.

   Scrolling flies you into the swirl: the words and the icon rush past while the swirl spreads out and fades
   (`progress`, 0 to 1, is the whole trip to the next part). Reduce Motion fades instead. */

const GLIDE = 'cubic-bezier(.16, 1, .3, 1)' // ease-out expo
const SOFT_GLIDE = 'cubic-bezier(.33, 1, .68, 1)' // ease-out cubic, for the big swirl fading in

type Props = {
  progress: MotionValue<number>
  /** The swirl's flight, 0 to 1; left out with Reduce Motion. */
  flight?: MotionValue<number>
  /** "Skip to the notch", for keyboard users. */
  onSkip: () => void
}

export function Splash({ progress, flight, onSkip }: Props) {
  const reduce = useReducedMotion() ?? false
  const sectionRef = useRef<HTMLElement>(null)
  const groupRef = useRef<HTMLDivElement>(null)
  const textRef = useRef<HTMLDivElement>(null)
  const titleRef = useRef<HTMLHeadingElement>(null)
  const subtitleRef = useRef<HTMLParagraphElement>(null)
  const iconRef = useRef<HTMLDivElement>(null)
  const swirlRef = useRef<HTMLDivElement>(null)
  const [clear, setClear] = useState({ x: 0, y: 0 })

  // Flying past: the words and icon grow toward you, blur and fade; then the swirl goes dark.
  const scale = useTransform(progress, [0, 0.225], [1, reduce ? 1 : 3.2], { ease: easeIn })
  const opacity = useTransform(progress, [0.015, 0.165], [1, 0])
  const blur = useTransform(progress, [0.03, 0.195], [0, reduce ? 0 : 10])
  const filter = useMotionTemplate`blur(${blur}px)`
  const swirlOpacity = useTransform(progress, [0.47, 0.6], [1, 0])
  const [gone, setGone] = useState(() => progress.get() > 0.225)
  useMotionValueEvent(progress, 'change', (p) => setGone(p > 0.225))

  // The swirl keeps a clear ellipse around the words and the icon. It's as wide as the content (so on
  // phones the dots still reach the sides) and just tall enough to cover it. Offsets ignore the intro's
  // transforms, so this can run at any time.
  useLayoutEffect(() => {
    const group = groupRef.current
    const text = textRef.current
    const icon = iconRef.current
    if (!group || !text || !icon) return
    const measure = () => {
      const cx = group.offsetWidth / 2
      const cy = group.offsetHeight / 2
      const points: [number, number][] = []
      for (const x of [text.offsetLeft, text.offsetLeft + text.offsetWidth])
        for (const y of [text.offsetTop, text.offsetTop + text.offsetHeight]) points.push([x - cx, y - cy])
      // The icon image has see-through margins: its rounded square reaches about 42% of its size out.
      const r = icon.offsetWidth * 0.42
      const ix = icon.offsetLeft + icon.offsetWidth / 2 - cx
      const iy = icon.offsetTop + icon.offsetHeight / 2 - cy
      for (let i = 0; i < 8; i++) points.push([ix + r * Math.cos((i * Math.PI) / 4), iy + r * Math.sin((i * Math.PI) / 4)])

      const a = Math.max(...points.map(([x]) => Math.abs(x))) + 12
      // Far corners may sit just outside (up to 1.1×), where the swirl has next to no dots anyway.
      const b = Math.max(...points.map(([x, y]) => Math.abs(y) / Math.sqrt(1.21 - (x / a) ** 2))) + 12
      setClear({ x: a, y: b })
    }
    measure()
    const sizes = new ResizeObserver(measure)
    sizes.observe(group)
    return () => sizes.disconnect()
  }, [])

  useLayoutEffect(() => {
    const section = sectionRef.current
    const title = titleRef.current
    const rest = [swirlRef.current, subtitleRef.current, iconRef.current]
    if (!section || !title || rest.some((element) => !element)) return
    const [swirl, subtitle, icon] = rest as HTMLElement[]

    // Each animation ends where the page already is, so nothing lingers once it's done.
    const animations: Animation[] = []
    const play = (element: Element, from: Keyframe, to: Keyframe, delay: number, duration: number, easing: string) =>
      animations.push(element.animate([from, to], { delay, duration, easing, fill: 'backwards' }))

    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      play(title, { opacity: 0 }, { opacity: 1 }, 100, 600, 'ease-out')
      for (const element of rest as HTMLElement[]) play(element, { opacity: 0 }, { opacity: 1 }, 500, 700, 'ease-out')
    } else {
      const page = section.getBoundingClientRect()
      const box = title.getBoundingClientRect()
      const dx = page.left + page.width / 2 - (box.left + box.width / 2)
      const dy = page.top + page.height / 2 - (box.top + box.height / 2)
      const centre = `translate(${dx}px, ${dy}px)`

      // Delays and lengths in milliseconds; all of it is done at 5 s.
      play(title, { opacity: 0, transform: centre, filter: 'blur(12px)' }, { opacity: 1, transform: centre, filter: 'blur(0px)' }, 300, 1600, GLIDE)
      play(title, { transform: centre }, { transform: 'none' }, 1700, 2200, GLIDE)
      play(swirl, { opacity: 0 }, { opacity: 1 }, 2600, 2400, SOFT_GLIDE)
      play(subtitle, { opacity: 0, transform: 'translateY(12px)' }, { opacity: 1, transform: 'none' }, 2800, 2200, GLIDE)
      play(icon, { opacity: 0, transform: 'scale(.92)' }, { opacity: 1, transform: 'none' }, 2700, 2300, GLIDE)
    }
    return () => animations.forEach((animation) => animation.cancel())
  }, [])

  return (
    <section ref={sectionRef} aria-labelledby="title" className="absolute inset-0 flex items-center justify-center overflow-hidden">
      <m.div style={{ opacity: swirlOpacity }} className="absolute inset-0">
        <div ref={swirlRef} className="absolute inset-0">
          <DitherSwirl clear={clear} flight={flight} className="absolute inset-0 overflow-hidden" />
        </div>
      </m.div>

      <m.div style={{ scale, opacity, filter }} className={gone ? 'invisible' : undefined}>
      <div
        ref={groupRef}
        className="relative flex flex-col-reverse items-center gap-7 px-6 text-center md:flex-row md:gap-[clamp(2rem,3.6vw,4rem)] md:px-0 md:text-left"
      >
        <div ref={textRef}>
          <h1
            ref={titleRef}
            id="title"
            className="font-display text-[clamp(2.75rem,13vw,4.5rem)] leading-[.95] font-bold tracking-[-0.045em] whitespace-nowrap text-ink md:text-[clamp(4rem,6.4vw,7.5rem)]"
          >
            PancakeNotch
          </h1>
          <p
            ref={subtitleRef}
            className="mt-[.75em] text-[clamp(1.0625rem,.9rem+.75vw,1.75rem)] font-medium tracking-[-0.01em] text-soft"
          >
            Give your notch a job.
          </p>
        </div>
        <div ref={iconRef}>
          <FloatingIcon src={appIcon} paused={gone} className="size-[clamp(8rem,36vw,10.5rem)] md:size-[clamp(9.5rem,14vw,15rem)]" />
        </div>
      </div>
      </m.div>

      {/* Shown only when the keyboard reaches it. */}
      <button
        type="button"
        onClick={onSkip}
        className={cn(
          'sr-only rounded-full bg-white px-4 py-2 text-sm font-semibold text-black focus-visible:not-sr-only focus-visible:absolute focus-visible:bottom-8',
          gone && 'invisible',
        )}
      >
        Skip to the notch
      </button>
    </section>
  )
}
