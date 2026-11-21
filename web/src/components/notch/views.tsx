import { useEffect, useReducer, useState, type ReactNode } from 'react'
import { TileSwap } from '@/components/TileSwap'
import { cn } from '@/lib/utils'
import { Cover, Icon, StatusMark, TOOL_ICON, Thumb, type IconName } from './art'
import { SONGS, clock, count, kindOf, nameOf, type Item, type Module, type Thread } from './data'
import { positionAt, type Player, type PlayerActions } from './player'

/* What the open notch shows: the player, the Shelf, the agents and Home, at the app's sizes (AI Usage is in usageViews.tsx). */

const control = 'grid cursor-pointer place-items-center rounded-[10px] text-white transition-[background-color,color,transform] duration-150 hover:bg-white/9 active:scale-90 motion-reduce:active:scale-100'

/* ---------- Now Playing ---------- */

/** The album art. A new song's cover builds in over the old one, pixel by pixel. */
function Art({ song, small }: { song: number; small: boolean }) {
  // Two layers take turns: the new cover goes into the hidden one, then they swap.
  const [layers, setLayers] = useState<[number, number]>([song, song])
  const [second, setSecond] = useState(false)
  const [shown, setShown] = useState(song)
  if (song !== shown) {
    setShown(song)
    setLayers(second ? [song, layers[1]] : [layers[0], song])
    setSecond(!second)
  }
  return (
    <div className={cn('flex-none overflow-hidden', small ? 'size-[88px] rounded-xl' : 'size-28 rounded-[14px]')}>
      <TileSwap first={<Cover song={layers[0]} />} second={<Cover song={layers[1]} />} showSecond={second} tile={14} duration={420} tileDuration={320} />
    </div>
  )
}

export function NowPlayingView({ player, actions, visible, narrow }: { player: Player; actions: PlayerActions; visible: boolean; narrow: boolean }) {
  const song = SONGS[player.song]
  const [dragging, setDragging] = useState(false)

  // Once a second while it plays and someone can see it; the bar glides toward the next second.
  const [, tick] = useReducer((n: number) => n + 1, 0)
  const ticking = player.playing && visible && !dragging
  useEffect(() => {
    if (!ticking) return
    const timer = setInterval(tick, 1000)
    return () => clearInterval(timer)
  }, [ticking])

  const pos = positionAt(player, performance.now())
  const shownAt = ticking ? Math.min(song.duration, pos + 1) : pos
  const share = shownAt / song.duration

  return (
    <div className={cn('flex h-full', narrow ? 'gap-3.5' : 'gap-[18px]')}>
      <Art song={player.song} small={narrow} />
      <div className="flex min-w-0 flex-1 flex-col justify-between pt-1">
        <div>
          <p className="truncate text-[15px] leading-[1.25] font-semibold">{song.title}</p>
          <p className="mt-[3px] truncate text-[12.5px] leading-[1.3] text-white/55">
            {song.artist} · {song.album}
          </p>
        </div>

        <div className="flex items-center gap-2.5 text-[10.5px] leading-none font-medium text-white/60 tabular-nums">
          <span className="w-10 flex-none">{clock(pos)}</span>
          <div className="group relative flex h-4 flex-1 items-center">
            <span className="absolute inset-x-0 h-1 rounded-sm bg-white/12" />
            {/* Keyed by the last jump, so a new song or a seek lands at once instead of sliding there. */}
            <span
              key={`fill-${player.song}-${player.since}`}
              className={cn('absolute inset-x-0 h-1 origin-left rounded-sm bg-white', ticking && 'transition-transform duration-1000 ease-linear')}
              style={{ transform: `scaleX(${share})` }}
            />
            <span
              key={`knob-${player.song}-${player.since}`}
              className={cn(
                'pointer-events-none absolute top-0.5 size-3 rounded-full bg-white opacity-0 transition-opacity group-hover:opacity-100 group-has-focus-visible:opacity-100 group-has-focus-visible:outline-2 group-has-focus-visible:outline-offset-2 group-has-focus-visible:outline-white',
                ticking && 'transition-[opacity,left] duration-1000 ease-linear',
              )}
              style={{ left: `calc(${share} * (100% - 12px))` }}
            />
            <input
              type="range"
              min={0}
              max={song.duration}
              step={1}
              value={Math.floor(pos)}
              aria-label="Song position"
              aria-valuetext={`${clock(pos)} of ${clock(song.duration)}`}
              onChange={(event) => actions.seek(Number(event.target.value))}
              onPointerDown={() => setDragging(true)}
              onPointerUp={() => setDragging(false)}
              onBlur={() => setDragging(false)}
              className="absolute inset-0 z-1 m-0 size-full cursor-pointer opacity-0"
            />
          </div>
          <span className="w-11 flex-none text-right">-{clock(song.duration - pos)}</span>
        </div>

        <div className="grid grid-cols-[1fr_auto_1fr] items-center">
          <Toggle label="Shuffle" icon="shuffle" on={player.shuffle} onClick={() => actions.toggle('shuffle')} className="justify-self-start" />
          <div className="flex items-center gap-1">
            <button type="button" aria-label="Previous" title="Previous" onClick={() => actions.skip(-1)} className={cn(control, 'h-8 w-10 text-xl')}>
              <Icon name="back" />
            </button>
            <button
              type="button"
              aria-label={player.playing ? 'Pause' : 'Play'}
              onClick={() => actions.play(!player.playing)}
              className={cn(control, 'h-9 w-11 text-2xl')}
            >
              <Icon name={player.playing ? 'pause' : 'play'} />
            </button>
            <button type="button" aria-label="Next" title="Next" onClick={() => actions.skip(1)} className={cn(control, 'h-8 w-10 text-xl')}>
              <Icon name="forward" />
            </button>
          </div>
          <Toggle label="Repeat" icon="repeat" on={player.repeat} onClick={() => actions.toggle('repeat')} className="justify-self-end" />
        </div>
      </div>
    </div>
  )
}

