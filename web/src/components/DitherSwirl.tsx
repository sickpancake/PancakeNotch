import { useEffect, useRef } from 'react'
import type { MotionValue } from 'motion/react'

/* A swirl of dithered dots, drawn by the graphics card. The look follows the dithered "Swirl" shaders
   published on 21st.dev (the same effect is listed there under Apache-2.0 by Paper Shaders): a spiral
   cut into dots by a 4 × 4 ordered dither, both ordinary techniques. The shader and everything around
   it here is written for this site: soft gray on black (easier on the eyes than white, and it leaves
   the title the brightest thing), circular on any screen shape, with a clear area in the middle that
   is sized to the content on top of it.

   It's light on purpose: the canvas has one pixel per dot (the browser scales it up without
   smoothing), and it stops drawing whenever it's off screen, the tab is hidden or the visitor asked
   for less motion.

   Scrolling flies into it: the swirl grows toward you, its rings spreading out past the edges while
   its dots fade out. `flight` runs from 0 (resting) to 1 (all the way through). */

const DOT = 4 // CSS pixels per dot, like the original
const SPEED = 0.6 // two thirds of the original demo's speed: calmer to look at
const BRIGHTNESS = 0.38 // of the dots: dim gray (#616161)
const DENSITY = 0.5 // how packed the busiest parts get: 1 would be solid

const VERTEX = `#version 300 es
layout(location = 0) in vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`

const FRAGMENT = `#version 300 es
precision highp float;

uniform float u_time;
uniform vec2 u_resolution; // canvas size, in dots
uniform vec2 u_clear;      // half-size of the clear middle, in dots
uniform float u_travel;    // how far the rings have turned while flying in
uniform float u_zoom;      // size of the whole swirl, 1 at rest, bigger as it comes toward you
uniform float u_density;   // how packed the busiest parts get
uniform float u_brightness;

out vec4 fragColor;

const float TWO_PI = 6.28318530718;
const int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

// How strongly the spiral covers this spot (0 to the density), before dithering.
float field(vec2 screen) {
  vec2 p = screen / u_zoom; // coming closer grows everything, clear middle included
  // The spiral, measured against the short side so it stays round on wide and tall screens.
  vec2 uv = p / min(u_resolution.x, u_resolution.y);
  float l = max(length(uv), 1e-3);
  float t = 0.5 * u_time;
  float angle = 6.0 * atan(uv.y, uv.x + 1e-6) + 4.0 * t; // atan(0, 0) is undefined
  float offset = pow(l, -1.2) + angle / TWO_PI + u_travel;

  // Density grows with the distance (in dots) beyond the clear middle, an ellipse around the
  // content, and tops out well below solid.
  float e = length(p / u_clear);
  float beyond = max(e - 1.0, 0.0) * length(p) / max(e, 1e-3);
  float ramp = 0.55 * min(u_resolution.x, u_resolution.y);
  float density = u_density * smoothstep(0.0, 1.0, pow(min(beyond / ramp, 1.0), 0.7));

  return fract(offset) * density;
}

void main() {
  vec2 cell = floor(gl_FragCoord.xy);
  vec2 p = cell + 0.5 - 0.5 * u_resolution;
  float shape = field(p);

  ivec2 b = ivec2(mod(cell, 4.0));
  float threshold = float(bayer[b.y * 4 + b.x]) / 16.0;
  float lit = step(1.0, shape + threshold);
  fragColor = vec4(vec3(lit * u_brightness), 1.0);
}
`

type Props = {
  /** Half-size of the area to keep clear, in CSS pixels, centred on the canvas. */
  clear: { x: number; y: number }
  /** How far into the swirl we've flown, 0 to 1. At 1 the swirl is out of sight and stops drawing. */
  flight?: MotionValue<number>
  className?: string
}

/** What the shader gets for a point in the flight (0 to 1). */
function inFlight(f: number) {
  const ease = (from: number, to: number) => {
    const x = Math.min(Math.max((f - from) / (to - from), 0), 1)
    return x * x * (3 - 2 * x)
  }
  return {
    travel: 1.2 * ease(0, 1), // a gentle turn that also pushes the rings outward
    zoom: 1 + 2 * ease(0, 1), // up to three times its size: the rings stream out past the edges
    density: DENSITY,
    brightness: BRIGHTNESS * (1 - ease(0.3, 0.85)), // fades out before the end
  }
}

