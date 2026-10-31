/* What the live notch plays and keeps: the practice player's made-up songs, an example Shelf, some
   made-up AI agent threads and three made-up AI accounts with their limits and tokens. */

export type Song = { title: string; artist: string; album: string; duration: number }

export const SONGS: Song[] = [
  { title: 'Pancake Sunrise', artist: 'The Flipsides', album: 'Breakfast Club', duration: 192 },
  { title: 'Golden Edges', artist: 'Maple & Co.', album: 'Stack', duration: 168 },
  { title: 'Night Owl', artist: 'Syrup Static', album: 'After Hours', duration: 220 },
]

export type Item =
  | { id: number; kind: 'file'; name: string; meta: string; thumb: 'pdf' | 'photo' }
  | { id: number; kind: 'text'; text: string }
  | { id: number; kind: 'link'; url: string }

export const EXAMPLES: Item[] = [
  { id: 0, kind: 'file', name: 'Report.pdf', meta: 'PDF document · 84 KB', thumb: 'pdf' },
  { id: 1, kind: 'file', name: 'Holiday.jpg', meta: 'JPEG image · 11 KB', thumb: 'photo' },
  { id: 2, kind: 'text', text: 'Pick up the cake at 5' },
  { id: 3, kind: 'link', url: 'https://github.com' },
]

export type Tool = 'Claude Code' | 'Codex' | 'Cursor'
export type ThreadState = 'working' | 'needs' | 'done' | 'stopped' | 'error'

/** One agent thread. `status` is the words beside its mark ("Working · 4m"); `fresh` is a finish nobody has looked at yet. */
export type Thread = { id: number; name: string; tool: Tool; project: string; state: ThreadState; step: string; status: string; fresh?: boolean }

export const THREADS: Thread[] = [
  { id: 0, name: 'Fix login redirect', tool: 'Claude Code', project: 'web-app', state: 'working', step: 'Running tests', status: 'Working · 4m' },
  { id: 1, name: 'Refactor parser', tool: 'Codex', project: 'compiler', state: 'needs', step: 'Wants to run: rm -rf build', status: 'Needs you' },
  { id: 2, name: 'Update README', tool: 'Cursor', project: 'docs', state: 'done', step: 'Edited README.md', status: 'Done · 2m ago' },
]

export type Module = 'menu' | 'np' | 'shelf' | 'agents' | 'usage'
export const VIEWS: Module[] = ['menu', 'np', 'shelf', 'agents', 'usage'] // left to right, for the slide direction

export const nameOf = (item: Item) =>
  item.kind === 'file' ? item.name : item.kind === 'link' ? new URL(item.url).host : item.text.split('\n')[0]
export const kindOf = (item: Item) => ({ file: 'File', text: 'Text', link: 'Link' })[item.kind]
export const count = (n: number) => (n === 1 ? '1 item' : `${n} items`)

/** The agents' one-line summary, for the Module Menu. */
export function summary(threads: Thread[]) {
  const needs = threads.filter((thread) => thread.state === 'needs').length
  const working = threads.filter((thread) => thread.state === 'working').length
  return needs ? `${needs} needs you` : working ? `${working} working` : 'All done'
}

/** What the closed notch shows for the agents: a mark, and the number of threads at work. Nothing when it's quiet. */
export function earOf(threads: Thread[]): { mark: 'needs' | 'done' | 'working'; count: number } | null {
  if (threads.some((thread) => thread.state === 'needs')) return { mark: 'needs', count: 0 }
  if (threads.some((thread) => thread.fresh)) return { mark: 'done', count: 0 }
  const working = threads.filter((thread) => thread.state === 'working').length
  return working ? { mark: 'working', count: working } : null
}

/* ---------- AI Usage ---------- */

export type AccountId = 'personal' | 'work' | 'codex'
export type Selection = AccountId | 'all'
export type Range = 'today' | 'week' | 'month'

/** One plan limit. `resetsIn` and `window` are minutes; where an even pace would stand follows from them. */
export type Limit = { name: 'Session' | 'Weekly'; left: number; resetsIn: number; window: number; reset: string }
type Model = { name: string; tokens: number; cost: number } // one pretend day
export type Account = {
  id: AccountId
  tool: Exclude<Tool, 'Cursor'>
  name: string // an account nobody has named goes by its email, as in the app
  email: string
  plan: string
  initials: string
  shade: number // the gray of its circle, as a share of white
  limits: Limit[]
  models: Model[]
}

const SESSION = 300
const WEEK = 7 * 24 * 60

