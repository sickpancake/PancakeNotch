import { useEffect, useRef } from 'react'

/* A swirl of dithered dots, drawn by the graphics card. Adapted from the "Swirl" dithering shader
   (designali-in on 21st.dev): same spiral and 4 × 4 Bayer dots, but soft gray on black (easier on the
   eyes than white, and it leaves the title the brightest thing), circular on any screen shape, and with a clear area in the middle that is sized to the content on top of it.

   It's light on purpose: the canvas has one pixel per dot (the browser scales it up without
   smoothing), and it stops drawing whenever it's off screen, the tab is hidden or the visitor asked
   for less motion. */

const DOT = 4 // CSS pixels per dot, like the original
const SPEED = 0.9 // the original demo's speed
const BRIGHTNESS = 0.5 // of the dots: 0.5 is mid gray (#808080)
const DENSITY = 0.6 // how packed the busiest parts get: 1 would be solid

const VERTEX = `#version 300 es
layout(location = 0) in vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`

const FRAGMENT = `#version 300 es
precision highp float;

uniform float u_time;
uniform vec2 u_resolution; // canvas size, in dots
uniform vec2 u_clear;      // half-size of the clear middle, in dots

out vec4 fragColor;

const float TWO_PI = 6.28318530718;
const int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

void main() {
  vec2 cell = floor(gl_FragCoord.xy);
  vec2 p = cell + 0.5 - 0.5 * u_resolution;

  // The spiral, measured against the short side so it stays round on wide and tall screens.
  vec2 uv = p / min(u_resolution.x, u_resolution.y);
  float l = max(length(uv), 1e-3);
  float t = 0.5 * u_time;
  float angle = 6.0 * atan(uv.y, uv.x + 1e-6) + 4.0 * t; // atan(0, 0) is undefined
  float offset = pow(l, -1.2) + angle / TWO_PI;

  // Density grows with the distance (in dots) beyond the clear middle, an ellipse around the
  // content, and tops out well below solid.
  float e = length(p / u_clear);
  float beyond = max(e - 1.0, 0.0) * length(p) / max(e, 1e-3);
  float ramp = 0.55 * min(u_resolution.x, u_resolution.y);
  float density = ${DENSITY.toFixed(2)} * smoothstep(0.0, 1.0, pow(min(beyond / ramp, 1.0), 0.7));

  float shape = fract(offset) * density;
  ivec2 b = ivec2(mod(cell, 4.0));
  float threshold = float(bayer[b.y * 4 + b.x]) / 16.0;
  float lit = step(1.0, shape + threshold);
  fragColor = vec4(vec3(lit * ${BRIGHTNESS.toFixed(2)}), 1.0);
}
`

type Props = {
  /** Half-size of the area to keep clear, in CSS pixels, centred on the canvas. */
  clear: { x: number; y: number }
  className?: string
}

export function DitherSwirl({ clear, className }: Props) {
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
    let uniforms: Record<'time' | 'resolution' | 'clear', WebGLUniformLocation | null> | null = null
    let width = 0
    let height = 0
    let frame = 0
    let last = 0
    let elapsed = 2 // seconds of animation so far; a still frame shows this moment
    let onScreen = true

    const setUp = () => {
      program = link(gl)
      if (!program) return
      uniforms = {
        time: gl.getUniformLocation(program, 'u_time'),
        resolution: gl.getUniformLocation(program, 'u_resolution'),
        clear: gl.getUniformLocation(program, 'u_clear'),
      }
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer())
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
      gl.enableVertexAttribArray(0)
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
      gl.useProgram(program)
    }

    const draw = () => {
      if (!program || !uniforms || gl.isContextLost()) return
      gl.viewport(0, 0, width, height)
      gl.uniform1f(uniforms.time, elapsed * SPEED)
      gl.uniform2f(uniforms.resolution, width, height)
      gl.uniform2f(uniforms.clear, Math.max(clearRef.current.x / DOT, 1), Math.max(clearRef.current.y / DOT, 1))
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
      const moving = !!program && onScreen && !document.hidden && !reduceMotion.matches
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

    play()

    return () => {
      cancelAnimationFrame(frame)
      sizes.disconnect()
      visibility.disconnect()
      document.removeEventListener('visibilitychange', play)
      reduceMotion.removeEventListener('change', play)
      canvas.removeEventListener('webglcontextlost', lost)
      canvas.removeEventListener('webglcontextrestored', restored)
      redrawRef.current = () => {}
      if (program) gl.deleteProgram(program)
    }
  }, [])

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
