import { useEffect, useReducer } from 'react'
import { SONGS } from './data'

/* The practice player: silent, made-up songs that play along in time. Nothing ticks while a song
   plays; its position is worked out from when it started, and its end is a single timer. */

export type Player = {
  song: number
  playing: boolean
  started: boolean // played at least once: from then on Now Playing keeps its spots beside the notch
  shuffle: boolean
  repeat: boolean
  pos: number // seconds into the song at `since`
  since: number // performance.now() when `pos` was taken
  changes: number // counts song changes, so the notch can show the new name
}

type Action =
  | { type: 'play'; on: boolean; now: number }
  | { type: 'seek'; to: number; now: number }
  | { type: 'skip'; step: 1 | -1; now: number; random: number }
  | { type: 'ended'; now: number; random: number }
  | { type: 'toggle'; key: 'shuffle' | 'repeat' }

/** Seconds into the song at `now`. */
export const positionAt = (s: Player, now: number) =>
  Math.min(SONGS[s.song].duration, s.playing ? s.pos + (now - s.since) / 1000 : s.pos)

function reduce(s: Player, a: Action): Player {
  switch (a.type) {
    case 'play':
      return { ...s, pos: positionAt(s, a.now), since: a.now, playing: a.on, started: s.started || a.on }
    case 'seek':
      return { ...s, pos: Math.min(Math.max(a.to, 0), SONGS[s.song].duration), since: a.now }
    case 'skip': {
      // Back goes to the start of the song first, then to the one before (like the app).
      if (a.step < 0 && positionAt(s, a.now) > 3) return { ...s, pos: 0, since: a.now }
      let next = (s.song + a.step + SONGS.length) % SONGS.length
      if (s.shuffle && a.step > 0) {
        const others = SONGS.map((_, i) => i).filter((i) => i !== s.song)
        next = others[Math.floor(a.random * others.length)]
      }
      return { ...s, song: next, pos: 0, since: a.now, changes: s.changes + 1 }
    }
    case 'ended':
      return s.repeat ? { ...s, pos: 0, since: a.now } : reduce(s, { type: 'skip', step: 1, now: a.now, random: a.random })
    case 'toggle':
      return { ...s, [a.key]: !s[a.key] }
  }
}

const START: Player = { song: 0, playing: false, started: false, shuffle: false, repeat: false, pos: 74, since: 0, changes: 0 }

export function usePlayer() {
  const [player, dispatch] = useReducer(reduce, START)

  // When the song will end, if it's playing.
  useEffect(() => {
    if (!player.playing) return
    const left = SONGS[player.song].duration - positionAt(player, performance.now())
    const timer = setTimeout(() => dispatch({ type: 'ended', now: performance.now(), random: Math.random() }), left * 1000 + 50)
    return () => clearTimeout(timer)
  }, [player])

  const actions = {
    play: (on: boolean) => dispatch({ type: 'play', on, now: performance.now() }),
    seek: (to: number) => dispatch({ type: 'seek', to, now: performance.now() }),
    skip: (step: 1 | -1) => dispatch({ type: 'skip', step, now: performance.now(), random: Math.random() }),
    toggle: (key: 'shuffle' | 'repeat') => dispatch({ type: 'toggle', key }),
  }
  return [player, actions] as const
}

export type PlayerActions = ReturnType<typeof usePlayer>[1]
