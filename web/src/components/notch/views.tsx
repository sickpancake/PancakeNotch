import { useEffect, useReducer, useState } from 'react'
import { TileSwap } from '@/components/TileSwap'
import { cn } from '@/lib/utils'
import { Cover, Icon, Thumb, type IconName } from './art'
import { SONGS, clock, count, kindOf, nameOf, type Item, type Module } from './data'
import { positionAt, type Player, type PlayerActions } from './player'

/* What the open notch shows: the player, the Shelf and the Module Menu, at the app's sizes. */

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

/* ---------- The Module Menu ---------- */

const MODULES: { id: Exclude<Module, 'menu'>; name: string; icon: IconName }[] = [
  { id: 'np', name: 'Now Playing', icon: 'note' },
  { id: 'shelf', name: 'Shelf', icon: 'tray' },
]

export function MenuView({ current, song, items, onGo }: { current: Module; song: string; items: number; onGo: (module: Module) => void }) {
  return (
    <div className="flex h-full gap-[18px]">
      <div>
        <p className="mt-1 mb-2.5 text-[10px] leading-none font-semibold tracking-[.08em] text-white/50 uppercase">Favorites</p>
        <div className="flex gap-2">
          {MODULES.map((module) => (
            <button
              key={module.id}
              type="button"
              onClick={() => onGo(module.id)}
              className={cn(
                'flex h-[62px] w-[78px] cursor-pointer flex-col items-center justify-center gap-1.5 rounded-xl bg-white/7 text-[10.5px] leading-none font-semibold shadow-[inset_0_0_0_1px_rgba(255,255,255,.08)] transition-colors hover:bg-white/12', // taste-skill-ignore: the app's own interface, drawn in the pretend screen
                current === module.id && 'bg-white/16 shadow-[inset_0_0_0_1px_rgba(255,255,255,.3)] hover:bg-white/16', // taste-skill-ignore: the app's own interface, drawn in the pretend screen
              )}
            >
              <Icon name={module.icon} className="text-[17px]" />
              {module.name}
            </button>
          ))}
        </div>
      </div>
      <div className="min-w-0 flex-1 border-l border-white/12 pl-[18px]" /* taste-skill-ignore: the app's own interface, drawn in the pretend screen */>
        <p className="mt-1 mb-2.5 text-[10px] leading-none font-semibold tracking-[.08em] text-white/50 uppercase">All modules</p>
        {MODULES.map((module) => (
          <button
            key={module.id}
            type="button"
            onClick={() => onGo(module.id)}
            className="flex w-full cursor-pointer items-center gap-2.5 rounded-[10px] px-1.5 py-[5px] text-left transition-colors hover:bg-white/7"
          >
            <span className="grid size-[26px] flex-none place-items-center rounded-lg bg-white/10 text-[13px]">
              <Icon name={module.icon} />
            </span>
            <span className="min-w-0">
              <span className="block text-[12.5px] leading-[1.25] font-semibold">{module.name}</span>
              <span className="block truncate text-[11px] leading-[1.3] text-white/50">
                {module.id === 'np' ? song : items ? count(items) : 'Empty'}
              </span>
            </span>
          </button>
        ))}
      </div>
    </div>
  )
}