function Toggle({ label, icon, on, onClick, className }: { label: string; icon: IconName; on: boolean; onClick: () => void; className?: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      aria-pressed={on}
      onClick={onClick}
      className={cn(control, 'size-[30px] rounded-full text-[15px] text-white/50', on && 'bg-white/14 text-white hover:bg-white/14', className)}
    >
      <Icon name={icon} />
    </button>
  )
}

/* ---------- The Shelf ---------- */

export function ShelfView({
  items,
  open,
  onOpen,
  onEdit,
  onRestore,
}: {
  items: Item[]
  open: Item | null
  onOpen: (id: number) => void
  onEdit: (id: number, text: string) => void
  onRestore: () => void
}) {
  if (open) {
    if (open.kind === 'text') {
      return (
        <div className="flex h-full">
          <textarea
            value={open.text}
            maxLength={2000}
            spellCheck={false}
            aria-label="Note"
            autoFocus
            onChange={(event) => onEdit(open.id, event.target.value)}
            className="flex-1 resize-none overflow-auto rounded-xl bg-[#141414] px-3.5 py-3 text-[13px] leading-[1.45] [overflow-wrap:anywhere] whitespace-pre-wrap outline-none select-text focus-visible:outline-2 focus-visible:outline-white/40"
          />
        </div>
      )
    }
    return (
      <div className="flex h-full items-center gap-[18px]">
        <div className="grid h-28 w-[150px] flex-none place-items-center">
          <Thumb item={open} large />
        </div>
        <div className="min-w-0">
          <p className="truncate text-[15px] leading-[1.3] font-semibold">{nameOf(open)}</p>
          <p className="mt-1 text-xs leading-[1.4] [overflow-wrap:anywhere] text-white/55">{open.kind === 'link' ? open.url : open.meta}</p>
        </div>
      </div>
    )
  }

  if (!items.length) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-[3px] text-center">
        <Icon name="tray" className="mb-1.5 text-2xl text-white/40 [stroke-width:1.6]" />
        <p className="text-[13px] leading-[1.3] font-semibold text-white/85">Nothing on the Shelf</p>
        <p className="text-[11px] leading-[1.4] text-white/50">Files, text and links you drop on the notch wait here.</p>
        <button type="button" data-restore onClick={onRestore} className="mt-2.5 h-6 cursor-pointer rounded-xl bg-white/12 px-[11px] text-[11.5px] font-semibold transition-colors hover:bg-white/20">
          Put the examples back
        </button>
      </div>
    )
  }

  return (
    <ul aria-label="Shelf items" className="flex h-full items-center gap-1.5 overflow-x-auto [scrollbar-width:none]">
      {items.map((item) => (
        <li key={item.id} className="flex-none">
          <button
            type="button"
            data-item={item.id}
            aria-label={`${kindOf(item)}, ${nameOf(item)}`}
            onClick={() => onOpen(item.id)}
            className="flex h-[100px] w-[74px] cursor-pointer flex-col items-center gap-1.5 rounded-[10px] pt-1.5 transition-colors hover:bg-white/7 focus-visible:outline-offset-0"
          >
            <span className="grid size-14 flex-none place-items-center">
              <Thumb item={item} />
            </span>
            <span className="line-clamp-2 w-[68px] text-center text-[10.5px] leading-[1.25] font-medium [overflow-wrap:anywhere]">{nameOf(item)}</span>
          </button>
        </li>
      ))}
    </ul>
  )
}

