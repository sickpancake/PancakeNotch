import type { FocusEvent, ReactNode } from 'react'
import { AnimatePresence, m } from 'motion/react'
import { cn } from '@/lib/utils'
import { Icon, TOOL_ICON, leftTone } from './art'
import { ACCOUNTS, RANGES, accountOf, isEmailName, money, paceOf, share, shortTool, spokenName, tokens, totalsOf, type Account, type AccountId, type Limit, type Selection } from './data'
import type { Usage } from './usage'

/* AI Usage's pieces, at the app's sizes: the account pill in the band, the account menu over the panel,
   the limits and the totals. Colors are for the gauges only: green, yellow, orange, red as a limit runs low. */

const TOOLS = [...new Set(ACCOUNTS.map((account) => account.tool))]
const header = 'px-2 pt-1 pb-px text-[10.5px] leading-[1.3] font-semibold text-white/45'

/* ---------- Gauges ---------- */

/** How much of a limit is left: a track, a fill and, when it's known, a thin tick where even use would be. */
function LeftBar({ left, pace, height, className }: { left: number; pace?: number; height: number; className?: string }) {
  return (
    <span aria-hidden="true" className={cn('relative block flex-none rounded-full bg-white/12', className)} style={{ height }}>
      <span
        className={cn('block h-full rounded-full bg-current transition-[width,color] duration-300 motion-reduce:transition-none', leftTone(left))}
        style={{ width: `${left}%` }}
      />
      {pace !== undefined && (
        <span
          className="absolute -inset-y-[2px] w-[1.5px] rounded-full bg-white/90 shadow-[0_0_0_.75px_#000]" // taste-skill-ignore: a black edge so the tick shows over the fill
          style={{ left: `clamp(0px, calc(${pace}% - .75px), calc(100% - 1.5px))` }}
        />
      )}
    </span>
  )
}

/** A still ring for the share of a limit that's left. */
export function LimitRing({ left, size }: { left: number; size: number }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={cn('flex-none -rotate-90 fill-none stroke-[4.4]', leftTone(left))} style={{ width: size, height: size }}>
      <circle cx="12" cy="12" r="9.8" className="stroke-white/12" />
      <circle cx="12" cy="12" r="9.8" pathLength="100" strokeDasharray={`${Math.max(left, 3)} 100`} strokeLinecap="round" stroke="currentColor" />
    </svg>
  )
}

/** The closed notch's ear when an account is nearly out: the ring and what's left. */
export function UsageEar({ left }: { left: number }) {
  return (
    <span className="flex items-center gap-[3px]">
      <LimitRing left={left} size={11} />
      <span className="text-[11px] leading-none font-semibold tabular-nums">{left}%</span>
    </span>
  )
}

/** Initials on a gray disc, the same gray for the same account. */
function Disc({ account, size }: { account: Account; size: number }) {
  return (
    <span
      aria-hidden="true"
      className="grid flex-none place-items-center rounded-full font-semibold"
      style={{ width: size, height: size, fontSize: size * 0.42, background: `rgb(255 255 255 / ${account.shade})` }}
    >
      {account.initials}
    </span>
  )
}

/* ---------- Emails ---------- */

const FILL = 'nostrilacdemu' // stands in for the hidden letters, so the real ones aren't on the page

/** An email with the part before the @ blurred but for its first letter. Click it to show, click again to hide. */
function Email({ account, shown, onToggle, className }: { account: Account; shown: boolean; onToggle: (id: AccountId) => void; className?: string }) {
  const [name, domain] = account.email.split('@')
  return (
    <button
      type="button"
      aria-label={shown ? `${account.email}, shown. Click to hide` : `${name[0]}… at ${domain}, hidden. Click to show`}
      title={shown ? 'Hide the email' : 'Show the email'}
      onClick={() => onToggle(account.id)}
      className={cn('relative z-1 max-w-full cursor-pointer rounded-sm text-left whitespace-nowrap hover:text-white', className)}
    >
      <span aria-hidden="true">
        {shown ? (
          account.email
        ) : (
          <>
            {name[0]}
            <span className="inline-block blur-[4px] select-none">{FILL.slice(0, Math.max(3, name.length - 1))}</span>@{domain}
          </>
        )}
      </span>
    </button>
  )
}

