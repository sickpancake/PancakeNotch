import { useEffect, useLayoutEffect, useRef, useState, type FocusEvent, type MouseEvent, type PointerEvent, type ReactNode } from 'react'
import { AnimatePresence, m, useReducedMotion, type Transition } from 'motion/react'
import { cn } from '@/lib/utils'
import { Logo } from './Logo'

/* The top bar, as a notch. It hangs from the top edge of the window like the MacBook's,
   pure black, with the small concave corners where it meets the edge.

   - While the opening animation plays it's just a bare notch; as it ends, the notch wakes up and the
     logo and the Download button slide out from under it (like the app's spots beside the notch).
   - Hover it (tap on touch screens, Enter with the keyboard) and it opens with the app's springs into
     a panel with the links: Help, GitHub, What's new and Report a problem.
   - Scroll into a new part of the page and it briefly grows a line underneath with that part's name and
     a row of dots, one per part, the current one stretched into a pill that slides along as you go
     (like a phone's page dots), as the app shows a new song's name.

   Sizes and springs follow the working notch further down the page (notch/LiveNotch.tsx). */

const REPO = 'https://github.com/sickpancake/PancakeNotch'
const RELEASES = `${REPO}/releases/latest`
const ALL_RELEASES = `${REPO}/releases`
const HELP = `${import.meta.env.BASE_URL}help/`
const REPORT = `${HELP}#report`

const H = 40 // the closed notch's height
const BARE = 196 // the bare notch's width, before it wakes up
const COMPACT = 404
const OPEN_MAX = 640
const PEEK = 30 // the extra height of the line underneath

const RING = '0 0 0 1px rgba(255,255,255,.07), 0 10px 30px rgba(0,0,0,.35)' // taste-skill-ignore: the notch's own edge, as in the app
const OPEN_RING = '0 0 0 1px rgba(255,255,255,.16), 0 24px 60px rgba(0,0,0,.9)' // taste-skill-ignore: the notch's own edge, as in the app

// The app's springs: opening overshoots a little, closing and small changes settle softly.
const OPEN: Transition = { type: 'spring', visualDuration: 0.5, bounce: 0.24 }
const CLOSE: Transition = { type: 'spring', visualDuration: 0.42, bounce: 0 }
const SWITCH: Transition = { type: 'spring', visualDuration: 0.42, bounce: 0.12 }
const INSTANT: Transition = { duration: 0 }

type How = 'hover' | 'click' | 'keyboard' | 'touch'

const LINKS = [
  { href: HELP, icon: 'help', title: 'Help', sub: 'Set up and use every module' },
  { href: REPO, icon: 'code', title: 'GitHub', sub: 'The source code, GPL-3.0' },
  { href: ALL_RELEASES, icon: 'sparkle', title: 'What’s new', sub: 'Notes for every version' },
  { href: REPORT, icon: 'alert', title: 'Report a problem', sub: 'Found a bug? Tell us' },
] as const

// The parts of the page the notch names as you scroll into them.
const PARTS = [
  { selector: 'section[aria-labelledby="features-title"]', title: 'What it does', caption: 'Features' },
  { selector: 'section[aria-labelledby="proof-title"]', title: 'Light, and measured', caption: 'Speed and memory' },
  { selector: 'footer', title: 'Get PancakeNotch', caption: 'Download' },
]