/* ---------- Agents ---------- */

const OPEN_NOTE = 'In your notch, this opens the thread’s app'

const capsule = 'h-6 flex-none cursor-pointer rounded-full px-3 text-[11.5px] leading-none font-semibold transition-colors'
const outlined = 'ring-1 ring-white/30 ring-inset hover:bg-white/10'

export function AgentsView({ threads, narrow, onAllow, onDeny }: { threads: Thread[]; narrow: boolean; onAllow: (id: number) => void; onDeny: (id: number) => void }) {
  // Clicking a row would bring its app forward; here it says so for a moment.
  const [noted, setNoted] = useState<number | null>(null)
  useEffect(() => {
    if (noted === null) return
    const end = setTimeout(() => setNoted(null), 3000)
    return () => clearTimeout(end)
  }, [noted])

  return (
    <>
      <ul aria-label="Agent threads" className="flex h-full flex-col">
        {threads.map((thread) => {
          const asks = thread.state === 'needs'
          return (
            <li key={thread.id} className="flex h-10 flex-none items-center gap-1.5 rounded-[10px] transition-colors hover:bg-white/7">
              <button
                type="button"
                data-thread={thread.id}
                title="Open the thread’s app"
                onClick={() => setNoted(thread.id)}
                className="flex h-full min-w-0 flex-1 cursor-pointer items-center gap-2.5 rounded-[10px] px-1.5 text-left focus-visible:outline-offset-0"
              >
                <span className="grid size-6 flex-none place-items-center rounded-lg bg-white/10 text-[13px]">
                  <Icon name={TOOL_ICON[thread.tool]} />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[13px] leading-[1.25] font-semibold">
                    <span className="sr-only">{thread.tool}: </span>
                    {thread.name}
                  </span>
                  <span className="block truncate text-[11.5px] leading-[1.3] text-white/60">
                    {noted === thread.id ? OPEN_NOTE : `${thread.project} · ${thread.step}`}
                  </span>
                </span>
                <span className={cn('flex flex-none items-center gap-1.5 text-[11.5px] leading-none', asks ? 'font-semibold text-white' : 'text-white/60', asks && narrow && 'sr-only')}>
                  <StatusMark state={thread.state} className="text-[15px]" />
                  {thread.status}
                </span>
              </button>
              {asks && (
                <div className="flex flex-none items-center gap-1.5 pr-1.5">
                  <button type="button" aria-label={`Allow once: ${thread.name}`} onClick={() => onAllow(thread.id)} className={cn(capsule, 'bg-white text-black hover:bg-white/85')}>
                    Allow
                  </button>
                  <button type="button" aria-label={`Deny: ${thread.name}`} onClick={() => onDeny(thread.id)} className={cn(capsule, outlined)}>
                    Deny
                  </button>
                  {!narrow && (
                    <button type="button" aria-label={`Open the app: ${thread.name}`} onClick={() => setNoted(thread.id)} className={cn(capsule, outlined)}>
                      Open
                    </button>
                  )}
                </div>
              )}
            </li>
          )
        })}
      </ul>
      <span role="status" className="sr-only">
        {noted === null ? '' : OPEN_NOTE}
      </span>
    </>
  )
}

/* ---------- Home ---------- */

