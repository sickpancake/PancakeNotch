import { useEffect, useId, useRef, useState, type CSSProperties, type PointerEvent, type ReactNode } from 'react'
import { useReducedMotion } from 'motion/react'
import { cn } from '@/lib/utils'
import { Cover, Icon, StatusMark, Thumb, leftTone, type IconName } from './notch/art'
import { EXAMPLES, type ThreadState } from './notch/data'

/* What the app does, as a row of cards you can scroll sideways: swipe, drag with the mouse, use the
   arrow buttons or the arrow keys. Each card has a small drawing made from the same pieces as the live
   notch above (its covers, icons and Shelf previews), a title and one line. The row runs off the right
   edge on purpose, so it's clear there's more. What's new in the latest release carries a small "New" tag. */

type Feature = { title: string; line: string; art: ReactNode; top?: boolean; fresh?: boolean }

const FEATURES: Feature[] = [
  { title: 'Now Playing', line: 'Music from any app: the cover and sound bars beside the notch, the controls inside.', art: <NowPlayingArt />, top: true },
  { title: 'Shelf', line: 'Drop files, notes and links on the notch. Pick them up later.', art: <ShelfArt /> },
  { title: 'Convert', line: 'Turn pictures, PDFs, sound and video into another format in one click.', art: <ConvertArt />, fresh: true },
  { title: 'Timer and Stopwatch', line: 'Count down or keep laps. The time left waits beside the notch.', art: <TimerArt />, top: true, fresh: true },
  { title: 'Keep Awake', line: 'Keep your Mac and its screen awake while your agents work.', art: <KeepAwakeArt />, fresh: true },
  { title: 'Agents', line: 'Claude Code, Codex and Cursor at work. Allow or Deny from the notch.', art: <AgentsArt /> },
  { title: 'AI Usage', line: 'Your Claude and Codex limits and tokens, and a heads-up when one resets.', art: <UsageArt /> },
  { title: 'Module Menu', line: 'Every module in one place. Your favorites get a tab.', art: <MenuArt /> },
  { title: 'Statistics', line: 'What you listen to, and how light the app stays.', art: <StatsArt /> },
  { title: 'Full screen', line: 'Steps aside while you watch a video.', art: <FullScreenArt /> },
  { title: 'Your shortcut', line: 'Open it from the keyboard, with keys you choose.', art: <ShortcutArt /> },
  { title: 'Open on click', line: 'Rather it opened only when you click? One switch.', art: <ClickArt />, top: true, fresh: true },
]

// The row starts where the page's text starts, and bleeds off the right edge.
const GUTTER = 'max(var(--page-gutter), calc((100% - 86rem) / 2 + var(--page-gutter)))'
const ROW_STYLE: CSSProperties = { paddingInline: GUTTER, scrollPaddingInline: GUTTER }

