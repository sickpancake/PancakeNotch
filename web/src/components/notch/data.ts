/* What the live notch plays and keeps: the practice player's made-up songs, an example Shelf and some
   made-up AI agent threads. */

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
export type ThreadState = 'working' | 'needs' | 'done' | 'error'

/** One agent thread. `status` is the words beside its mark ("Working · 4m"); `fresh` is a finish nobody has looked at yet. */
export type Thread = { id: number; name: string; tool: Tool; project: string; state: ThreadState; step: string; status: string; fresh?: boolean }

export const THREADS: Thread[] = [
  { id: 0, name: 'Fix login redirect', tool: 'Claude Code', project: 'web-app', state: 'working', step: 'Running tests', status: 'Working · 4m' },
  { id: 1, name: 'Refactor parser', tool: 'Codex', project: 'compiler', state: 'needs', step: 'Wants to run: rm -rf build', status: 'Needs you' },
  { id: 2, name: 'Update README', tool: 'Cursor', project: 'docs', state: 'done', step: 'Edited README.md', status: 'Done · 2m ago' },
]

export type Module = 'menu' | 'np' | 'shelf' | 'agents'
export const VIEWS: Module[] = ['menu', 'np', 'shelf', 'agents'] // left to right, for the slide direction

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

export const clock = (seconds: number) => {
  const whole = Math.max(0, Math.floor(seconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}