export function TopBar() {
  const reduce = useReducedMotion() ?? false
  const [awake, setAwake] = useState(false)
  const [open, setOpen] = useState(false)
  const [how, setHow] = useState<How>('hover')
  const [peek, setPeek] = useState<number | null>(null) // which part of the page is showing underneath
  const [lastPeek, setLastPeek] = useState(0) // kept while the line fades out, so its words don't vanish first
  if (peek !== null && peek !== lastPeek) setLastPeek(peek)
  const [vw, setVw] = useState(() => (typeof window === 'undefined' ? 1280 : window.innerWidth))

  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const timer = useRef(0)
  const hovering = useRef(false)
  const hoverLocked = useRef(false) // closed with a click: hovering opens it again only after leaving

  const narrow = vw < 560
  const compactWidth = Math.min(COMPACT, vw - 24)
  const openWidth = Math.min(OPEN_MAX, vw - 16)
  // Two columns of links, or one on a phone, then the line at the bottom.
  const openHeight = narrow ? H + 8 + 4 * 50 + 3 * 2 + 8 + 30 + 8 : H + 8 + 2 * 54 + 4 + 8 + 30 + 8

  useEffect(() => {
    const resize = () => setVw(window.innerWidth)
    window.addEventListener('resize', resize)
    return () => window.removeEventListener('resize', resize)
  }, [])

  // The opening animation is five seconds; the notch wakes up as it ends (sooner with Reduce Motion).
  useEffect(() => {
    const wake = setTimeout(() => setAwake(true), reduce ? 600 : 4300)
    return () => clearTimeout(wake)
  }, [reduce])

  /* ---------- Opening and closing ---------- */

  const show = (by: How) => {
    setHow(by)
    setOpen(true)
    setPeek(null)
  }
  const close = () => setOpen(false)

  const enter = (event: PointerEvent) => {
    if (event.pointerType !== 'mouse' || !awake) return
    hovering.current = true
    clearTimeout(timer.current)
    if (!hoverLocked.current && !open) timer.current = window.setTimeout(() => show('hover'), 120)
  }
  const leave = (event: PointerEvent) => {
    if (event.pointerType !== 'mouse') return
    hovering.current = false
    hoverLocked.current = false
    clearTimeout(timer.current)
    if (open && how !== 'keyboard') timer.current = window.setTimeout(close, 300)
  }
  const toggle = (event: MouseEvent) => {
    clearTimeout(timer.current)
    if (open) {
      close()
      hoverLocked.current = hovering.current
    } else {
      const pointer = (event.nativeEvent as globalThis.PointerEvent).pointerType
      show(event.detail === 0 ? 'keyboard' : pointer === 'touch' ? 'touch' : 'click')
    }
  }
  // Tabbing out closes it.
  const blur = (event: FocusEvent) => {
    if (rootRef.current?.contains(event.relatedTarget as Node | null)) return
    setTimeout(() => {
      const now = document.activeElement
      if (now && now !== document.body && !rootRef.current?.contains(now) && !hovering.current) close()
    }, 0)
  }

  useEffect(() => {
    if (!open) return
    // Clicking or tapping anywhere else closes it; so does scrolling the page when the pointer isn't on it.
    let outside: number | null = null
    const down = (event: globalThis.PointerEvent) => {
      outside = rootRef.current?.contains(event.target as Node) ? null : event.pointerId
    }
    const up = (event: globalThis.PointerEvent) => {
      if (outside === event.pointerId) close()
      outside = null
    }
    const cancel = () => {
      outside = null
    }
    const startY = window.scrollY
    const scroll = () => {
      if (!hovering.current && Math.abs(window.scrollY - startY) > 48) close()
    }
    const escape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.preventDefault()
      close()
      if (rootRef.current?.contains(document.activeElement)) triggerRef.current?.focus()
    }
    document.addEventListener('pointerdown', down)
    document.addEventListener('pointerup', up)
    document.addEventListener('pointercancel', cancel)
    document.addEventListener('keydown', escape)
    window.addEventListener('scroll', scroll, { passive: true })
    return () => {
      document.removeEventListener('pointerdown', down)
      document.removeEventListener('pointerup', up)
      document.removeEventListener('pointercancel', cancel)
      document.removeEventListener('keydown', escape)
      window.removeEventListener('scroll', scroll)
    }
  }, [open])

  useEffect(() => () => clearTimeout(timer.current), [])

  /* ---------- Naming the part of the page you scroll into ---------- */

  const current = useRef<number | null>(null)
  const openRef = useRef(open)
  useEffect(() => {
    openRef.current = open
  }, [open])
  useEffect(() => {
    if (!awake) return
    const targets = PARTS.map((part) => document.querySelector(part.selector))
    const inView = new Set<number>()
    // A part counts once it crosses a line a little above the middle of the window.
    const watcher = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const index = targets.indexOf(entry.target)
          if (entry.isIntersecting) inView.add(index)
          else inView.delete(index)
        }
        const now = inView.size ? Math.max(...inView) : null
        if (now === current.current) return
        current.current = now
        if (now !== null && !openRef.current) setPeek(now)
      },
      { rootMargin: '-40% 0px -55% 0px' },
    )
    targets.forEach((target) => target && watcher.observe(target))
    return () => watcher.disconnect()
  }, [awake])

  useEffect(() => {
    if (peek === null) return
    const end = setTimeout(() => setPeek(null), 2600)
    return () => clearTimeout(end)
  }, [peek])

  /* ---------- Shape ---------- */

  const peeking = peek !== null && !open
  const size = open
    ? { width: openWidth, height: openHeight, radius: 28, ears: 1 }
    : awake
      ? { width: compactWidth + (peeking ? 20 : 0), height: H + (peeking ? PEEK : 0), radius: peeking ? 20 : 16, ears: 0.4 }
      : { width: BARE, height: H - 6, radius: 14, ears: 0.4 }
  // Opening overshoots; closing from open settles softly; waking up and the line underneath bounce a little.
  const wasOpen = useRef(false)
  const spring = reduce ? INSTANT : open ? OPEN : wasOpen.current ? CLOSE : SWITCH
  useEffect(() => {
    wasOpen.current = open
  }, [open])
  const tuck = 56 // asleep, the logo and the button hide under the middle

  return (
    <header inert={!awake} className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center">
      <m.div
        ref={rootRef}
        className="pointer-events-auto relative text-white"
        initial={false}
        animate={{ width: size.width, height: size.height }}
        transition={spring}
        onPointerEnter={enter}
        onPointerLeave={leave}
        onBlur={blur}
      >
        {/* Concave corners where the notch meets the top of the window. */}
        <m.span
          aria-hidden="true"
          className="absolute top-0 right-full z-1 size-[18px] origin-top-right bg-[radial-gradient(circle_at_0_100%,transparent_17.4px,#000_18px)]" // taste-skill-ignore: the notch's own shape
          initial={false}
          animate={{ scale: size.ears }}
          transition={spring}
        />
        <m.span
          aria-hidden="true"
          className="absolute top-0 left-full z-1 size-[18px] origin-top-left bg-[radial-gradient(circle_at_100%_100%,transparent_17.4px,#000_18px)]" // taste-skill-ignore: the notch's own shape
          initial={false}
          animate={{ scale: size.ears }}
          transition={spring}
        />

        <m.div
          className="absolute inset-0 overflow-hidden bg-black"
          initial={false}
          animate={{ borderBottomLeftRadius: size.radius, borderBottomRightRadius: size.radius, boxShadow: open ? OPEN_RING : awake ? RING : 'none' }}
          transition={spring}
        >
          {/* The whole closed notch opens it: click, tap or Enter. */}
          <button
            ref={triggerRef}
            type="button"
            aria-expanded={open}
            aria-controls="notch-panel"
            aria-label={open ? 'Close the menu' : 'Open the menu'}
            onClick={toggle}
            className="absolute inset-x-0 top-0 z-1 cursor-pointer rounded-b-[16px] focus-visible:outline-2 focus-visible:-outline-offset-4 focus-visible:outline-white/70"
            style={{ height: H }}
          />

          {/* The top row: the same in both states, so the logo and Download ride out with the edges as it opens. */}
          <div className="pointer-events-none absolute inset-x-0 top-0 z-2 flex items-center justify-between pr-[7px] pl-4" style={{ height: H }}>
            <m.a
              href="./"
              tabIndex={open ? 0 : -1}
              aria-hidden={!open}
              onClick={(event) => {
                event.preventDefault()
                close()
                window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' })
              }}
              className={cn(
                'group flex items-center gap-2 rounded-full py-1 pr-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white',
                open && 'pointer-events-auto',
              )}
              initial={false}
              animate={{ x: awake ? 0 : tuck, opacity: awake ? 1 : 0 }}
              transition={reduce ? { duration: 0.2 } : { ...SWITCH, opacity: { duration: 0.25, delay: awake ? 0.08 : 0 } }}
            >
              <Logo className="text-[1.3rem] transition-transform duration-300 ease-[cubic-bezier(.34,1.56,.64,1)] group-hover:-rotate-6 group-hover:scale-110" />
              <span className="font-display text-[15px] font-bold tracking-[-0.02em]">PancakeNotch</span>
            </m.a>

            <m.div
              className="flex items-center gap-1.5"
              initial={false}
              animate={{ x: awake ? 0 : -tuck, opacity: awake ? 1 : 0 }}
              transition={reduce ? { duration: 0.2 } : { ...SWITCH, opacity: { duration: 0.25, delay: awake ? 0.08 : 0 } }}
            >
              <AnimatePresence initial={false}>
                {open && (
                  <m.span
                    key="beta"
                    className="mr-0.5 rounded-full px-2.5 py-[5px] text-[11px] leading-none font-semibold text-white/80 ring-1 ring-white/20"
                    initial={{ opacity: 0, x: reduce ? 0 : 10, filter: 'blur(4px)' }}
                    animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }}
                    exit={{ opacity: 0, x: reduce ? 0 : 10, filter: 'blur(4px)', transition: { duration: 0.12 } }}
                    transition={{ duration: 0.3, delay: 0.1 }}
                  >
                    Beta
                  </m.span>
                )}
              </AnimatePresence>
              <a
                href={RELEASES}
                className="pointer-events-auto inline-flex h-[28px] items-center gap-1.5 rounded-full bg-white pr-3.5 pl-3 text-[13px] font-semibold text-black transition-[transform,background-color] duration-200 hover:scale-[1.04] hover:bg-white/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white active:scale-[.97]"
              >
                <Glyph name="download" className="text-[13px]" />
                Download
              </a>
            </m.div>
          </div>

          {/* The line underneath while you scroll into a new part of the page. */}
          <div
            aria-hidden="true"
            className={cn(
              'pointer-events-none absolute inset-x-0 flex items-center justify-center gap-2 px-4 text-[12.5px] leading-none font-semibold whitespace-nowrap transition-opacity',
              peeking ? 'opacity-100 delay-150 duration-300' : 'opacity-0 duration-100',
            )}
            style={{ top: H - 4, height: PEEK }}
          >
            <PeekLine index={lastPeek} shown={peeking} reduce={reduce} />
          </div>

          <AnimatePresence>
            {open && (
              <m.div
                key="panel"
                id="notch-panel"
                role="group"
                aria-label="Links"
                className="absolute top-0 left-1/2 origin-top"
                style={{ width: openWidth, height: openHeight, x: '-50%' }}
                initial={reduce ? { opacity: 0 } : { opacity: 0, filter: 'blur(10px)', scaleY: 0.6 }}
                animate={{ opacity: 1, filter: 'blur(0px)', scaleY: 1 }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, filter: 'blur(10px)', scaleY: 0.6, transition: { duration: 0.15 } }}
                transition={reduce ? { duration: 0.2 } : { opacity: { duration: 0.3, delay: 0.04 }, filter: { duration: 0.35 }, scaleY: OPEN }}
              >
                <div className="absolute inset-x-0 bottom-0 flex flex-col px-2.5 pt-2 pb-2" style={{ top: H }}>
                  <ul className={cn('grid', narrow ? 'grid-cols-1 gap-0.5' : 'grid-cols-2 gap-1')}>
                    {LINKS.map((link, i) => (
                      <m.li
                        key={link.href}
                        initial={reduce ? { opacity: 0 } : { opacity: 0, y: -8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={reduce ? { duration: 0.2 } : { type: 'spring', visualDuration: 0.4, bounce: 0.15, delay: 0.06 + i * 0.035 }}
                      >
                        <LinkRow {...link} tall={!narrow} />
                      </m.li>
                    ))}
                  </ul>
                  <m.p
                    className="mx-2 mt-auto flex h-[30px] items-center justify-between gap-3 border-t border-white/10 text-[11.5px] text-white/45" // taste-skill-ignore: the app's own divider
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ duration: 0.3, delay: 0.2 }}
                  >
                    <span className="truncate">{narrow ? 'Free and open source' : 'Free and open source, GPL-3.0'}</span>
                    <span className="truncate">macOS 15 or later · Apple Silicon</span>
                  </m.p>
                </div>
              </m.div>
            )}
          </AnimatePresence>
        </m.div>
      </m.div>
    </header>
  )
}

