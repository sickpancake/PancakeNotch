/* What the live notch plays and keeps: the practice player's made-up songs and an example Shelf. */

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

export type Module = 'menu' | 'np' | 'shelf'
export const VIEWS: Module[] = ['menu', 'np', 'shelf'] // left to right, for the slide direction

export const nameOf = (item: Item) =>
  item.kind === 'file' ? item.name : item.kind === 'link' ? new URL(item.url).host : item.text.split('\n')[0]
export const kindOf = (item: Item) => ({ file: 'File', text: 'Text', link: 'Link' })[item.kind]
export const count = (n: number) => (n === 1 ? '1 item' : `${n} items`)

export const clock = (seconds: number) => {
  const whole = Math.max(0, Math.floor(seconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}
