import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore, type FocusEvent, type MouseEvent, type PointerEvent } from 'react'
import { AnimatePresence, m, useReducedMotion, type Transition } from 'motion/react'
import { ScrambleText } from '@/components/ScrambleText'
import { cn } from '@/lib/utils'
import { Cover, Icon, StatusMark, type IconName } from './art'
import { useAgents } from './agents'
import { EXAMPLES, SONGS, VIEWS, count, earOf, kindOf, nearLimit, spokenName, summary, usageStatus, type Item, type Module, type Selection } from './data'
import { usePlayer } from './player'
import { useUsage } from './usage'
import { AccountMenu, AccountPill, UsageEar, UsageView } from './usageViews'
import { AgentsView, MenuView, NowPlayingView, ShelfView } from './views'

/* A working copy of the notch, hanging from the top edge of the box it's in (a pretend screen).
   Hover it to open it (tap on touch screens): a pretend, silent song plays, the Shelf holds a few
   examples, three pretend AI agents wait in Agents (one asks to be allowed), three pretend AI accounts
   show their limits in AI Usage, and the Module Menu switches between them. Sizes are the app's own,
   in points. It tells its owner what's showing
   (`onStatus`), so the words beside it can follow along. */

const NW = 185 // the hardware cutout
const NH = 32
const EAR = NH + 6 // the spots beside it
const EH = 180 // open height
// Open, a thin edge and a shadow lift the panel off the screen, as in the app. // taste-skill-ignore: the app's own interface, drawn in the pretend screen
const RING = '0 0 0 1px rgba(255,255,255,0), 0 24px 60px rgba(0,0,0,0)'
const OPEN_RING = '0 0 0 1px rgba(255,255,255,.16), 0 24px 60px rgba(0,0,0,.9)'

// The app's springs: opening overshoots a little, closing and small changes settle softly.
const OPEN: Transition = { type: 'spring', visualDuration: 0.5, bounce: 0.24 }
const CLOSE: Transition = { type: 'spring', visualDuration: 0.42, bounce: 0 }
const SWITCH: Transition = { type: 'spring', visualDuration: 0.42, bounce: 0.12 }
const INSTANT: Transition = { duration: 0 }

type How = 'hover' | 'click' | 'keyboard' | 'touch' // how it was opened, for the hint

export type NotchStatus = { open: boolean; module: Module; item: Item['kind'] | null; touch: boolean }

type Props = {
  /** On screen and reachable: the song starts, the bars move, the agents' answers play out, the hint shows. */
  active: boolean
  onStatus?: (status: NotchStatus) => void
}

