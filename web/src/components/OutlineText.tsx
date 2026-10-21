import { useEffect, useRef, type CSSProperties } from 'react'

/* One line of text drawn on a canvas, so a letter can turn into something else when you point at it:
   the letter under the pointer becomes a dashed outline with a small frame round it, its size beside
   it and a few specks flickering about. The frame glides from letter to letter. When it first appears
   the text builds itself: little squares fly in from all around and lock into the letters, left to
   right. With Reduce Motion it appears at once and the specks stay still.

   The canvas may be bigger than the box that listens to the pointer (see `canvasClassName`), so the
   frame and its label have room outside the line. The text sits `EDGE` pixels in from the canvas's
   left, centred on the height of capital letters, so several lines line up. */

const EDGE = 28 // CSS pixels kept free round the text
const REACH = 28 // how far from a letter the pointer still counts as on it
const FRAME_PAD = 6
const SPECKS = 14
const BUILD_DELAY = 0.15 // seconds before the build starts
const LABEL_FONT = '10px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' // taste-skill-ignore: a size read-out, like code

type Props = {
  text: string
  /** Font size in CSS pixels. */
  fontSize: number
  fontWeight?: number
  /** Letter spacing in ems (negative is tighter). */
  letterSpacing?: number
  /** Seconds the build takes when the text first appears; 0 shows it at once. */
  build?: number
  /** The box that listens to the pointer. */
  className?: string
  /** The drawing area, which can reach beyond the box. */
  canvasClassName?: string
  style?: CSSProperties
}

type Glyph = { char: string; x: number; left: number; top: number; right: number; bottom: number; outline: number }
type Piece = { x: number; y: number; dx: number; dy: number; from: number; to: number }
type Dashed = { image: HTMLCanvasElement; x: number; y: number; w: number; h: number }

const approach = (now: number, goal: number, dt: number, seconds: number) => now + (goal - now) * (1 - Math.exp(-dt / seconds))
const clamp01 = (n: number) => Math.min(1, Math.max(0, n))

/** A repeatable pseudo-random number from up to three whole numbers, so specks can be re-rolled without being stored. */
function roll(a: number, b = 0, c = 0) {
  let h = (a * 374761393 + b * 668265263 + c * 2246822519) | 0
  h = Math.imul(h ^ (h >>> 15), 2246822519)
  h = Math.imul(h ^ (h >>> 13), 3266489917)
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296
}