function LinkRow({ href, icon, title, sub, tall }: { href: string; icon: GlyphName; title: string; sub: string; tall: boolean }) {
  const external = href.startsWith('http')
  return (
    <a
      href={href}
      className={cn(
        'group flex items-center gap-3 rounded-[14px] px-2.5 transition-colors hover:bg-white/8 focus-visible:bg-white/8 focus-visible:outline-none',
        tall ? 'h-[54px]' : 'h-[50px]',
      )}
    >
      <span className="grid size-[34px] flex-none place-items-center rounded-[10px] bg-white/10 text-[16px] transition-colors group-hover:bg-white/14">
        <Glyph name={icon} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[13.5px] leading-[1.25] font-semibold">{title}</span>
        <span className="block truncate text-[12px] leading-[1.35] text-white/50">{sub}</span>
      </span>
      <Glyph
        name={external ? 'arrowUpRight' : 'arrowRight'}
        className="mr-1 text-[14px] text-white/0 transition-[color,translate] duration-200 group-hover:translate-x-0.5 group-hover:text-white/60 group-focus-visible:text-white/60"
      />
    </a>
  )
}

const DOT = 5
const PILL = 15
const ROW = 'flex items-center gap-2 whitespace-nowrap'

/* The line underneath: the page dots, then the part's name and a caption. When the part changes, nothing
   jumps: the pill stretches across to its new dot, the old words roll out and the new ones roll in from
   the way you scrolled, and the space for the words grows or shrinks smoothly, so the whole line glides
   to its new middle instead of snapping there. */