/* ---------- The account pill and menu ---------- */

/** Beside the notch: the tool, the account and a chevron. A click opens the account menu. */
export function AccountPill({ usage, onMenu, onEmail, narrow }: { usage: Usage; onMenu: () => void; onEmail: (id: AccountId) => void; narrow: boolean }) {
  const account = usage.account === 'all' ? null : accountOf(usage.account)
  return (
    <div className={cn('relative flex h-[22px] flex-none items-center rounded-full bg-white/8 text-[11.5px] leading-none font-semibold whitespace-nowrap transition-colors hover:bg-white/16', narrow ? 'gap-1 px-2' : 'gap-[5px] px-[9px]')}>
      <button
        type="button"
        data-pill
        aria-haspopup="true"
        aria-expanded={usage.menu}
        aria-label={`Account: ${account ? spokenName(account) : 'All accounts'}. Choose an account`}
        title="Choose an account"
        onClick={onMenu}
        className="absolute inset-0 cursor-pointer rounded-full"
      />
      {!narrow && <Icon name={account ? TOOL_ICON[account.tool] : 'people'} className="text-[11px] text-white/60" />}
      {account && isEmailName(account) ? (
        narrow ? (
          <span aria-hidden="true">{account.tool}</span>
        ) : (
          <Email account={account} shown={usage.shown.includes(account.id)} onToggle={onEmail} />
        )
      ) : (
        <span aria-hidden="true">{account?.name ?? (narrow ? 'All' : 'All accounts')}</span>
      )}
      <Icon name="chevronDown" className="text-[9px] text-white/60 [stroke-width:3.2]" />
    </div>
  )
}

/** Over the right side of the panel, with the rest of the panel dimmed. Esc, a click outside or a choice closes it. */
export function AccountMenu({
  usage,
  top,
  reduce,
  onChoose,
  onClose,
  onEmail,
}: {
  usage: Usage
  top: number // where the dimmed part starts: under the row of tabs
  reduce: boolean
  onChoose: (selection: Selection) => void
  onClose: () => void
  onEmail: (id: AccountId) => void
}) {
  // Tabbing on past the menu closes it.
  const blur = (event: FocusEvent<HTMLDivElement>) => {
    if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget as Node)) onClose()
  }

  return (
    <AnimatePresence>
      {usage.menu && (
        <m.div
          key="menu"
          className="pointer-events-none absolute inset-0"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, transition: { duration: 0.1 } }}
          transition={{ duration: reduce ? 0.1 : 0.15 }}
        >
          <div aria-hidden="true" className="pointer-events-auto absolute inset-x-0 bottom-0 bg-black/40" style={{ top }} onClick={onClose} />
          <m.div
            role="group"
            aria-label="Accounts"
            onBlur={blur}
            className="pointer-events-auto absolute top-1.5 right-2.5 w-[236px] max-w-[calc(100%-20px)] rounded-[11px] bg-black p-1 ring-1 ring-white/16 ring-inset"
            style={{ originX: 1, originY: 0 }}
            initial={{ scale: reduce ? 1 : 0.96 }}
            animate={{ scale: 1 }}
            transition={{ duration: 0.15, ease: 'easeOut' }}
          >
            <ul>
              <Choice id="all" current={usage.account === 'all'} label="All accounts" height={26} onChoose={onChoose}>
                <span className="grid size-5 flex-none place-items-center rounded-full bg-white/18 text-[10px]">
                  <Icon name="people" />
                </span>
                <span aria-hidden="true" className="text-[12.5px] leading-none font-semibold">
                  All accounts
                </span>
              </Choice>
            </ul>
            {TOOLS.map((tool) => (
              <section key={tool}>
                <h3 className={header}>{tool}</h3>
                <ul>
                  {ACCOUNTS.filter((account) => account.tool === tool).map((account) => (
                    <AccountChoice key={account.id} account={account} current={usage.account === account.id} shown={usage.shown.includes(account.id)} onChoose={onChoose} onEmail={onEmail} />
                  ))}
                </ul>
              </section>
            ))}
          </m.div>
        </m.div>
      )}
    </AnimatePresence>
  )
}