export default function OutlineText({ text, fontSize, fontWeight = 700, letterSpacing = 0, build = 0, className, canvasClassName, style }: Props) {
  const boxRef = useRef<HTMLDivElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const propsRef = useRef({ text, fontSize, fontWeight, letterSpacing, build })
  const wakeRef = useRef<() => void>(() => {})

  useEffect(() => {
    propsRef.current = { text, fontSize, fontWeight, letterSpacing, build }
    wakeRef.current()
  })

  useEffect(() => {
    const box = boxRef.current
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    const probe = document.createElement('canvas').getContext('2d')
    if (!box || !canvas || !ctx || !probe) return

    const still = matchMedia('(prefers-reduced-motion: reduce)').matches
    let width = 1
    let height = 1
    let dpr = 1
    let layoutKey = ''
    let family = 'sans-serif'
    let ink = '#fff'
    let size = fontSize // the font size actually used (smaller if the line wouldn't fit)
    let baseline = 0
    let glyphs: Glyph[] = []
    const dashes = new Map<number, Dashed>()

    let pieces: Piece[] = []
    let pieceSize = 3
    let age = 0 // seconds since the build began
    let building = build > 0 && !still
    let hover = -1
    const pointer = { x: 0, y: 0, over: false }
    const frame = { left: 0, top: 0, right: 0, bottom: 0, alpha: 0, of: -1 }
    let clock = 0
    let raf = 0
    let last = 0
    let visible = true

    const setFont = (target: CanvasRenderingContext2D, px: number) => {
      target.font = `${propsRef.current.fontWeight} ${px}px ${family}`
      if ('letterSpacing' in target) target.letterSpacing = `${propsRef.current.letterSpacing * px}px`
      target.textAlign = 'left'
      target.textBaseline = 'alphabetic'
    }

    // Where every letter is, measured by laying the line out on a scratch canvas.
    const layout = () => {
      const p = propsRef.current
      const style = getComputedStyle(box)
      family = style.fontFamily || 'sans-serif'
      ink = style.color || '#fff'
      size = p.fontSize
      setFont(probe, size)
      let whole = probe.measureText(p.text)
      const room = width - EDGE * 2
      const reach = whole.actualBoundingBoxLeft + whole.actualBoundingBoxRight
      if (reach > room) {
        size *= room / reach
        setFont(probe, size)
        whole = probe.measureText(p.text)
      }
      const startX = EDGE + whole.actualBoundingBoxLeft
      baseline = (height + probe.measureText('H').actualBoundingBoxAscent) / 2
      glyphs = []
      let upTo = ''
      for (const char of p.text) {
        upTo += char
        const own = probe.measureText(char)
        const x = startX + probe.measureText(upTo).width - own.width // includes the kerning with the letter before
        if (!char.trim()) continue
        glyphs.push({
          char,
          x,
          left: x - own.actualBoundingBoxLeft,
          right: x + own.actualBoundingBoxRight,
          top: baseline - own.actualBoundingBoxAscent,
          bottom: baseline + own.actualBoundingBoxDescent,
          outline: 0,
        })
      }
      dashes.clear()
      pieces = []
      frame.of = -1
      frame.alpha = 0
    }

    const checkLayout = () => {
      const p = propsRef.current
      const key = [p.text, p.fontSize, p.fontWeight, p.letterSpacing, width, height, dpr].join('|')
      if (key === layoutKey) return
      layoutKey = key
      layout()
    }

    // The little squares of the build: every spot of the letters, on a coarse grid, gets a square that
    // starts somewhere nearby and flies home.
    const makePieces = () => {
      pieceSize = Math.max(3, Math.round(size / 26))
      const sheet = document.createElement('canvas')
      sheet.width = Math.max(1, Math.ceil(width))
      sheet.height = Math.max(1, Math.ceil(height))
      const sheetCtx = sheet.getContext('2d', { willReadFrequently: true })
      if (!sheetCtx || !glyphs.length) return
      setFont(sheetCtx, size)
      sheetCtx.fillStyle = '#fff'
      for (const g of glyphs) sheetCtx.fillText(g.char, g.x, baseline)
      const pixels = sheetCtx.getImageData(0, 0, sheet.width, sheet.height).data
      const covered = (x: number, y: number) => {
        const px = Math.min(sheet.width - 1, Math.max(0, Math.round(x)))
        const py = Math.min(sheet.height - 1, Math.max(0, Math.round(y)))
        return pixels[(py * sheet.width + px) * 4 + 3] > 50
      }
      const inkLeft = glyphs[0].left
      const inkWidth = Math.max(1, glyphs[glyphs.length - 1].right - inkLeft)
      const top = Math.min(...glyphs.map((g) => g.top))
      const bottom = Math.max(...glyphs.map((g) => g.bottom))
      let n = 0
      for (let y = Math.floor(top / pieceSize) * pieceSize; y < bottom; y += pieceSize) {
        for (let x = Math.floor(inkLeft / pieceSize) * pieceSize; x < inkLeft + inkWidth; x += pieceSize) {
          const s = pieceSize - 1
          if (!(covered(x + 1, y + 1) || covered(x + s, y + 1) || covered(x + 1, y + s) || covered(x + s, y + s))) continue
          n++
          const along = (x - inkLeft) / inkWidth
          const to = 0.1 + 0.55 * along + 0.2 * roll(n)
          const angle = roll(n, 1) * Math.PI * 2
          const far = size * (0.25 + 0.6 * roll(n, 2))
          pieces.push({ x, y, dx: Math.cos(angle) * far, dy: Math.sin(angle) * far * 0.7, from: to - (0.26 + 0.14 * roll(n, 3)), to })
        }
      }
    }

    // The outline of a letter: dashes just outside its edge, with the inside cut away. Made when first needed.
    const dashed = (index: number): Dashed => {
      const cached = dashes.get(index)
      if (cached) return cached
      const g = glyphs[index]
      const pad = 6
      const w = Math.ceil(g.right - g.left) + pad * 2
      const h = Math.ceil(g.bottom - g.top) + pad * 2
      const image = document.createElement('canvas')
      image.width = Math.max(1, Math.ceil(w * dpr))
      image.height = Math.max(1, Math.ceil(h * dpr))
      const c = image.getContext('2d')
      const result = { image, x: g.left - pad, y: g.top - pad, w, h }
      if (c) {
        c.setTransform(dpr, 0, 0, dpr, (pad - g.left) * dpr, (pad - g.top) * dpr)
        setFont(c, size)
        c.lineJoin = 'round'
        c.lineWidth = 3
        c.strokeStyle = ink
        c.setLineDash([4, 2])
        c.strokeText(g.char, g.x, baseline)
        c.globalCompositeOperation = 'destination-out'
        c.fillText(g.char, g.x, baseline)
      }
      dashes.set(index, result)
      return result
    }

    const glyphAt = (x: number, y: number) => {
      if (!glyphs.length) return -1
      const top = Math.min(...glyphs.map((g) => g.top))
      const bottom = Math.max(...glyphs.map((g) => g.bottom))
      if (y < top - REACH || y > bottom + REACH) return -1
      let best = -1
      let nearest = Infinity
      glyphs.forEach((g, i) => {
        const away = x < g.left ? g.left - x : x > g.right ? x - g.right : 0
        if (away < nearest) {
          nearest = away
          best = i
        }
      })
      return nearest < REACH ? best : -1
    }

    const paintLetters = () => {
      ctx.fillStyle = ink
      glyphs.forEach((g, i) => {
        if (g.outline < 0.999) {
          ctx.globalAlpha = 1 - g.outline
          ctx.fillText(g.char, g.x, baseline)
        }
        if (g.outline > 0.001) {
          const d = dashed(i)
          ctx.globalAlpha = g.outline
          ctx.drawImage(d.image, d.x, d.y, d.w, d.h)
        }
      })
      ctx.globalAlpha = 1
    }

    const paintBuild = (progress: number) => {
      if (!pieces.length) makePieces()
      // The squares that have landed show the letters themselves; the rest are still on their way.
      ctx.save()
      ctx.beginPath()
      for (const p of pieces) if (progress >= p.to) ctx.rect(p.x, p.y, pieceSize, pieceSize)
      ctx.clip()
      paintLetters()
      ctx.restore()
      ctx.fillStyle = ink
      for (const p of pieces) {
        if (progress < p.from || progress >= p.to) continue
        const u = (progress - p.from) / (p.to - p.from)
        const e = 1 - Math.pow(1 - u, 4)
        const s = pieceSize * (0.4 + 0.6 * e)
        ctx.globalAlpha = Math.min(1, u * 4) * (0.55 + 0.45 * e)
        ctx.fillRect(p.x + (pieceSize - s) / 2 + p.dx * (1 - e), p.y + (pieceSize - s) / 2 + p.dy * (1 - e), s, s)
      }
      ctx.globalAlpha = 1
    }

    // A point on the frame's edge, `d` pixels along it from the top left, going clockwise, and which way is out.
    const along = (d: number, w: number, h: number): [number, number, number, number] => {
      const round = 2 * (w + h)
      let s = ((d % round) + round) % round
      if (s < w) return [frame.left + s, frame.top, 0, -1]
      s -= w
      if (s < h) return [frame.right, frame.top + s, 1, 0]
      s -= h
      if (s < w) return [frame.right - s, frame.bottom, 0, 1]
      s -= w
      return [frame.left, frame.bottom - s, -1, 0]
    }

    const paintSpecks = (alpha: number) => {
      const w = frame.right - frame.left
      const h = frame.bottom - frame.top
      const round = 2 * (w + h)
      const seed = frame.of + 1
      ctx.fillStyle = ink
      ctx.strokeStyle = ink
      for (let k = 0; k < SPECKS; k++) {
        const t = clock * (0.55 + roll(seed, k, 1) * 1.1) + roll(seed, k, 2)
        const cycle = Math.floor(t)
        const life = t - cycle
        if (life > 0.65) continue
        const [px, py, nx, ny] = along(roll(seed, k, cycle + 1000) * round, w, h)
        const kind = roll(seed, k, cycle + 2000)
        const side = kind < 0.5 ? 2 : kind < 0.75 ? 3 : kind < 0.9 ? 5 : 8
        const out = 4 + Math.floor(roll(seed, k, cycle + 3000) * 5) * 3
        const x = Math.round((px + nx * out) / 3) * 3
        const y = Math.round((py + ny * out) / 3) * 3
        ctx.globalAlpha = alpha * (0.3 + 0.6 * roll(seed, k, cycle + 4000)) * (life < 0.06 ? 0.4 : 1)
        if (side >= 5 && kind > 0.8) ctx.strokeRect(Math.round(x - side / 2) + 0.5, Math.round(y - side / 2) + 0.5, side, side)
        else ctx.fillRect(Math.round(x - side / 2), Math.round(y - side / 2), side, side)
      }
      // Two bright dots with short tails, running round the frame.
      for (let runner = 0; runner < 2; runner++) {
        const head = (clock * 0.42 + runner * 0.5) * round
        for (let i = 0; i < 4; i++) {
          const [x, y] = along(head - i * 6, w, h)
          const side = i === 0 ? 3 : 2
          ctx.globalAlpha = alpha * [0.95, 0.55, 0.32, 0.16][i]
          ctx.fillRect(Math.round(x - side / 2), Math.round(y - side / 2), side, side)
        }
      }
      ctx.globalAlpha = 1
    }

    const paintFrame = () => {
      const g = glyphs[frame.of]
      if (!g || frame.alpha < 0.01) return
      const a = frame.alpha
      const left = Math.round(frame.left) + 0.5
      const top = Math.round(frame.top) + 0.5
      const w = Math.round(frame.right) - Math.round(frame.left)
      const h = Math.round(frame.bottom) - Math.round(frame.top)
      ctx.fillStyle = ink
      ctx.strokeStyle = ink
      ctx.lineWidth = 1
      ctx.globalAlpha = 0.5 * a
      ctx.strokeRect(left, top, w, h)
      ctx.globalAlpha = 0.95 * a
      for (const [x, y] of [[left, top], [left + w, top], [left + w, top + h], [left, top + h]]) ctx.fillRect(Math.round(x) - 2, Math.round(y) - 2, 5, 5)
      if (!still) paintSpecks(a)
      ctx.font = LABEL_FONT
      ctx.textBaseline = 'bottom'
      ctx.globalAlpha = 0.62 * a
      ctx.fillText(`${g.char}  ${Math.round(g.right - g.left)} × ${Math.round(g.bottom - g.top)}`, Math.round(frame.left), Math.round(frame.top) - 7)
      ctx.globalAlpha = 1
    }

    const tick = (now: number) => {
      raf = 0
      const dt = Math.min(0.05, Math.max(0.001, (now - last) / 1000))
      last = now
      checkLayout()
      clock += dt

      let progress = 1
      if (building) {
        age += dt
        progress = clamp01((age - BUILD_DELAY) / Math.max(0.3, propsRef.current.build))
        if (progress >= 1) building = false
      }
      hover = !building && pointer.over ? glyphAt(pointer.x, pointer.y) : -1

      let moving = building
      glyphs.forEach((g, i) => {
        const goal = i === hover ? 1 : 0
        g.outline = approach(g.outline, goal, dt, 0.09)
        if (Math.abs(g.outline - goal) > 0.002) moving = true
        else g.outline = goal
      })

      // The frame glides to the letter being pointed at, and fades out when there's none.
      if (hover >= 0) {
        const g = glyphs[hover]
        const goal = { left: g.left - FRAME_PAD, top: g.top - FRAME_PAD, right: g.right + FRAME_PAD, bottom: g.bottom + FRAME_PAD }
        if (frame.of < 0 || frame.alpha < 0.02) Object.assign(frame, goal)
        for (const side of ['left', 'top', 'right', 'bottom'] as const) frame[side] = approach(frame[side], goal[side], dt, 0.08)
        frame.of = hover
        frame.alpha = approach(frame.alpha, 1, dt, 0.1)
      } else {
        frame.alpha = approach(frame.alpha, 0, dt, 0.1)
      }

      ctx.setTransform(1, 0, 0, 1, 0, 0)
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      setFont(ctx, size)
      if (building) paintBuild(progress)
      else paintLetters()
      paintFrame()

      if ((moving || frame.alpha > 0.01 || hover >= 0) && visible) raf = requestAnimationFrame(tick)
    }

    const wake = () => {
      if (raf || !visible) return
      last = performance.now()
      raf = requestAnimationFrame(tick)
    }
    wakeRef.current = wake

    const resize = () => {
      width = Math.max(1, canvas.clientWidth)
      height = Math.max(1, canvas.clientHeight)
      dpr = Math.min(devicePixelRatio || 1, 2)
      canvas.width = Math.round(width * dpr)
      canvas.height = Math.round(height * dpr)
      wake()
    }
    const place = (event: PointerEvent) => {
      const at = canvas.getBoundingClientRect()
      pointer.x = event.clientX - at.left
      pointer.y = event.clientY - at.top
      pointer.over = true
      wake()
    }
    const leave = () => {
      pointer.over = false
      wake()
    }

    box.addEventListener('pointerenter', place, { passive: true })
    box.addEventListener('pointermove', place, { passive: true })
    box.addEventListener('pointerleave', leave, { passive: true })
    const sizes = new ResizeObserver(resize)
    sizes.observe(canvas)
    const sight = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting
      wake()
    })
    sight.observe(box)
    document.fonts?.ready.then(() => {
      layoutKey = ''
      wake()
    })
    resize()

    return () => {
      cancelAnimationFrame(raf)
      wakeRef.current = () => {}
      sizes.disconnect()
      sight.disconnect()
      box.removeEventListener('pointerenter', place)
      box.removeEventListener('pointermove', place)
      box.removeEventListener('pointerleave', leave)
    }
    // The line is set up once; later changes to the props are picked up through `propsRef`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div ref={boxRef} className={`touch-pan-y select-none ${className ?? ''}`.trim()} style={style} role="img" aria-label={text}>
      <canvas ref={canvasRef} className={canvasClassName ?? 'block size-full'} />
    </div>
  )
}