export function LiveNotch({ active, onStatus }: Props) {
  const reduce = useReducedMotion() ?? false
  const [player, actions] = usePlayer()
  const [agents, agentActions] = useAgents(active)
  const [usage, usageActions] = useUsage()
  const [open, setOpen] = useState(false)
  const [how, setHow] = useState<How>('hover')
  const [module, setModule] = useState<Module>('np')
  const [lastModule, setLastModule] = useState<Exclude<Module, 'menu'>>('np')
  const [direction, setDirection] = useState(1)
  const [items, setItems] = useState<Item[]>(EXAMPLES)
  const [openId, setOpenId] = useState<number | null>(null)
  const [confirming, setConfirming] = useState(false)
  const [copied, setCopied] = useState('')
  const [peeking, setPeeking] = useState(false)
  const [peekOf, setPeekOf] = useState<'song' | 'agent'>('song')
  const [width, setWidth] = useState(640) // of the pretend screen
  const touch = useSyncExternalStore(onPointerKind, () => TOUCH.matches, () => false)

  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const timer = useRef(0)
  const hovering = useRef(false)
  const hoverLocked = useRef(false) // closed with a click: hovering opens it again only after leaving
  const nextId = useRef(EXAMPLES.length)

  const EW = Math.min(600, width - 24)

  useLayoutEffect(() => {
    const root = rootRef.current
    if (!root) return
    const sizes = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width))
    sizes.observe(root)
    return () => sizes.disconnect()
  }, [])
  const agentEar = active ? earOf(agents.threads) : null
  const usageEar = active ? nearLimit() : null // an account nearly out of a limit
  const compact = player.started || agentEar !== null || usageEar !== null // a song that has played (even paused), an agent or a limit to show keeps spots beside the notch
  // Wider spots when the agents' mark and the usage ring join the song's bars (less on a very narrow screen).
  const earWidth = Math.min(EAR + (agentEar ? 18 : 0) + (usageEar ? 34 : 0), Math.max(EAR, (width - NW) / 2))
  const openItem = items.find((item) => item.id === openId) ?? null

  /* ---------- Opening and closing ---------- */

  const show = (by: How) => {
    setHow(by)
    setOpen(true)
    setPeeking(false)
  }
  const close = () => {
    setOpen(false)
    closeItem()
    setConfirming(false)
    usageActions.close()
  }

  // Hover (mouse only), with the app's delays.
  const enter = (event: PointerEvent) => {
    if (event.pointerType !== 'mouse') return
    hovering.current = true
    clearTimeout(timer.current)
    if (!hoverLocked.current && !open) timer.current = window.setTimeout(() => show('hover'), 150)
  }
  const leave = (event: PointerEvent) => {
    if (event.pointerType !== 'mouse') return
    hovering.current = false
    hoverLocked.current = false
    clearTimeout(timer.current)
    // An open item or account menu holds it open, so a note can be read without keeping the pointer on
    // it. Opened with the keyboard, it waits for Escape.
    if (open && openId === null && !usage.menu && how !== 'keyboard') timer.current = window.setTimeout(close, 300)
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

  // Tabbing out closes it; a view swap that drops the focus doesn't.
  const blur = (event: FocusEvent) => {
    if (rootRef.current?.contains(event.relatedTarget as Node | null)) return
    setTimeout(() => {
      const now = document.activeElement
      if (now && now !== document.body && !rootRef.current?.contains(now) && !hovering.current) close()
    }, 0)
  }

  useEffect(() => {
    if (!open) return
    // Clicking or tapping anywhere else closes it; a swipe that scrolls the page doesn't (the browser
    // cancels the pointer when it starts scrolling).
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
    // Escape steps back once: out of the account menu or an open item, then closes the notch.
    const escape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.preventDefault()
      if (usage.menu) {
        closeMenu()
      } else if (openId !== null) {
        refocus.current = `[data-item="${openId}"]`
        closeItem()
      } else {
        close()
        if (rootRef.current?.contains(document.activeElement)) triggerRef.current?.focus()
      }
    }
    document.addEventListener('pointerdown', down)
    document.addEventListener('pointerup', up)
    document.addEventListener('pointercancel', cancel)
    document.addEventListener('keydown', escape)
    return () => {
      document.removeEventListener('pointerdown', down)
      document.removeEventListener('pointerup', up)
      document.removeEventListener('pointercancel', cancel)
      document.removeEventListener('keydown', escape)
    }
  })

  // Scrolled away: it closes, as the app's does when you leave it.
  if (!active && open) close()

  // The song starts by itself shortly after you arrive.
  useEffect(() => {
    if (!active || player.started) return
    const start = setTimeout(() => actions.play(true), 700)
    return () => clearTimeout(start)
  }, [active, player.started]) // eslint-disable-line react-hooks/exhaustive-deps -- `actions` is new each time, `play` isn't

  // A new song shows its name under the small notch for 3 seconds.
  const [seenChanges, setSeenChanges] = useState(player.changes)
  if (seenChanges !== player.changes) {
    setSeenChanges(player.changes)
    if (!open && compact && active) {
      setPeekOf('song')
      setPeeking(true)
    }
  }
  // So does a thread that needs you, once the notch is in view.
  const asking = agents.threads.find((thread) => thread.state === 'needs')
  const [seenAsking, setSeenAsking] = useState<number | null>(null)
  if (active && seenAsking !== (asking?.id ?? null)) {
    setSeenAsking(asking?.id ?? null)
    if (asking && !open) {
      setPeekOf('agent')
      setPeeking(true)
    }
  }
  useEffect(() => {
    if (!peeking) return
    const end = setTimeout(() => setPeeking(false), 3000)
    return () => clearTimeout(end)
  }, [peeking, player.changes, asking?.id])

  // Looking at the agents counts as seeing what finished.
  useEffect(() => {
    if (open && module === 'agents' && agents.threads.some((thread) => thread.fresh)) agentActions.seen()
  }, [open, module, agents.threads]) // eslint-disable-line react-hooks/exhaustive-deps -- `agentActions` is new each time, `seen` isn't

  // Where the keyboard goes once the Shelf has changed, so it isn't dropped when a button disappears:
  // back to an item's tile, the next tile, "Put the examples back", or an open item's Back button.
  const refocus = useRef<string | null>(null)
  useEffect(() => {
    if (refocus.current === null) return
    const target = rootRef.current?.querySelector<HTMLElement>(refocus.current)
    refocus.current = null
    target?.focus()
  })

  useEffect(() => () => clearTimeout(timer.current), [])

  const kind = items.find((item) => item.id === openId)?.kind ?? null
  useEffect(() => {
    onStatus?.({ open, module, item: kind, touch })
  }, [open, module, kind, touch, onStatus])

  /* ---------- Modules ---------- */

  const go = (next: Module) => {
    if (next === module) {
      if (next === 'menu') go(lastModule) // the Menu button toggles the Menu
      return
    }
    setDirection(VIEWS.indexOf(next) > VIEWS.indexOf(module) ? 1 : -1)
    setModule(next)
    if (next !== 'menu') setLastModule(next)
    closeItem()
    setConfirming(false)
    usageActions.close()
  }

  /* ---------- Agents ---------- */

  const answer = (kind: 'allow' | 'deny', id: number) => {
    refocus.current = `[data-thread="${id}"]` // the buttons go away, so the keyboard moves to the row
    agentActions[kind](id)
  }

  /* ---------- AI Usage ---------- */

  // The menu's buttons go away, so the keyboard moves to where it began: the pill, or the open menu's current choice.
  const closeMenu = () => {
    refocus.current = '[data-pill]'
    usageActions.close()
  }
  const toggleMenu = () => {
    refocus.current = usage.menu ? '[data-pill]' : `[data-pick="${usage.account}"]`
    usageActions.toggleMenu()
  }
  const choose = (selection: Selection) => {
    refocus.current = '[data-pill]'
    usageActions.choose(selection)
  }

  /* ---------- The Shelf ---------- */

  function closeItem() {
    // A note emptied while editing goes away, as in the app.
    setItems((list) => list.filter((item) => !(item.id === openId && item.kind === 'text' && !item.text.trim())))
    setOpenId(null)
    setCopied('')
  }
  const remove = (id: number) => {
    const rest = items.filter((item) => item.id !== id)
    const next = rest[Math.min(items.findIndex((item) => item.id === id), rest.length - 1)]
    refocus.current = next ? `[data-item="${next.id}"]` : '[data-restore]'
    setItems(rest)
    setOpenId(null)
  }
  const openTile = (id: number) => {
    // A note opens straight into its text; anything else puts the keyboard on Back.
    if (items.find((item) => item.id === id)?.kind !== 'text') refocus.current = '[data-back]'
    setOpenId(id)
  }
  const edit = (id: number, text: string) => {
    setItems((list) => list.map((item) => (item.id === id && item.kind === 'text' ? { ...item, text } : item)))
    setCopied('')
  }
  const restore = () => setItems(EXAMPLES.map((item) => ({ ...item, id: nextId.current++ })))
  const copy = async (item: Item) => {
    try {
      await navigator.clipboard.writeText(item.kind === 'link' ? item.url : item.kind === 'text' ? item.text : '')
      setCopied('Copied')
    } catch {
      setCopied('Couldn’t copy')
    }
  }

  // "Clear all" asks once more, then gives up asking after 4 seconds.
  useEffect(() => {
    if (!confirming) return
    const stop = setTimeout(() => setConfirming(false), 4000)
    return () => clearTimeout(stop)
  }, [confirming])

  /* ---------- Shape ---------- */

  const size = open
    ? { width: EW, height: EH, radius: 26, ears: 1 }
    : compact
      ? { width: NW + 2 * earWidth + (peeking ? 28 : 0), height: NH + (peeking ? 24 : 0), radius: 14, ears: 1 / 3 }
      : { width: NW, height: NH, radius: 14, ears: 0 }
  const spring = reduce ? INSTANT : open ? OPEN : peeking ? SWITCH : CLOSE

  const hint = open
    ? how === 'keyboard'
      ? 'Press Esc to close it'
      : touch
        ? 'Tap outside the notch to close it'
        : openId !== null || usage.menu
          ? 'Click outside the notch to close it'
          : 'Move the pointer away to close it'
    : touch
      ? 'Tap the notch'
      : 'Hover the notch'
  const hintIcon: IconName = open && how === 'keyboard' ? 'key' : touch ? 'tap' : 'cursor'
  const song = SONGS[player.song]
  const label = `${player.started ? `Notch: ${song.title} by ${song.artist}, ${player.playing ? 'playing' : 'paused'}` : 'Notch'}${asking ? `. ${asking.name} needs you` : ''}${usageEar ? `. ${spokenName(usageEar.account)} is nearly out of ${usageEar.account.tool}: ${usageEar.limit.left}% left` : ''}`

  return (
    <div ref={rootRef} className="pointer-events-none absolute inset-0 flex flex-col items-center text-white select-none">
      <m.div
        className={cn('relative', active && 'pointer-events-auto')}
        initial={false}
        animate={{ width: size.width, height: size.height }}
        transition={spring}
        onPointerEnter={enter}
        onPointerLeave={leave}
        onBlur={blur}
      >
        {/* Over the hardware cutout: click, tap or Enter to open and close. First, so Tab
            goes on into the open panel. */}
        <button
          ref={triggerRef}
          type="button"
          aria-expanded={open}
          aria-label={label}
          onClick={toggle}
          className="absolute top-0 left-1/2 z-3 -translate-x-1/2 cursor-pointer rounded-b-[14px] focus-visible:outline-offset-2"
          style={{ width: open ? NW : '100%', height: NH }}
        />
        {/* Concave corners where the notch meets the top of the screen. */}
        <m.span
          aria-hidden="true"
          className="absolute top-0 right-full size-[18px] origin-top-right bg-[radial-gradient(circle_at_0_100%,transparent_17.4px,#000_18px)]" // taste-skill-ignore: the app's own interface, drawn in the pretend screen
          initial={false}
          animate={{ scale: size.ears }}
          transition={spring}
        />
        <m.span
          aria-hidden="true"
          className="absolute top-0 left-full size-[18px] origin-top-left bg-[radial-gradient(circle_at_100%_100%,transparent_17.4px,#000_18px)]" // taste-skill-ignore: the app's own interface, drawn in the pretend screen
          initial={false}
          animate={{ scale: size.ears }}
          transition={spring}
        />

        <m.div
          className="absolute inset-0 overflow-hidden bg-black"
          initial={false}
          animate={{ borderBottomLeftRadius: size.radius, borderBottomRightRadius: size.radius, boxShadow: open ? OPEN_RING : RING }}
          transition={spring}
        >
          <Ears
            shown={compact && !open}
            ear={earWidth}
            started={player.started}
            playing={player.playing}
            song={player.song}
            agent={agentEar}
            usage={usageEar?.limit.left ?? null}
            moving={active && !reduce}
            spring={reduce ? INSTANT : SWITCH}
          />

          <div
            aria-hidden="true"
            className={cn(
              'absolute inset-x-0 flex h-[22px] items-center justify-center gap-1.5 px-3.5 text-[11px] leading-[1.35] font-semibold whitespace-nowrap transition-opacity',
              peeking && !open ? 'opacity-100 delay-150 duration-300' : 'opacity-0 duration-100',
            )}
            style={{ top: NH }}
          >
            {peekOf === 'agent' && asking ? (
              <>
                <StatusMark state="needs" className="size-3.5 flex-none" />
                <span className="min-w-0 truncate">{asking.name}</span>
                <span className="min-w-0 shrink-[2] truncate font-normal text-white/55">Needs you</span>
              </>
            ) : (
              <>
                <Cover song={player.song} className="size-3.5 flex-none rounded-[3.5px]" />
                <span className="min-w-0 truncate">{song.title}</span>
                <span className="min-w-0 shrink-[2] truncate font-normal text-white/55">{song.artist}</span>
              </>
            )}
          </div>

          <AnimatePresence>
            {open && (
              <m.div
                key="panel"
                role="group"
                aria-label="Open notch"
                className="pointer-events-none absolute top-0 left-1/2 z-4 origin-top"
                style={{ width: EW, height: EH, x: '-50%' }}
                initial={reduce ? { opacity: 0 } : { opacity: 0, filter: 'blur(10px)', scaleY: 0.6 }}
                animate={{ opacity: 1, filter: 'blur(0px)', scaleY: 1 }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, filter: 'blur(10px)', scaleY: 0.6, transition: { duration: 0.15 } }}
                transition={reduce ? { duration: 0.2 } : { opacity: { duration: 0.3, delay: 0.04 }, filter: { duration: 0.35 }, scaleY: OPEN }}
              >
                {/* The panel sits above the notch's own button and lets taps through only in the middle of
                    the top row, so on a narrow phone, where the sides reach in under the cutout, their
                    controls still get the taps. */}
                <div className="absolute inset-x-0 top-0 grid items-center px-4" style={{ height: NH, gridTemplateColumns: `1fr ${NW}px 1fr` }}>
                  <div className={cn('pointer-events-auto flex min-w-0 items-center', EW < 420 ? 'gap-0.5' : 'gap-1.5')}>
                    {openItem ? (
                      <>
                        <Round
                          label="Back to the Shelf"
                          icon="chevronLeft"
                          onClick={() => {
                            refocus.current = `[data-item="${openItem.id}"]`
                            closeItem()
                          }}
                        />
                        <span className="text-xs leading-none font-semibold">{kindOf(openItem)}</span>
                      </>
                    ) : (
                      <>
                        <Tab label="All modules" icon="grid" on={module === 'menu'} onClick={() => go('menu')} />
                        <span aria-hidden="true" className="mx-1 h-3.5 w-px flex-none bg-white/20" /* taste-skill-ignore: the app's own interface, drawn in the pretend screen */ />
                        <Tab label="Now Playing" icon="note" on={module === 'np'} onClick={() => go('np')} />
                        <Tab label="Shelf" icon="tray" on={module === 'shelf'} onClick={() => go('shelf')} />
                        <Tab label="Agents" icon="agents" on={module === 'agents'} onClick={() => go('agents')} />
                        <Tab label="AI Usage" icon="usage" on={module === 'usage'} onClick={() => go('usage')} />
                        {module === 'shelf' && items.length > 0 && (
                          <span className="ml-1.5 text-[11.5px] whitespace-nowrap text-white/50 tabular-nums">{count(items.length)}</span>
                        )}
                      </>
                    )}
                  </div>
                  <div />
                  <div className="pointer-events-auto flex min-w-0 items-center justify-end gap-1.5">
                    {module === 'np' && <span className={cn(pill, 'bg-white/8 text-white/70')}>Demo player</span>}
                    {module === 'usage' && <AccountPill usage={usage} onMenu={toggleMenu} onEmail={usageActions.toggleEmail} narrow={EW < 420} />}
                    {module === 'agents' &&
                      (asking ? (
                        <span className={cn(pill, 'bg-white/8 text-white/70')}>Demo agents</span>
                      ) : (
                        <button
                          type="button"
                          aria-label="Replay the demo"
                          onClick={() => {
                            refocus.current = '[data-thread]'
                            agentActions.reset()
                          }}
                          className={cn(pill, 'cursor-pointer bg-white/12 hover:bg-white/20')}
                        >
                          Replay
                        </button>
                      ))}
                    {module === 'shelf' && !openItem && items.length > 0 && (
                      <button
                        type="button"
                        onClick={() => {
                          if (!confirming) return setConfirming(true)
                          refocus.current = '[data-restore]'
                          setItems([])
                          setConfirming(false)
                        }}
                        className={cn(pill, 'cursor-pointer', confirming ? 'bg-white text-black' : 'bg-white/12 hover:bg-white/20')}
                      >
                        {confirming ? `Clear ${count(items.length)}?` : 'Clear all'}
                      </button>
                    )}
                    {openItem && openItem.kind !== 'file' && (
                      <button type="button" onClick={() => copy(openItem)} className={cn(pill, 'cursor-pointer bg-white/12 hover:bg-white/20')}>
                        {copied || 'Copy'}
                      </button>
                    )}
                    {openItem && <Round label="Remove from the Shelf" icon="trash" onClick={() => remove(openItem.id)} />}
                  </div>
                </div>

                <div className="pointer-events-auto absolute inset-x-0 bottom-0 px-5 pt-2 pb-4" style={{ top: NH }}>
                  <m.div
                    key={openItem ? `item-${openItem.id}` : module}
                    className="h-full"
                    initial={
                      reduce
                        ? { opacity: 0 }
                        : module === 'menu'
                          ? { opacity: 0, scale: 0.96, filter: 'blur(5px)' }
                          : { opacity: 0, x: 34 * direction, filter: 'blur(6px)' }
                    }
                    animate={{ opacity: 1, x: 0, scale: 1, filter: 'blur(0px)' }}
                    transition={reduce ? { duration: 0.2 } : { type: 'spring', visualDuration: 0.42, bounce: 0.1 }}
                    style={{ originX: 0, originY: 0 }}
                  >
                    {module === 'np' && <NowPlayingView player={player} actions={actions} visible={active} narrow={EW < 420} />}
                    {module === 'shelf' && <ShelfView items={items} open={openItem} onOpen={openTile} onEdit={edit} onRestore={restore} />}
                    {module === 'agents' && (
                      <AgentsView threads={agents.threads} narrow={EW < 420} onAllow={(id) => answer('allow', id)} onDeny={(id) => answer('deny', id)} />
                    )}
                    {module === 'usage' && <UsageView usage={usage} onRange={usageActions.setRange} onEmail={usageActions.toggleEmail} narrow={EW < 420} />}
                    {module === 'menu' && (
                      <MenuView current={lastModule} song={song.title} items={items.length} agents={summary(agents.threads)} usage={usageStatus(usage.account)} narrow={EW < 420} onGo={go} />
                    )}
                  </m.div>
                </div>
                {module === 'usage' && <AccountMenu usage={usage} top={NH} reduce={reduce} onChoose={choose} onClose={closeMenu} onEmail={usageActions.toggleEmail} />}
                <span role="status" className="sr-only">
                  {copied || (confirming ? `Press again to clear ${count(items.length)}` : '')}
                </span>
              </m.div>
            )}
          </AnimatePresence>
        </m.div>

      </m.div>

      {active && (
        <p className="absolute inset-x-0 bottom-3.5 flex items-center justify-center gap-1.5 text-[13px] font-medium text-soft">
          <Icon name={hintIcon} className="text-sm" />
          <ScrambleText key={hint} text={hint} pace={24} scrambledClassName="text-white/35" />
        </p>
      )}
    </div>
  )
}

