import { useEffect, useLayoutEffect, useRef, type ReactNode } from 'react'
import { useReducedMotion } from 'motion/react'
import { cn } from '@/lib/utils'

/* Swaps one picture for another, tile by tile: the new picture grows in as a scatter of small squares,
   in random order, until it has covered the old one. It's two stacked layers, and the incoming one is
   shown through a clip-path made of the squares that have arrived so far (each one growing from its
   middle), so any content can be swapped, not just images. Reduce Motion swaps at once. */

type Props = {
  first: ReactNode
  second: ReactNode
  /** false shows `first`, true shows `second`. Changing it plays the swap. */
  showSecond: boolean
  /** Side of a tile, in pixels. */
  tile?: number
  /** Milliseconds for the whole swap. */
  duration?: number
  /** Milliseconds one tile takes to grow. */
  tileDuration?: number
  className?: string
}

const easeOut = (t: number) => 1 - Math.pow(1 - t, 3)

export function TileSwap({ first, second, showSecond, tile = 14, duration = 420, tileDuration = 320, className }: Props) {
  const reduce = useReducedMotion() ?? false
  const boxRef = useRef<HTMLDivElement>(null)
  const layers = useRef<Record<'a' | 'b', HTMLDivElement | null>>({ a: null, b: null })
  const front = useRef<'a' | 'b'>(showSecond ? 'b' : 'a')
  const finish = useRef<() => void>(() => {})

  // Which layer is on top to begin with.
  useLayoutEffect(() => {
    const { a, b } = layers.current
    if (a) a.style.zIndex = front.current === 'a' ? '1' : '0'
    if (b) b.style.zIndex = front.current === 'b' ? '1' : '0'
  }, [])

  useEffect(() => {
    const want = showSecond ? 'b' : 'a'
    if (want === front.current) return
    finish.current() // a swap still running is done in an instant
    const incoming = layers.current[want]
    const outgoing = layers.current[want === 'a' ? 'b' : 'a']
    const box = boxRef.current
    if (!incoming || !outgoing || !box) return

    front.current = want
    const settle = () => {
      incoming.style.clipPath = ''
      incoming.style.zIndex = '1'
      outgoing.style.zIndex = '0'
    }
    if (reduce) {
      settle()
      return
    }

    const columns = Math.ceil(box.clientWidth / tile)
    const rows = Math.ceil(box.clientHeight / tile)
    const lateness = Math.max(duration - tileDuration, 0)
    const delays = Array.from({ length: columns * rows }, () => Math.random() * lateness)
    incoming.style.zIndex = '2'
    outgoing.style.zIndex = '1'
    incoming.style.clipPath = 'inset(0 0 100% 0)' // nothing yet

    const began = performance.now()
    let frame = 0
    const step = (now: number) => {
      const elapsed = now - began
      let squares = ''
      delays.forEach((delay, i) => {
        const grown = Math.min(Math.max((elapsed - delay) / tileDuration, 0), 1)
        if (grown <= 0) return
        const side = tile * easeOut(grown) + (grown < 1 ? 0 : 1) // a pixel more at the end closes any gap
        const x = (i % columns) * tile + (tile - side) / 2
        const y = Math.floor(i / columns) * tile + (tile - side) / 2
        squares += `M${x} ${y}h${side}v${side}h${-side}z`
      })
      if (elapsed >= duration) {
        settle()
        finish.current = () => {}
        return
      }
      if (squares) incoming.style.clipPath = `path("${squares}")`
      frame = requestAnimationFrame(step)
    }
    finish.current = () => {
      cancelAnimationFrame(frame)
      settle()
    }
    frame = requestAnimationFrame(step)
  }, [showSecond, reduce, tile, duration, tileDuration])

  useEffect(() => () => finish.current(), [])

  return (
    <div ref={boxRef} className={cn('relative size-full overflow-hidden', className)}>
      <div ref={(element) => void (layers.current.a = element)} className="absolute inset-0">
        {first}
      </div>
      <div ref={(element) => void (layers.current.b = element)} className="absolute inset-0">
        {second}
      </div>
    </div>
  )
}