/** Two Claude accounts (Personal on Pro, Work on Max) and a Codex one, as in the app's practice notch. */
export const ACCOUNTS: Account[] = [
  {
    id: 'personal', tool: 'Claude Code', name: 'Personal', email: 'sam@example.com', plan: 'Pro', initials: 'P', shade: 0.26,
    limits: [
      { name: 'Session', left: 63, resetsIn: 185, window: SESSION, reset: 'resets in 3h 5m' },
      { name: 'Weekly', left: 77, resetsIn: 5940, window: WEEK, reset: 'resets Sun 11:00' },
    ],
    models: [
      { name: 'Sonnet 5.5', tokens: 3_400_000, cost: 2.1 },
      { name: 'Haiku 5.5', tokens: 900_000, cost: 0.08 },
    ],
  },
  {
    id: 'work', tool: 'Claude Code', name: 'Work', email: 'sam@example.org', plan: 'Max', initials: 'W', shade: 0.34,
    limits: [
      { name: 'Session', left: 8, resetsIn: 41, window: SESSION, reset: 'resets in 41m' },
      { name: 'Weekly', left: 42, resetsIn: 2880, window: WEEK, reset: 'resets Wed 09:00' },
    ],
    models: [
      { name: 'Opus 5.5', tokens: 9_800_000, cost: 11.4 },
      { name: 'Sonnet 5.5', tokens: 2_100_000, cost: 1.3 },
    ],
  },
  {
    id: 'codex', tool: 'Codex', name: 'sam@example.com', email: 'sam@example.com', plan: 'Plus', initials: 'SE', shade: 0.42,
    limits: [
      { name: 'Session', left: 88, resetsIn: 210, window: SESSION, reset: 'resets in 3h 30m' },
      { name: 'Weekly', left: 59, resetsIn: 7200, window: WEEK, reset: 'resets Mon 18:00' },
    ],
    models: [{ name: 'GPT-6.1 Sol', tokens: 4_200_000, cost: 1.85 }],
  },
]

export const accountOf = (id: AccountId) => ACCOUNTS.find((account) => account.id === id)!
export const shortTool = (account: Account) => (account.tool === 'Claude Code' ? 'Claude' : account.tool)
export const isEmailName = (account: Account) => account.name === account.email
/** What a screen reader hears for an account. Its email is only ever read through the Email button. */
export const spokenName = (account: Account) => (isEmailName(account) ? account.tool : account.name)

/** How the limit is being used compared with spreading it evenly over its window (the app's 5-point margin). */
export function paceOf(limit: Limit) {
  const even = (limit.resetsIn / limit.window) * 100 // what an even pace would have left
  const label = limit.left < even - 5 ? 'Ahead of pace' : limit.left > even + 5 ? 'Under pace' : 'On pace'
  return { even, label }
}

/** The account closest to running out, while one of its limits is under 10% left (the closed notch's ring). */
export function nearLimit() {
  const near = ACCOUNTS.map((account) => ({ account, limit: account.limits.reduce((a, b) => (b.left < a.left ? b : a)) }))
    .filter(({ limit }) => limit.left < 10)
    .sort((a, b) => a.limit.left - b.limit.left)
  return near[0] ?? null
}

const SCALE: Record<Range, number> = { today: 1, week: 5.6, month: 21 }
export const RANGES: { id: Range; label: string; short: string }[] = [
  { id: 'today', label: 'Today', short: 'Today' },
  { id: 'week', label: '7 days', short: '7d' },
  { id: 'month', label: '30 days', short: '30d' },
]

/** The tokens, what they'd cost at API prices and the models used most, for one account or all (the sums). */
export function totalsOf(selection: Selection, range: Range) {
  const merged = new Map<string, Model>()
  for (const account of selection === 'all' ? ACCOUNTS : [accountOf(selection)]) {
    for (const model of account.models) {
      const sum = merged.get(model.name) ?? { name: model.name, tokens: 0, cost: 0 }
      sum.tokens += Math.round(model.tokens * SCALE[range])
      sum.cost += Math.round(model.cost * SCALE[range] * 100) / 100
      merged.set(model.name, sum)
    }
  }
  const models = [...merged.values()].sort((a, b) => b.tokens - a.tokens)
  return { tokens: models.reduce((n, m) => n + m.tokens, 0), cost: models.reduce((n, m) => n + m.cost, 0), models }
}

const compact = new Intl.NumberFormat('en', { notation: 'compact', maximumSignificantDigits: 3 })
const dollars = new Intl.NumberFormat('en', { style: 'currency', currency: 'USD' })
export const tokens = (n: number) => compact.format(n) // "12.4M"
export const money = (n: number) => dollars.format(n) // "$41.20"
/** "Opus 5.5 · 62%": the model's share of the tokens. */
export const share = (model: Model, total: number) => {
  const percent = (model.tokens / total) * 100
  return `${model.name} · ${percent < 1 ? '<1' : Math.round(percent)}%`
}

/** The Module Menu's line: the chosen account's tightest limit, or "All accounts". */
export function usageStatus(selection: Selection) {
  if (selection === 'all') return 'All accounts'
  const limit = accountOf(selection).limits.reduce((a, b) => (b.left < a.left ? b : a))
  return `${limit.name} ${limit.left}% left`
}

export const clock = (seconds: number) => {
  const whole = Math.max(0, Math.floor(seconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}
