import { useEffect, useState } from 'react'
import { useReducedMotion } from 'motion/react'
import { useOnceInView } from '@/lib/useOnceInView'

/* The "light, and measured" proof: three big numbers that count up (or down) when they come into view,
   and a terminal that types out the two memory checks the project runs. The numbers are the limits
   those checks enforce (README and the memory scripts), not a reading, so nothing here is made up.
   Reduce Motion: everything is there from the start. */

const STATS = [
  { say: 'under', mark: '<', from: 0, to: 50, unit: 'MB', label: 'of memory when idle' },
  { say: 'under', mark: '<', from: 0, to: 100, unit: 'MB', label: 'of memory at its busiest' },
  { say: 'about', mark: '~', from: 100, to: 0, unit: '%', label: 'CPU when nothing is happening' },
]

type Line = { kind: 'command' | 'result' | 'prompt'; text: string }

const LINES: Line[] = [
  { kind: 'command', text: 'scripts/check-memory.sh' },
  { kind: 'result', text: 'idle footprint under 50 MiB' },
  { kind: 'command', text: 'scripts/check-shelf-memory.sh' },
  { kind: 'result', text: 'peak footprint under 100 MiB' },
  { kind: 'prompt', text: '' },
]

const TYPE_MS = 38 // per typed letter
const PAUSE_MS = 480 // between a command and its result, and before the next command

/** When each line starts (ms after the terminal comes into view) and how long it takes. */
const TIMELINE = (() => {
  let at = 250
  return LINES.map((line) => {
    const duration = line.kind === 'command' ? line.text.length * TYPE_MS : 0
    const entry = { start: at, duration }
    at += duration + PAUSE_MS
    return entry
  })
})()
const TOTAL_MS = TIMELINE[TIMELINE.length - 1].start

export function Proof() {
  const reduce = useReducedMotion() ?? false
  const [numbersRef, numbersSeen] = useOnceInView<HTMLDivElement>(0.5)
  const [terminalRef, terminalSeen] = useOnceInView<HTMLDivElement>(0.5)

  return (
    <section aria-labelledby="proof-title" className="relative py-[clamp(4rem,12svh,8rem)]">
      <div className="mx-auto grid max-w-[86rem] items-center px-(--page-gutter) gap-[clamp(2.5rem,6svh,4rem)] lg:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] lg:gap-[clamp(2.5rem,5vw,5.5rem)]">
        <div>
          <h2
            id="proof-title"
            className="font-display text-[clamp(2rem,4.2vw,3.75rem)] leading-none font-bold tracking-[-0.035em] text-ink"
          >
            Light, and measured.
          </h2>
          <div ref={terminalRef} className="mt-[clamp(1.5rem,4svh,2.5rem)]">
            <Terminal play={terminalSeen} instant={reduce} />
          </div>
        </div>

        <div ref={numbersRef} className="grid gap-[clamp(1.5rem,5svh,3rem)]">
          {STATS.map((stat) => (
            <Stat key={stat.label} {...stat} play={numbersSeen} instant={reduce} />
          ))}
        </div>
      </div>
    </section>
  )
}

type StatProps = (typeof STATS)[number] & { play: boolean; instant: boolean }

function Stat({ say, mark, from, to, unit, label, play, instant }: StatProps) {
  const value = useCount(from, to, 1700, play, instant)
  return (
    <div>
      <span className="sr-only">
        {say} {to} {unit === '%' ? 'percent' : 'megabytes'} {label}
      </span>
      <p aria-hidden="true" className="font-display text-[clamp(3.5rem,7vw,6.5rem)] leading-none font-bold tracking-[-0.045em] text-ink tabular-nums">
        {mark}
        {value}
        <span className="ml-2 text-[.4em] tracking-normal text-soft">{unit}</span>
      </p>
      <p aria-hidden="true" className="mt-2 text-[clamp(1rem,.9rem+.4vw,1.25rem)] text-soft">
        {label}
      </p>
    </div>
  )
}

/** A whole number that eases from `from` to `to` once `play` turns true. */
function useCount(from: number, to: number, ms: number, play: boolean, instant: boolean) {
  const [value, setValue] = useState(instant ? to : from)

  useEffect(() => {
    if (instant) {
      setValue(to)
      return
    }
    if (!play) return
    const began = performance.now()
    let frame = 0
    const tick = (now: number) => {
      const t = Math.min((now - began) / ms, 1)
      setValue(Math.round(from + (to - from) * (1 - Math.pow(1 - t, 3))))
      if (t < 1) frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [from, to, ms, play, instant])

  return value
}

/** A Mac-style terminal window that types its commands and prints their results. */
function Terminal({ play, instant }: { play: boolean; instant: boolean }) {
  const [elapsed, setElapsed] = useState(instant ? TOTAL_MS + 1 : 0)

  useEffect(() => {
    if (instant) {
      setElapsed(TOTAL_MS + 1)
      return
    }
    if (!play) return
    const began = performance.now()
    let frame = 0
    const tick = (now: number) => {
      const t = now - began
      setElapsed(t)
      if (t <= TOTAL_MS) frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [play, instant])

  return (
    <div className="overflow-hidden rounded-2xl bg-[#0b0b0b] ring-1 ring-white/10">
      <div aria-hidden="true" className="flex gap-2 px-4 py-3.5">
        {[0, 1, 2].map((dot) => (
          <span key={dot} className="size-2.5 rounded-full bg-white/18" />
        ))}
      </div>
      <p className="sr-only">
        {LINES.filter((line) => line.text).map((line) => line.text).join('. ')}.
      </p>
      <div
        aria-hidden="true"
        className="px-5 pt-1 pb-6 font-mono text-[clamp(.8125rem,.7rem+.35vw,1rem)] leading-[1.9]" // taste-skill-ignore: a terminal shows literal commands
      >
        {LINES.map((line, i) => {
          const { start, duration } = TIMELINE[i]
          const started = elapsed >= start
          // Letters of a command typed so far. The rest is kept (invisible) so the window never changes size.
          const typed = Math.max(0, Math.min(line.text.length, Math.floor(((elapsed - start) / (duration || 1)) * line.text.length)))
          return (
            <div key={i} className="flex gap-3 whitespace-pre-wrap">
              <span className={started && line.kind !== 'result' ? 'text-soft' : 'invisible'}>$</span>
              {line.kind === 'command' && (
                <span className="text-ink">
                  {line.text.slice(0, typed)}
                  <span className="invisible">{line.text.slice(typed)}</span>
                </span>
              )}
              {line.kind === 'result' && (
                <span className={started ? 'text-soft' : 'invisible'}>
                  <span className="text-ink">PASS</span> {line.text}
                </span>
              )}
              {line.kind === 'prompt' && started && <span className="caret inline-block h-[1.1em] w-[.55em] translate-y-[.25em] bg-white" />}
            </div>
          )
        })}
      </div>
    </div>
  )
}