/** One choice: a button across the whole row, with a check when it's the current one. Anything clickable inside sits above it. */
function Choice({ id, current, label, height, onChoose, children }: { id: Selection; current: boolean; label: string; height: number; onChoose: (selection: Selection) => void; children: ReactNode }) {
  return (
    <li
      className="relative flex items-center gap-[5px] rounded-[7px] px-[5px] transition-colors hover:bg-white/14 has-[[data-pick]:focus-visible]:bg-white/14"
      style={{ height }}
    >
      <button type="button" data-pick={id} aria-current={current || undefined} aria-label={label} onClick={() => onChoose(id)} className="absolute inset-0 cursor-pointer rounded-[7px] focus-visible:outline-offset-0" />
      <Icon name="check" className={cn('text-[9px] [stroke-width:3.4]', !current && 'opacity-0')} />
      {children}
    </li>
  )
}

function AccountChoice({ account, current, shown, onChoose, onEmail }: { account: Account; current: boolean; shown: boolean; onChoose: (selection: Selection) => void; onEmail: (id: AccountId) => void }) {
  const named = !isEmailName(account)
  const email = <Email account={account} shown={shown} onToggle={onEmail} />
  const label = [spokenName(account), account.plan, ...account.limits.map((limit) => `${limit.name} ${limit.left}% left`)].join(', ')
  return (
    <Choice id={account.id} current={current} label={label} height={30} onChoose={onChoose}>
      <Disc account={account} size={20} />
      <span className="min-w-0 flex-1 leading-[1.25]">
        {named ? (
          <span aria-hidden="true" className="flex items-baseline gap-1">
            <span className="truncate text-[11.5px] font-semibold">{account.name}</span>
            <span className="flex-none text-[10.5px] text-white/60">{account.plan}</span>
          </span>
        ) : (
          <span className="block text-[11.5px] font-semibold">{email}</span>
        )}
        <span className="block text-[10px] text-white/60">{named ? email : <span aria-hidden="true">{account.plan}</span>}</span>
      </span>
      <span aria-hidden="true" className="flex flex-none flex-col gap-[3px]">
        {account.limits.map((limit) => (
          <LeftBar key={limit.name} left={limit.left} height={3} className="w-9" />
        ))}
      </span>
    </Choice>
  )
}

/* ---------- The panel ---------- */