const pill = 'inline-flex h-6 items-center rounded-xl px-[11px] text-[11.5px] leading-none font-semibold whitespace-nowrap transition-colors'

function Tab({ label, icon, on, onClick }: { label: string; icon: IconName; on: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      aria-pressed={on}
      onClick={onClick}
      className={cn(
        'grid h-6 w-[30px] flex-none cursor-pointer place-items-center rounded-xl text-[15px] transition-colors',
        on ? 'bg-white/16 text-white' : 'text-white/60 hover:bg-white/8 hover:text-white',
      )}
    >
      <Icon name={icon} />
    </button>
  )
}

function Round({ label, icon, onClick }: { label: string; icon: IconName; onClick: () => void }) {
  return (
    <button
      type="button"
      data-back={icon === 'chevronLeft' ? '' : undefined}
      aria-label={label}
      title={label}
      onClick={onClick}
      className="grid size-[26px] cursor-pointer place-items-center rounded-full bg-white/12 text-sm transition-colors hover:bg-white/20"
    >
      <Icon name={icon} />
    </button>
  )
}

/** The small spots beside the closed notch: the album art on the left; on the right, the sound bars, the agents' mark and the ring of an account that's nearly out. */
function Ears({
  shown,
  ear,
  started,
  playing,
  song,
  agent,
  usage,
  moving,
  spring,
}: {
  shown: boolean
  ear: number // each spot's width
  started: boolean // a song has played
  playing: boolean
  song: number
  agent: ReturnType<typeof earOf>
  usage: number | null // the share left of the limit that's nearly out
  moving: boolean
  spring: Transition
}) {
  const tuck = ear + 8 // closed, they slide in under the notch
  return (
    <div aria-hidden="true" className="absolute top-0 left-1/2 flex -translate-x-1/2 justify-between" style={{ width: NW + 2 * ear, height: NH }}>
      <m.span
        className="grid place-items-center"
        style={{ width: ear }}
        initial={false}
        animate={{ x: shown ? 0 : tuck, opacity: shown ? 1 : 0 }}
        transition={{ ...spring, opacity: { duration: shown ? 0.18 : 0.12, delay: shown ? 0 : 0.3 } }}
      >
        <span className={cn('relative overflow-hidden rounded-md transition-opacity duration-300', !started && 'opacity-0')} style={{ width: NH - 11, height: NH - 11 }}>
          <Cover song={song} className={cn('transition-opacity duration-300', !playing && 'opacity-45')} />
          <Icon
            name="pause"
            className={cn('absolute inset-0 m-auto size-[9px] transition-[opacity,transform] duration-300', playing ? 'scale-60 opacity-0' : 'opacity-100')}
          />
        </span>
      </m.span>
      <m.span
        className="flex items-center justify-center gap-1.5"
        style={{ width: ear }}
        initial={false}
        animate={{ x: shown ? 0 : -tuck, opacity: shown ? 1 : 0 }}
        transition={{ ...spring, opacity: { duration: shown ? 0.18 : 0.12, delay: shown ? 0 : 0.3 } }}
      >
        {started && (
          <span className="flex items-center gap-0.5" style={{ height: NH - 17 }}>
            {BARS.map((bar, i) => (
              <i
                key={i}
                className="block h-full w-[2.5px] rounded-sm bg-white/90 transition-transform duration-300"
                style={{
                  transform: `scaleY(${playing ? bar.still : bar.rest})`,
                  animation: playing && shown && moving ? `bar-dance ${bar.d}s ease-in-out ${bar.delay}s infinite alternate backwards` : undefined,
                  ['--from' as string]: bar.from,
                  ['--to' as string]: bar.to,
                }}
              />
            ))}
          </span>
        )}
        {agent && (
          <span className="flex items-center gap-[3px]">
            <StatusMark state={agent.mark} className="text-[13px]" />
            {agent.count > 0 && <span className="text-[11px] leading-none font-semibold tabular-nums">{agent.count}</span>}
          </span>
        )}
        {usage !== null && <UsageEar left={usage} />}
      </m.span>
    </div>
  )
}

const BARS = [
  { rest: 0.22, still: 0.5, from: 0.25, to: 0.9, d: 0.42, delay: 0 },
  { rest: 0.3, still: 0.85, from: 0.35, to: 1, d: 0.55, delay: 0.12 },
  { rest: 0.26, still: 0.65, from: 0.3, to: 0.8, d: 0.36, delay: 0.05 },
  { rest: 0.2, still: 0.4, from: 0.2, to: 0.95, d: 0.48, delay: 0.2 },
]

/* Whether it's a touch screen, kept up to date. */
const TOUCH = matchMedia('(hover: none)')
function onPointerKind(onChange: () => void) {
  TOUCH.addEventListener('change', onChange)
  return () => TOUCH.removeEventListener('change', onChange)
}
