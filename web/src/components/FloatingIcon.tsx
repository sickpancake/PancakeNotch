import { useEffect, useRef } from 'react'

/* The app icon, leaning toward the cursor like a card in your hand. Quick cursor moves make it
   wobble a little before it settles (an underdamped spring), and a slow float in CSS keeps it alive
   when the cursor rests. The spring only runs while something is moving. Touch screens get the float
   alone; Reduce Motion gets a still icon. */

const TILT = 14 // degrees at the edge of the screen
const DRIFT = { x: 16, y: 10 } // pixels at the edge of the screen
const WOBBLE = 0.006 // degrees of twist per pixel-per-second of cursor speed
const MAX_WOBBLE = 7 // degrees

type Spring = { value: number; velocity: number; target: number }
const spring = (): Spring => ({ value: 0, velocity: 0, target: 0 })

type Props = { src: string; className?: string }

export function FloatingIcon({ src, className }: Props) {
  const anchorRef = useRef<HTMLDivElement>(null)
  const tiltRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const anchor = anchorRef.current
    const element = tiltRef.current
    if (!anchor || !element) return
    const finePointer = matchMedia('(hover: hover) and (pointer: fine)')
    const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)')

    const axes = { rx: spring(), ry: spring(), rz: spring(), x: spring(), y: spring() }
    let frame = 0
    let last = 0
    let lastPointer: { x: number; t: number } | null = null

    const apply = () => {
      element.style.transform =
        `perspective(900px) translate3d(${axes.x.value.toFixed(2)}px, ${axes.y.value.toFixed(2)}px, 0) ` +
        `rotateX(${axes.rx.value.toFixed(2)}deg) rotateY(${axes.ry.value.toFixed(2)}deg) ` +
        `rotateZ(${axes.rz.value.toFixed(2)}deg)`
    }

    const step = (now: number) => {
      const dt = Math.min((now - (last || now)) / 1000, 1 / 30)
      last = now
      let moving = false
      for (const [name, s] of Object.entries(axes)) {
        // The twist springs back to zero by itself; it's only nudged by cursor speed.
        if (name === 'rz') s.target *= Math.exp(-dt * 10)
        const stiffness = name === 'rz' ? 260 : 90
        const damping = name === 'rz' ? 9 : 14
        s.velocity += ((s.target - s.value) * stiffness - s.velocity * damping) * dt
        s.value += s.velocity * dt
        if (Math.abs(s.velocity) > 0.01 || Math.abs(s.target - s.value) > 0.01) moving = true
      }
      apply()
      frame = moving ? requestAnimationFrame(step) : 0
      if (!moving) last = 0
    }

    const wake = () => {
      if (!frame) frame = requestAnimationFrame(step)
    }

    const onMove = (event: PointerEvent) => {
      if (event.pointerType !== 'mouse' && event.pointerType !== 'pen') return
      // Measured on the box that doesn't move, so the icon's own tilt doesn't feed back into it.
      const box = anchor.getBoundingClientRect()
      const cx = box.left + box.width / 2
      const cy = box.top + box.height / 2
      const nx = clamp((event.clientX - cx) / (innerWidth / 2))
      const ny = clamp((event.clientY - cy) / (innerHeight / 2))
      axes.ry.target = nx * TILT
      axes.rx.target = -ny * TILT
      axes.x.target = nx * DRIFT.x
      axes.y.target = ny * DRIFT.y
      if (lastPointer && event.timeStamp > lastPointer.t) {
        const speed = ((event.clientX - lastPointer.x) / (event.timeStamp - lastPointer.t)) * 1000
        axes.rz.target = clamp(speed * WOBBLE / MAX_WOBBLE) * MAX_WOBBLE
      }
      lastPointer = { x: event.clientX, t: event.timeStamp }
      wake()
    }

    const onLeave = () => {
      for (const s of Object.values(axes)) s.target = 0
      lastPointer = null
      wake()
    }

    const listen = () => {
      const active = finePointer.matches && !reduceMotion.matches
      window.removeEventListener('pointermove', onMove)
      document.documentElement.removeEventListener('pointerleave', onLeave)
      if (active) {
        window.addEventListener('pointermove', onMove, { passive: true })
        document.documentElement.addEventListener('pointerleave', onLeave)
      } else {
        onLeave()
      }
    }

    listen()
    finePointer.addEventListener('change', listen)
    reduceMotion.addEventListener('change', listen)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('pointermove', onMove)
      document.documentElement.removeEventListener('pointerleave', onLeave)
      finePointer.removeEventListener('change', listen)
      reduceMotion.removeEventListener('change', listen)
    }
  }, [])

  return (
    <div ref={anchorRef} className={className}>
      <div className="animate-float motion-reduce:animate-none">
        <div ref={tiltRef} className="will-change-transform">
          <img src={src} alt="" width={512} height={512} draggable={false} className="block h-full w-full select-none" />
        </div>
      </div>
    </div>
  )
}

function clamp(value: number) {
  return Math.max(-1, Math.min(1, value))
}