export function UsageView({ usage, onRange, onEmail, narrow }: { usage: Usage; onRange: (range: Usage['range']) => void; onEmail: (id: AccountId) => void; narrow: boolean }) {
  const account = usage.account === 'all' ? null : accountOf(usage.account)
  const totals = totalsOf(usage.account, usage.range)

  return (
    <div role="group" aria-label="AI Usage" className={cn('flex h-full', narrow ? 'gap-3' : 'gap-6')}>
      <div className={cn('min-w-0', narrow ? 'flex-1' : 'flex-45')}>
        {account ? (
          <div className="flex flex-col gap-1.5">
            {account.limits.map((limit) => (
              <LimitRow key={limit.name} limit={limit} narrow={narrow} />
            ))}
          </div>
        ) : (
          <>
            <p className="mb-0.5 truncate text-[10.5px] leading-[1.3] text-white/45">{narrow ? '% left: session, weekly' : '% left: session above, weekly below'}</p>
            <ul aria-label="Accounts">
              {ACCOUNTS.map((each) => (
                <SummaryRow key={each.id} account={each} shown={usage.shown.includes(each.id)} onEmail={onEmail} narrow={narrow} />
              ))}
            </ul>
          </>
        )}
      </div>

      <div className={cn('flex min-w-0 flex-col items-start gap-0.5', narrow ? 'flex-none' : 'flex-55')}>
        <div role="group" aria-label="Range" className="mb-1 flex gap-0.5 rounded-full bg-white/8 p-0.5">
          {RANGES.map((range) => (
            <button
              key={range.id}
              type="button"
              aria-label={range.label}
              aria-pressed={usage.range === range.id}
              onClick={() => onRange(range.id)}
              className={cn(
                'h-5 cursor-pointer rounded-full text-[11px] leading-none font-semibold whitespace-nowrap transition-colors',
                narrow ? 'px-1.5' : 'px-2.5',
                usage.range === range.id ? 'bg-white/18 text-white' : 'text-white/60 hover:text-white/85',
              )}
            >
              {narrow ? range.short : range.label}
            </button>
          ))}
        </div>
        <div aria-live="polite" className="flex min-w-0 max-w-full flex-col gap-0.5">
          <p className={cn('truncate leading-[1.2] font-semibold', narrow ? 'text-lg' : 'text-[22px]')}>{tokens(totals.tokens)} tokens</p>
          <p className="truncate text-xs leading-[1.3] text-white/70">≈ {money(totals.cost)} API value</p>
        </div>
        <ul className="mt-0.5 max-w-full">
          {totals.models.slice(0, 3).map((model) => (
            <li key={model.name} className="truncate text-[11px] leading-[1.3] text-white/60">
              {share(model, totals.tokens)}
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}

/** "Session · On pace", a bar and "63% left · resets in 3h 5m". */
function LimitRow({ limit, narrow }: { limit: Limit; narrow: boolean }) {
  const { even, label } = paceOf(limit)
  const size = narrow ? 'text-[11px]' : 'text-[11.5px]'
  return (
    <div>
      <p className={cn('truncate leading-[1.3] font-semibold', size)}>
        {limit.name} · {label}
      </p>
      <LeftBar left={limit.left} pace={even} height={6} className="my-[3px]" />
      <p className={cn('truncate leading-[1.3] text-white/60', size)}>
        {limit.left}% left · {limit.reset}
      </p>
    </div>
  )
}

/** An account in the all-accounts list: its disc, name and plan, and two tiny bars for Session and Weekly. */
function SummaryRow({ account, shown, onEmail, narrow }: { account: Account; shown: boolean; onEmail: (id: AccountId) => void; narrow: boolean }) {
  return (
    <li className="flex h-[30px] items-center gap-2">
      {!narrow && <Disc account={account} size={20} />}
      <span className="min-w-0 flex-1 leading-[1.25]">
        {isEmailName(account) && !narrow ? (
          <Email account={account} shown={shown} onToggle={onEmail} className="block text-[12.5px] font-semibold" />
        ) : (
          <span className="block truncate text-[12.5px] font-semibold">{spokenName(account)}</span>
        )}
        <span className="block truncate text-[10.5px] text-white/60">{isEmailName(account) && narrow ? account.plan : `${shortTool(account)} · ${account.plan}`}</span>
      </span>
      <span aria-hidden="true" className="flex flex-none flex-col gap-[3px]">
        {account.limits.map((limit) => (
          <span key={limit.name} className="flex items-center gap-[5px]">
            <LeftBar left={limit.left} height={4} className={narrow ? 'w-8' : 'w-11'} />
            <span className="w-[26px] text-right text-[10.5px] leading-none text-white/60 tabular-nums">{limit.left}%</span>
          </span>
        ))}
      </span>
      <span className="sr-only">{account.limits.map((limit) => `${limit.name} ${limit.left}% left`).join(', ')}</span>
    </li>
  )
}