/** One widget card, as in the app: white 7%, 12 pt corners, a click opens its module. */
function Card({ className, onClick, label, children }: { className?: string; onClick?: () => void; label: string; children: ReactNode }) {
  const look = cn('flex min-w-0 flex-col rounded-xl bg-white/6 p-2.5 text-left shadow-[inset_0_0_0_1px_rgba(255,255,255,.06)]', className) // taste-skill-ignore: the app's own interface, drawn in the pretend screen
  if (!onClick) return <div className={look} aria-label={label}>{children}</div>
  return (
    <button type="button" onClick={onClick} aria-label={label} className={cn(look, 'cursor-pointer transition-colors hover:bg-white/10')}>
      {children}
    </button>
  )
}

/** Home: the modules as widgets on a 6 × 2 grid (4 columns on a phone), like the app's default page. */
export function HomeView({ song, songIndex, items, agents, usage, narrow, onGo }: { song: { title: string; artist: string }; songIndex: number; items: number; agents: string; usage: string; narrow: boolean; onGo: (module: Module) => void }) {
  const time = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
  const small = 'text-[10px] leading-[1.3] font-medium text-white/55'
  return (
    <div className={cn('grid h-full gap-2', narrow ? 'grid-cols-4' : 'grid-cols-6')} style={{ gridTemplateRows: 'repeat(2, minmax(0, 1fr))' }}>
      <Card className="col-span-2 row-span-2 justify-between" label={`Now Playing: ${song.title}`} onClick={() => onGo('np')}>
        <span className="flex items-center gap-2.5">
          <span className="size-[46px] flex-none overflow-hidden rounded-[9px]">
            <Cover song={songIndex} />
          </span>
          <span className="min-w-0">
            <span className="block truncate text-[12.5px] leading-[1.25] font-semibold">{song.title}</span>
            <span className="block truncate text-[11px] leading-[1.3] text-white/60">{song.artist}</span>
          </span>
        </span>
        <span className="h-[3px] w-full rounded-full bg-white/15">
          <span className="block h-full w-2/5 rounded-full bg-white/90" />
        </span>
      </Card>
      <Card className="col-span-2 justify-center gap-1" label={`Agents: ${agents}`} onClick={() => onGo('agents')}>
        <span className="flex items-center gap-1.5 text-[11px] leading-none font-semibold text-white/85">
          <Icon name="agents" className="text-[13px]" />
          Agents
        </span>
        <span className={cn(small, 'truncate')}>{agents}</span>
      </Card>
      {!narrow && (
        <>
          <Card className="justify-between" label={`Shelf: ${items ? count(items) : 'Empty'}`} onClick={() => onGo('shelf')}>
            <Icon name="tray" className="text-[13px] text-white/85" />
            <span>
              <span className="block text-[11px] leading-[1.25] font-semibold">Shelf</span>
              <span className={cn(small, 'block truncate')}>{items ? count(items) : 'Drop files here'}</span>
            </span>
          </Card>
          <Card className="justify-between" label={`Clock: ${time}`}>
            <Icon name="clock" className="text-[13px] text-white/85" />
            <span className="truncate text-[16px] leading-none font-semibold tabular-nums">{time}</span>
          </Card>
        </>
      )}
      <Card className="col-span-2 justify-center gap-1" label={`AI Usage: ${usage}`} onClick={() => onGo('usage')}>
        <span className="flex items-center gap-1.5 text-[11px] leading-none font-semibold text-white/85">
          <Icon name="usage" className="text-[13px]" />
          AI Usage
        </span>
        <span className={cn(small, 'truncate')}>{usage}</span>
      </Card>
      {!narrow && (
        <>
          <Card className="justify-between" label="Battery: 76%, on battery">
            <span className="flex items-center gap-1.5">
              <Icon name="battery" className="text-[13px] text-white/85" />
              <span className={small}>On battery</span>
            </span>
            <span className="text-[16px] leading-none font-semibold tabular-nums">76%</span>
          </Card>
          <Card className="justify-between" label="Statistics: 23 notch opens today">
            <span className="flex items-center gap-1.5">
              <Icon name="grid" className="text-[12px] text-white/85" />
              <span className={small}>Opens</span>
            </span>
            <span className="text-[16px] leading-none font-semibold tabular-nums">23</span>
          </Card>
        </>
      )}
    </div>
  )
}
