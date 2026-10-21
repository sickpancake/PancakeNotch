import { useRef } from 'react'
import { useMotionValue, useMotionValueEvent, useReducedMotion, useScroll, useSpring, useTransform } from 'motion/react'
import { Arrival } from './Arrival'
import { FabricGrid } from './FabricGrid'
import { Splash } from './Splash'

/* The first stretch of the page: the splash, the trip through the swirl and the notch at the other
   end, all on one screen that stays put while you scroll. Scrolling steers the trip (a spring smooths
   out mouse-wheel steps); stop and it holds, scroll back up and you fly out again. Keyboard users get
   a "Skip to the notch" link, shown when it has focus.

   Three stretches of scrolling, in screen heights: getting to the notch (`ENTER`), a stretch where
   nothing changes so there's time to play with the notch (`HOLD`), and then the notch section
   dissolving into the fabric backdrop (`EXIT`). The backdrop is a fixed layer drawn after the track,
   so it covers the pinned screen and then stays put behind the rest of the page, whose sections are
   `relative` so they sit on top of it. */

const ENTER = 80
const HOLD = 60
const EXIT = 35
const RANGE = ENTER + HOLD + EXIT
const ARRIVED_AT = ENTER / RANGE // the share of the track where the notch has arrived
const LEAVING_AT = (ENTER + HOLD) / RANGE // where it starts to dissolve

export function Journey() {
  const trackRef = useRef<HTMLDivElement>(null)
  const reduce = useReducedMotion() ?? false
  const { scrollYProgress } = useScroll({ target: trackRef, offset: ['start start', 'end end'] })
  const smooth = useSpring(scrollYProgress, { stiffness: 110, damping: 26, mass: 0.5, restDelta: 0.0005 })
  // With Reduce Motion, the scroll position itself. Copied over rather than used directly: Motion hands
  // values straight from useScroll to the browser's own scroll animations, which map this layout wrongly.
  const direct = useMotionValue(scrollYProgress.get())
  useMotionValueEvent(scrollYProgress, 'change', (p) => direct.set(p))
  const trip = reduce ? direct : smooth
  const progress = useTransform(trip, [0, ARRIVED_AT], [0, 1]) // 0 to 1 on the way to the notch
  const exit = useTransform(trip, [LEAVING_AT, 1], [0, 1]) // 0 to 1 while it dissolves
  const cover = useTransform(exit, [0.04, 0.96], [0, 1])
  const flight = useTransform(progress, [0, 0.6], [0, 1])

  const focusOnArrival = useRef(false)
  const skip = () => {
    const track = trackRef.current
    if (!track) return
    focusOnArrival.current = true
    const top = track.offsetTop + (track.offsetHeight - window.innerHeight) * ARRIVED_AT
    window.scrollTo({ top, behavior: reduce ? 'auto' : 'smooth' })
  }

  return (
    <>
      <div ref={trackRef} className="relative" style={{ height: `${100 + RANGE}svh` }}>
        <div className="sticky top-0 h-svh min-h-[30rem] overflow-hidden bg-black">
          <Splash progress={progress} flight={reduce ? undefined : flight} onSkip={skip} />
          <Arrival progress={progress} exit={exit} focusOnArrival={focusOnArrival} />
        </div>
      </div>
      <FabricGrid cover={cover} />
    </>
  )
}