function PeekLine({ index, shown, reduce }: { index: number; shown: boolean; reduce: boolean }) {
  // Which way you went, so the words roll the same way as the page.
  const [prev, setPrev] = useState(index)
  const [dir, setDir] = useState(1)
  if (index !== prev) {
    setDir(index > prev ? 1 : -1)
    setPrev(index)
  }
  // Arriving with the line, the pill waits for it to fade in, so you see it move; already showing, it goes at once.
  const wasShown = useRef(shown)
  const delay = wasShown.current ? 0 : 0.22
  useEffect(() => {
    wasShown.current = shown
  }, [shown])

  // Each part's words, measured once (and again when the fonts arrive), so their space can be animated.
  const measure = useRef<(HTMLSpanElement | null)[]>([])
  const [widths, setWidths] = useState<number[] | null>(null)
  useLayoutEffect(() => {
    const read = () => setWidths(measure.current.map((el) => Math.ceil(el?.getBoundingClientRect().width ?? 0)))
    read()
    document.fonts?.ready.then(read)
  }, [])

  const glide: Transition = reduce ? { duration: 0 } : { type: 'spring', visualDuration: 0.45, bounce: 0.15, delay }
  const roll = reduce
    ? { enter: { opacity: 0 }, center: { opacity: 1 }, exit: { opacity: 0 } }
    : {
        enter: (d: number) => ({ opacity: 0, y: 14 * d, filter: 'blur(3px)' }),
        center: { opacity: 1, y: 0, filter: 'blur(0px)' },
        exit: (d: number) => ({ opacity: 0, y: -14 * d, filter: 'blur(3px)' }),
      }

  return (
    <>
      <span className="flex flex-none items-center gap-[4px]">
        {PARTS.map((_, i) => (
          <m.span
            key={i}
            className="block h-[5px] rounded-full bg-white"
            initial={false}
            animate={{ width: i === index ? PILL : DOT, opacity: i === index ? 1 : 0.3 }}
            transition={glide}
          />
        ))}
      </span>

      <m.span
        // Cut off only above and below (for the roll), never at the sides, so a longer name isn't clipped while its space grows.
        className="relative block h-[18px] [clip-path:inset(0_-200px)]"
        initial={false}
        animate={{ width: widths ? widths[index] : 'auto' }}
        transition={reduce ? { duration: 0 } : { type: 'spring', visualDuration: 0.45, bounce: 0.1 }}
      >
        <AnimatePresence initial={false} custom={dir}>
          <m.span
            key={index}
            custom={dir}
            variants={roll}
            initial="enter"
            animate="center"
            exit="exit"
            transition={reduce ? { duration: 0.2 } : { type: 'spring', visualDuration: 0.4, bounce: 0.12 }}
            className={cn(ROW, 'absolute inset-y-0 left-0')}
          >
            <Words index={index} />
          </m.span>
        </AnimatePresence>
      </m.span>

      {/* Out of sight: each part's words at full size, for measuring. */}
      <span aria-hidden="true" className="invisible absolute top-0 left-0">
        {PARTS.map((_, i) => (
          <span
            key={i}
            ref={(el) => {
              measure.current[i] = el
            }}
            className={cn(ROW, 'absolute top-0 left-0')}
          >
            <Words index={i} />
          </span>
        ))}
      </span>
    </>
  )
}

