import { useEffect, useState } from 'react'
import { m, useReducedMotion, useScroll, useSpring, useTransform } from 'motion/react'
import { Logo } from './Logo'

/* The top bar: the logo and name on the left, links to Help and the project and a Download button (the
   latest release on GitHub) on the right. It waits for the opening animation to finish before it appears.
   At the very top it's a wide, light frosted-glass bar; as you scroll the glass fills in and it
   shrinks into a compact capsule in the middle. With Reduce Motion it doesn't shrink. */

const REPO = 'https://github.com/sickpancake/PancakeNotch'
const RELEASES = `${REPO}/releases/latest`
const HELP = `${import.meta.env.BASE_URL}help/`

const FULL = 1376 // 86rem, the page's width, in pixels
const COMPACT = 900

export function TopBar() {
  const reduce = useReducedMotion() ?? false
  const [shown, setShown] = useState(false)
  const { scrollY } = useScroll()
  const glass = useTransform(scrollY, [0, 180], [0.5, 1]) // light glass from the start, so it reads over the swirl
  const width = useSpring(useTransform(scrollY, [30, 260], [FULL, reduce ? FULL : COMPACT]), { stiffness: 170, damping: 28, mass: 0.6 })

  // The opening animation is five seconds; the bar comes in as it ends (sooner with Reduce Motion).
  useEffect(() => {
    const timer = setTimeout(() => setShown(true), reduce ? 600 : 4300)
    return () => clearTimeout(timer)
  }, [reduce])

  const toTop = (event: React.MouseEvent) => {
    event.preventDefault()
    window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' })
  }

  return (
    <header
      // Not reachable (by pointer or keyboard) until it has appeared.
      inert={!shown}
      data-shown={shown}
      className="fixed inset-x-0 top-0 z-50 -translate-y-3 px-[max(.75rem,calc(var(--page-gutter)-1.25rem))] pt-3 opacity-0 transition-[opacity,translate] duration-700 ease-out data-[shown=true]:translate-y-0 data-[shown=true]:opacity-100 sm:pt-4"
    >
      <m.div style={{ maxWidth: width }} className="relative mx-auto flex h-14 items-center justify-between rounded-full pr-2 pl-5">
        {/* The frosted glass: light at the top, fuller once you've scrolled. */}
        <m.div
          aria-hidden="true"
          style={{ opacity: glass }}
          className="absolute inset-0 rounded-full bg-black/55 ring-1 ring-white/12 backdrop-blur-xl backdrop-saturate-150" // taste-skill-ignore: the one sticky bar, frosted on purpose
        />

        <a
          href="./"
          onClick={toTop}
          className="group relative flex items-center gap-3 rounded-full py-1 pr-3 text-ink focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
        >
          <Logo className="text-[1.75rem] transition-transform duration-300 ease-[cubic-bezier(.34,1.56,.64,1)] group-hover:-rotate-6 group-hover:scale-110" />
          <span className="font-display text-[1.1875rem] font-bold tracking-[-0.025em]">PancakeNotch</span>
        </a>

        <nav aria-label="Project" className="relative flex items-center gap-1.5">
          <a
            href={HELP}
            className="hidden h-10 items-center rounded-full px-4 text-[.9375rem] font-medium text-soft transition-colors hover:bg-white/10 hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white sm:inline-flex"
          >
            Help
          </a>
          <a
            href={REPO}
            className="hidden h-10 items-center rounded-full px-4 text-[.9375rem] font-medium text-soft transition-colors hover:bg-white/10 hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white sm:inline-flex"
          >
            GitHub
          </a>
          <a
            href={RELEASES}
            className="inline-flex h-10 items-center rounded-full bg-white px-5 text-[.9375rem] font-semibold text-black transition-[transform,background-color] duration-200 hover:scale-[1.04] hover:bg-white/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white active:scale-[.97]"
          >
            Download
          </a>
        </nav>
      </m.div>
    </header>
  )
}