export function FeatureRow() {
  const reduce = useReducedMotion() ?? false
  const rowRef = useRef<HTMLDivElement>(null)
  const drag = useRef<{ x: number; left: number } | null>(null)
  const [dragging, setDragging] = useState(false)
  const [edges, setEdges] = useState({ start: true, end: false })

  const measure = () => {
    const row = rowRef.current
    if (!row) return
    setEdges({ start: row.scrollLeft < 4, end: row.scrollLeft + row.clientWidth >= row.scrollWidth - 4 })
  }

  useEffect(() => {
    const row = rowRef.current
    if (!row) return
    measure()
    const sizes = new ResizeObserver(measure)
    sizes.observe(row)
    return () => sizes.disconnect()
  }, [])

  const step = (direction: 1 | -1) => {
    const row = rowRef.current
    const card = row?.querySelector('li')
    if (!row || !card) return
    row.scrollBy({ left: direction * (card.getBoundingClientRect().width + 16), behavior: reduce ? 'auto' : 'smooth' })
  }

  // Dragging with a mouse (touch and trackpads already scroll sideways by themselves).
  const down = (event: PointerEvent<HTMLDivElement>) => {
    const row = rowRef.current
    if (!row || event.pointerType !== 'mouse' || event.button !== 0) return
    drag.current = { x: event.clientX, left: row.scrollLeft }
    row.setPointerCapture(event.pointerId)
    setDragging(true)
  }
  const move = (event: PointerEvent<HTMLDivElement>) => {
    const row = rowRef.current
    if (row && drag.current) row.scrollLeft = drag.current.left - (event.clientX - drag.current.x)
  }
  const up = () => {
    drag.current = null
    setDragging(false)
  }

  return (
    <section aria-labelledby="features-title" className="relative py-[clamp(4rem,12svh,8rem)]">
      <div className="mx-auto flex max-w-[86rem] items-end justify-between gap-6 px-(--page-gutter)">
        <h2
          id="features-title"
          className="font-display text-[clamp(2rem,4.2vw,3.75rem)] leading-none font-bold tracking-[-0.035em] text-ink"
        >
          What it does.
        </h2>
        <div className="flex gap-2">
          <ArrowButton label="Previous features" disabled={edges.start} onClick={() => step(-1)} />
          <ArrowButton label="Next features" disabled={edges.end} flip onClick={() => step(1)} />
        </div>
      </div>

      <div
        ref={rowRef}
        role="region"
        aria-label="Features. Scroll sideways to see more."
        tabIndex={0}
        style={ROW_STYLE}
        onScroll={measure}
        onPointerDown={down}
        onPointerMove={move}
        onPointerUp={up}
        onPointerCancel={up}
        className={cn(
          'mt-[clamp(2rem,6svh,3.5rem)] overflow-x-auto overscroll-x-contain pb-2 [scrollbar-width:none] select-none focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-white [&::-webkit-scrollbar]:hidden',
          dragging ? 'cursor-grabbing' : 'cursor-grab snap-x snap-mandatory',
        )}
      >
        <ul className="flex w-max gap-4">
          {FEATURES.map((feature) => (
            <li key={feature.title} className="w-[min(80vw,21rem)] shrink-0 snap-start">
              <article className="h-full rounded-2xl bg-[#101010] p-2.5 ring-1 ring-white/8 transition-colors hover:bg-[#151515]">
                <ArtFrame top={feature.top}>{feature.art}</ArtFrame>
                <div className="px-2 pt-4 pb-3">
                  <h3 className="flex items-center gap-2 text-lg font-semibold tracking-[-0.01em] text-ink">
                    {feature.title}
                    {feature.fresh && (
                      <span className="rounded-full px-2 py-0.5 text-[11px] leading-none font-semibold tracking-normal text-soft ring-1 ring-white/15">
                        New
                      </span>
                    )}
                  </h3>
                  <p className="mt-1.5 text-[15px] leading-snug text-soft">{feature.line}</p>
                </div>
              </article>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}

function ArrowButton({ label, disabled, flip, onClick }: { label: string; disabled: boolean; flip?: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className="grid size-11 place-items-center rounded-full bg-white/8 text-lg text-ink transition-colors hover:bg-white/16 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white disabled:opacity-30 disabled:hover:bg-white/8"
    >
      <Icon name="chevronLeft" className={flip ? 'rotate-180' : undefined} />
    </button>
  )
}

/** The picture area of a card: a bed of faint square dots, like the page's own background, with the drawing on it. */
function ArtFrame({ top, children }: { top?: boolean; children: ReactNode }) {
  const id = useId()
  return (
    <div className="relative aspect-[4/3] overflow-hidden rounded-xl bg-[#080808]">
      <svg aria-hidden="true" className="absolute inset-0 size-full">
        <defs>
          <pattern id={id} width="14" height="14" patternUnits="userSpaceOnUse">
            <rect x="6" y="6" width="2" height="2" fill="#fff" fillOpacity=".08" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill={`url(#${CSS.escape(id)})`} />
      </svg>
      <div className={cn('relative flex size-full justify-center', top ? 'items-start' : 'items-center')}>{children}</div>
    </div>
  )
}

const SURFACE = 'bg-black ring-1 ring-white/10'

/** The sound bars of a playing song: each swings between its own heights. */
function Bars() {
  const bars = [
    [0.3, 0.9, 0.7],
    [0.5, 1, 0.55],
    [0.25, 0.7, 0.8],
    [0.6, 0.95, 0.5],
    [0.35, 0.8, 0.65],
  ]
  return (
    <span aria-hidden="true" className="flex h-5 items-center gap-[3px]">
      {bars.map(([from, to, seconds], i) => (
        <span
          key={i}
          className="h-full w-[3px] rounded-full bg-white motion-safe:[animation:bar-dance_var(--seconds)_ease-in-out_infinite_alternate] motion-reduce:scale-y-[.6]"
          style={{ '--from': from, '--to': to, '--seconds': `${seconds}s`, animationDelay: `${-i * 0.17}s` } as CSSProperties}
        />
      ))}
    </span>
  )
}

function NowPlayingArt() {
  return (
    <div className={cn('flex w-[14rem] items-center justify-between rounded-b-[1.4rem] px-3.5 py-2.5', SURFACE)}>
      <span className="block size-9 overflow-hidden rounded-[10px]">
        <Cover song={0} />
      </span>
      <Bars />
    </div>
  )
}

function ShelfArt() {
  return (
    <div className={cn('flex items-end gap-2.5 rounded-2xl p-3.5', SURFACE)}>
      {EXAMPLES.slice(0, 3).map((item) => (
        <Thumb key={item.id} item={item} />
      ))}
    </div>
  )
}

function AgentsArt() {
  const rows: { mark: ThreadState; width: string }[] = [
    { mark: 'working', width: 'w-24' },
    { mark: 'needs', width: 'w-16' },
    { mark: 'done', width: 'w-20' },
  ]
  return (
    <div aria-hidden="true" className={cn('w-[14.5rem] space-y-3.5 rounded-2xl p-3.5', SURFACE)}>
      {rows.map(({ mark, width }) => (
        <div key={mark} className="flex items-center gap-2.5">
          <StatusMark state={mark} className="text-lg" />
          <span className={cn('h-1.5 rounded-full bg-white/18', width)} />
          {mark === 'needs' && <span className="ml-auto grid h-5 place-items-center rounded-full bg-white px-2.5 text-[11px] leading-none font-semibold text-black">Allow</span>}
        </div>
      ))}
    </div>
  )
}

function UsageArt() {
  const limits = [
    { name: 'Session', left: 63, pace: 55 },
    { name: 'Weekly', left: 77, pace: 80 },
  ]
  return (
    <div aria-hidden="true" className={cn('w-[14.5rem] space-y-4 rounded-2xl p-3.5', SURFACE)}>
      {limits.map(({ name, left, pace }) => (
        <div key={name}>
          <div className="flex justify-between text-[11px] leading-none font-medium text-soft">
            <span>{name}</span>
            <span className="text-ink tabular-nums">{left}% left</span>
          </div>
          <div className="relative mt-2 h-1.5 rounded-full bg-white/12">
            <span className={cn('block h-full rounded-full bg-current', leftTone(left))} style={{ width: `${left}%` }} />
            <span className="absolute -top-1 h-3.5 w-0.5 rounded-full bg-white/45" style={{ left: `${pace}%` }} />
          </div>
        </div>
      ))}
    </div>
  )
}

function MenuArt() {
  const favorites: IconName[] = ['note', 'tray', 'grid']
  return (
    <div className={cn('w-[13.5rem] rounded-2xl p-3.5', SURFACE)}>
      <div className="grid grid-cols-3 gap-2">
        {favorites.map((name) => (
          <span key={name} className="grid h-11 place-items-center rounded-xl bg-[#1f1f1f] text-xl text-ink">
            <Icon name={name} />
          </span>
        ))}
      </div>
      <div className="mt-3.5 space-y-2.5">
        {[0, 1].map((row) => (
          <div key={row} className="flex items-center gap-2.5">
            <span className="size-5 rounded-md bg-[#1f1f1f]" />
            <span className={cn('h-1.5 rounded-full bg-white/18', row ? 'w-16' : 'w-24')} />
          </div>
        ))}
      </div>
    </div>
  )
}

function StatsArt() {
  return (
    <div className="flex h-[6.5rem] items-end gap-2.5">
      {[0.35, 0.55, 0.4, 0.8, 0.6, 0.95, 0.7].map((height, i) => (
        <span key={i} className="w-3.5 rounded-sm bg-white" style={{ height: `${height * 100}%`, opacity: 0.25 + 0.75 * height }} />
      ))}
    </div>
  )
}

function FullScreenArt() {
  return (
    <div className="relative h-[7rem] w-44 rounded-lg bg-[#262626] ring-1 ring-white/10">
      {/* The notch, hidden: just its outline is left. */}
      <span className="absolute top-0 left-1/2 h-4 w-16 -translate-x-1/2 rounded-b-lg border border-t-0 border-dashed border-white/40" />
      <Icon name="play" className="absolute inset-0 m-auto text-3xl text-white/55" />
    </div>
  )
}

function ShortcutArt() {
  return (
    <div className="flex items-center gap-2.5">
      {['⌥', '⌘'].map((key) => (
        <kbd key={key} className="grid size-12 place-items-center rounded-xl bg-[#1f1f1f] font-sans text-xl text-ink ring-1 ring-white/10">
          {key}
        </kbd>
      ))}
      <kbd className="grid h-12 w-24 place-items-center rounded-xl bg-[#1f1f1f] font-sans text-sm text-ink ring-1 ring-white/10">Space</kbd>
    </div>
  )
}

function ConvertArt() {
  const formats = ['PNG', 'HEIC', 'PDF']
  return (
    <div aria-hidden="true" className={cn('flex items-center gap-3 rounded-2xl p-3.5', SURFACE)}>
      <Thumb item={EXAMPLES.find((item) => item.kind === 'file' && item.thumb === 'photo') ?? EXAMPLES[0]} />
      <Icon name="arrowRight" className="text-lg text-soft" />
      <div className="grid gap-1.5">
        {formats.map((format, i) => (
          <span
            key={format}
            className={cn(
              'grid h-6 w-14 place-items-center rounded-full text-[11px] leading-none font-semibold',
              i === 0 ? 'bg-white text-black' : 'bg-[#1f1f1f] text-ink',
            )}
          >
            {format}
          </span>
        ))}
      </div>
    </div>
  )
}

/** The closed notch with a timer running beside it: a ring that has drained a little, and the time left. */
function TimerArt() {
  const left = 0.72 // share of the ring still to go
  return (
    <div aria-hidden="true" className={cn('flex w-[14rem] items-center justify-between rounded-b-[1.4rem] px-3.5 py-2.5', SURFACE)}>
      <span className="size-9" />
      <span className="flex items-center gap-2 text-[15px] font-semibold text-ink tabular-nums">
        <svg viewBox="0 0 20 20" className="size-[18px] -rotate-90">
          <circle cx="10" cy="10" r="7.5" fill="none" stroke="#fff" strokeOpacity=".2" strokeWidth="2.5" />
          <circle cx="10" cy="10" r="7.5" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" pathLength="1" strokeDasharray={`${left} 1`} />
        </svg>
        7:14
      </span>
    </div>
  )
}

/** A cup beside an "on" switch. */
function KeepAwakeArt() {
  return (
    <div aria-hidden="true" className={cn('flex w-[13.5rem] items-center gap-3 rounded-2xl p-3.5', SURFACE)}>
      <span className="grid size-10 place-items-center rounded-xl bg-[#1f1f1f] text-xl text-ink">
        <Icon name="cup" />
      </span>
      <span className="h-1.5 w-16 rounded-full bg-white/18" />
      <span className="ml-auto flex h-6 w-10 items-center justify-end rounded-full bg-white p-0.5">
        <span className="size-5 rounded-full bg-black" />
      </span>
    </div>
  )
}

/** The closed notch, and a pointer clicking just under it. */
function ClickArt() {
  return (
    <div aria-hidden="true" className="flex flex-col items-center">
      <span className="block h-7 w-32 rounded-b-2xl bg-black ring-1 ring-white/10" />
      <Icon name="cursor" className="mt-9 text-5xl text-ink" />
    </div>
  )
}