export function DitherSwirl({ clear, flight, className }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const clearRef = useRef(clear)
  const redrawRef = useRef<() => void>(() => {})

  useEffect(() => {
    clearRef.current = clear
    redrawRef.current()
  }, [clear])

  useEffect(() => {
    const canvas = canvasRef.current
    const box = canvas?.parentElement
    if (!canvas || !box) return

    const gl = canvas.getContext('webgl2', { antialias: false, alpha: false, powerPreference: 'low-power' })
    if (!gl) return // No WebGL 2: the page stays plain black.

    const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)')
    let program: WebGLProgram | null = null
    let buffer: WebGLBuffer | null = null
    let uniforms: Record<string, WebGLUniformLocation | null> | null = null
    let width = 0
    let height = 0
    let frame = 0
    let last = 0
    let elapsed = 2 // seconds of animation so far; a still frame shows this moment
    let onScreen = true

    const setUp = () => {
      program = link(gl)
      if (!program) return
      const linked = program
      uniforms = Object.fromEntries(
        ['time', 'resolution', 'clear', 'travel', 'zoom', 'density', 'brightness'].map((name) => [
          name,
          gl.getUniformLocation(linked, `u_${name}`),
        ]),
      )
      buffer = gl.createBuffer()
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
      gl.enableVertexAttribArray(0)
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
      gl.useProgram(program)
    }

    const draw = () => {
      if (!program || !uniforms || gl.isContextLost()) return
      const f = inFlight(flight?.get() ?? 0)
      gl.viewport(0, 0, width, height)
      gl.uniform1f(uniforms.time, elapsed * SPEED)
      gl.uniform2f(uniforms.resolution, width, height)
      gl.uniform2f(uniforms.clear, Math.max(clearRef.current.x / DOT, 1), Math.max(clearRef.current.y / DOT, 1))
      gl.uniform1f(uniforms.travel, f.travel)
      gl.uniform1f(uniforms.zoom, f.zoom)
      gl.uniform1f(uniforms.density, f.density)
      gl.uniform1f(uniforms.brightness, f.brightness)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
    }

    const tick = (now: number) => {
      frame = 0
      if (!program) return // the graphics card was reset; "restored" starts drawing again
      // Stay at 60 frames a second or less, even on 120 Hz screens.
      if (last && now - last < 1000 / 61) {
        frame = requestAnimationFrame(tick)
        return
      }
      if (last) elapsed += Math.min(now - last, 100) / 1000
      last = now
      draw()
      frame = requestAnimationFrame(tick)
    }

    const play = () => {
      const through = (flight?.get() ?? 0) >= 1
      const moving = !!program && onScreen && !through && !document.hidden && !reduceMotion.matches
      if (moving && !frame) {
        last = 0
        frame = requestAnimationFrame(tick)
      } else if (!moving && frame) {
        cancelAnimationFrame(frame)
        frame = 0
      }
    }

    const resize = () => {
      const w = box.clientWidth
      const h = box.clientHeight
      width = Math.max(1, Math.ceil(w / DOT))
      height = Math.max(1, Math.ceil(h / DOT))
      canvas.width = width
      canvas.height = height
      // The canvas is a whole number of dots, so it can be a little bigger than the box: centre it.
      canvas.style.width = `${width * DOT}px`
      canvas.style.height = `${height * DOT}px`
      canvas.style.left = `${(w - width * DOT) / 2}px`
      canvas.style.top = `${(h - height * DOT) / 2}px`
      draw()
    }

    redrawRef.current = draw
    setUp()
    resize()

    const sizes = new ResizeObserver(resize)
    sizes.observe(box)
    const visibility = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting
      play()
    })
    visibility.observe(canvas)
    document.addEventListener('visibilitychange', play)
    reduceMotion.addEventListener('change', play)

    const lost = (event: Event) => {
      event.preventDefault()
      cancelAnimationFrame(frame)
      frame = 0
      program = null
    }
    const restored = () => {
      setUp()
      draw()
      play()
    }
    canvas.addEventListener('webglcontextlost', lost)
    canvas.addEventListener('webglcontextrestored', restored)

    // Scrolling moves the flight: keep drawing while it changes, even when the swirl holds still.
    const unfollow = flight?.on('change', () => {
      play()
      if (!frame) draw()
    })

    play()

    return () => {
      unfollow?.()
      cancelAnimationFrame(frame)
      sizes.disconnect()
      visibility.disconnect()
      document.removeEventListener('visibilitychange', play)
      reduceMotion.removeEventListener('change', play)
      canvas.removeEventListener('webglcontextlost', lost)
      canvas.removeEventListener('webglcontextrestored', restored)
      redrawRef.current = () => {}
      if (program) gl.deleteProgram(program)
      if (buffer) gl.deleteBuffer(buffer)
    }
  }, [flight])

  return (
    <div className={className} aria-hidden="true">
      <canvas ref={canvasRef} className="absolute [image-rendering:pixelated]" />
    </div>
  )
}

function link(gl: WebGL2RenderingContext) {
  const compile = (type: number, source: string) => {
    const shader = gl.createShader(type)
    if (!shader) return null
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader
    console.error(gl.getShaderInfoLog(shader))
    gl.deleteShader(shader)
    return null
  }
  const vertex = compile(gl.VERTEX_SHADER, VERTEX)
  const fragment = compile(gl.FRAGMENT_SHADER, FRAGMENT)
  if (!vertex || !fragment) return null
  const program = gl.createProgram()
  gl.attachShader(program, vertex)
  gl.attachShader(program, fragment)
  gl.linkProgram(program)
  gl.deleteShader(vertex)
  gl.deleteShader(fragment)
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program
  console.error(gl.getProgramInfoLog(program))
  gl.deleteProgram(program)
  return null
}