function Words({ index }: { index: number }) {
  return (
    <>
      <span>{PARTS[index].title}</span>
      <span className="font-normal text-white/55">{PARTS[index].caption}</span>
    </>
  )
}

const GLYPHS = {
  help: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M9.6 9.6a2.5 2.5 0 0 1 4.85.85c0 1.65-2.45 2.15-2.45 3.6M12 16.9h.01" />
    </>
  ),
  code: <path d="m8.5 7.5-4.5 4.5 4.5 4.5M15.5 7.5l4.5 4.5-4.5 4.5M13.4 5.5l-2.8 13" />,
  sparkle: <path d="m12 3.5 1.9 6.6 6.6 1.9-6.6 1.9-1.9 6.6-1.9-6.6L3.5 12l6.6-1.9Z" />,
  alert: <path d="M12 9v3.8M12 16.2h.01M10.3 4.6 3.4 16.8A2 2 0 0 0 5.1 19.8h13.8a2 2 0 0 0 1.7-3L13.7 4.6a2 2 0 0 0-3.4 0Z" />,
  download: <path d="M12 4.5v10.5M7.5 10.5 12 15l4.5-4.5M5.5 19.5h13" />,
  arrowRight: <path d="M4.5 12h14M13.5 6.5 19 12l-5.5 5.5" />,
  arrowUpRight: <path d="M7 17 17 7M8.5 7H17v8.5" />,
} satisfies Record<string, ReactNode>

type GlyphName = keyof typeof GLYPHS

function Glyph({ name, className }: { name: GlyphName; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className={cn('size-[1em] flex-none fill-none stroke-current stroke-2 [stroke-linecap:round] [stroke-linejoin:round]', className)}
    >
      {GLYPHS[name]}
    </svg>
  )
}
