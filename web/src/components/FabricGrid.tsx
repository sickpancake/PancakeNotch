import { useEffect, useRef } from 'react'
import { useReducedMotion, type MotionValue } from 'motion/react'

/* The backdrop of the rest of the page: a grid of fine gray lines draped over slow, soft folds, like
   a sheet of cloth under the page. The folds catch light from the upper left, so the grid bends and
   brightens over them. The pointer dents the cloth as it moves (each bit of its path becomes a dent
   that ripples outward and fades within a couple of seconds, so nothing stays disturbed), and a click
   makes a bigger one.

   It's one fixed layer over the whole screen, and it only shows once `cover` starts to rise: then it
   arrives the way the opening swirl is drawn, as 4 px square dots, switching on from the top of the
   screen down (an ordered dither), until it covers the notch section completely. Before that it draws
   nothing and costs nothing. It stops when the tab is hidden, and with Reduce Motion it fades in
   instead and the cloth holds still. */

const SCALE = 1.25 // most canvas pixels per CSS pixel: lines stay sharp without a big drawing area
const GUSTS = 12 // bits of the pointer's recent path that still dent the cloth
const LIFE = 1.6 // seconds before a dent has gone

const VERTEX = `#version 300 es
layout(location = 0) in vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`

const FRAGMENT = `#version 300 es
precision highp float;

uniform vec2 u_res;        // the screen, in CSS pixels
uniform float u_scale;     // canvas pixels per CSS pixel
uniform float u_time;
uniform float u_cover;     // 0 shows nothing, 1 covers everything
uniform float u_still;     // 1 with Reduce Motion: cover fades instead of dissolving
uniform vec4 u_gusts[${GUSTS}];     // x, y (CSS pixels from the top left), strength 0 to 1, unused
uniform float u_ages[${GUSTS}];     // seconds since each dent was made (negative = unused)

out vec4 fragColor;

const float CELL = 56.0; // the grid's squares, in CSS pixels

// Slow folds: a few long waves bent by each other, so they curl like cloth instead of rolling like water.
float folds(vec2 p, float t) {
  vec2 q = p / 620.0;
  float h = 0.0;
  h += sin(q.x * 2.1 + sin(q.y * 1.7 + t * 0.11) * 1.6 + t * 0.07) * 0.55;
  h += sin(dot(q, vec2(0.8, 1.9)) + sin(q.x * 2.3 - t * 0.09) * 1.3 - t * 0.05) * 0.40;
  h += sin(dot(q, vec2(-1.7, 1.1)) * 1.9 + t * 0.08) * 0.22;
  return h * 82.0;
}

// The cloth's height at a spot: the folds, plus the dents the pointer has made.
float height(vec2 p, float t) {
  float dents = 0.0;
  for (int i = 0; i < ${GUSTS}; i++) {
    float age = u_ages[i];
    if (age < 0.0) continue;
    vec4 gust = u_gusts[i];
    vec2 d = p - gust.xy;
    float r2 = dot(d, d);
    float radius = 80.0 + age * 90.0;
    if (r2 > 16.0 * radius * radius) continue;
    float fade = 1.0 - smoothstep(0.0, ${LIFE.toFixed(2)}, age);
    float r = sqrt(r2);
    float dent = -32.0 * exp(-r2 / (radius * radius));
    // The ripple dies out smoothly before the cut-off above, so no ring edge shows.
    float ripple = 5.5 * sin(r * 0.04 - age * 8.0) * exp(-r / 200.0) * (1.0 - smoothstep(1.5 * radius, 3.5 * radius, r));
    dents += gust.z * fade * fade * (dent + ripple);
  }
  // However many dents overlap, the cloth only goes so deep.
  return folds(p, t) + 42.0 * tanh(dents / 42.0);
}

// 4 by 4 ordered dither, the same dots as the opening swirl.
float bayer(vec2 cell) {
  ivec2 b = ivec2(mod(cell, 4.0));
  int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
  return (float(m[b.y * 4 + b.x]) + 0.5) / 16.0;
}

float gridLines(vec2 g) {
  vec2 width = max(fwidth(g), vec2(1e-4)); // lines stay one screen pixel wide, however the cloth stretches
  vec2 d = abs(fract(g - 0.5) - 0.5) / width;
  return 1.0 - min(min(d.x, d.y), 1.0);
}

void main() {
  vec2 frag = gl_FragCoord.xy / u_scale;
  vec2 p = vec2(frag.x, u_res.y - frag.y);
  float t = u_time;

  float e = 3.0;
  float h0 = height(p, t);
  vec2 slope = vec2(height(p + vec2(e, 0.0), t) - h0, height(p + vec2(0.0, e), t) - h0) / e;
  vec3 n = normalize(vec3(-slope * 3.2, 1.0));
  float shade = smoothstep(0.15, 0.95, dot(n, normalize(vec3(-0.45, -0.55, 0.7))));

  // The grid, bent over the folds, with a finer weave between its lines.
  vec2 g = (p + slope * 60.0) / CELL;
  float lines = max(gridLines(g), 0.3 * gridLines(g * 4.0));
  float v = 0.04 * shade * shade + 0.36 * lines * (0.22 + 0.78 * shade);

  // How much of the screen is covered: switching on cell by cell, from the top down.
  vec2 cell = floor(gl_FragCoord.xy / (4.0 * u_scale));
  float top = 1.0 - frag.y / u_res.y;
  float on = step(bayer(cell), u_cover * 1.6 - 0.6 * top);
  on = mix(on, u_cover, u_still);

  fragColor = vec4(vec3(v) * on, on);
}
`

type Props = {
  /** 0 shows nothing; as it rises the cloth switches on from the top down, and at 1 it covers the screen. */
  cover: MotionValue<number>
}

export function FabricGrid({ cover }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const reduce = useReducedMotion() ?? false
  const reduceRef = useRef(reduce)
  const wakeRef = useRef<() => void>(() => {})

  useEffect(() => {
    reduceRef.current = reduce
    wakeRef.current()
  }, [reduce])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const gl = canvas.getContext('webgl2', { antialias: false, alpha: true, premultipliedAlpha: true, powerPreference: 'low-power' })
    if (!gl) return // No WebGL 2: the page stays plain black.

    let program: WebGLProgram | null = null
    let buffer: WebGLBuffer | null = null
    let uniforms: Record<string, WebGLUniformLocation | null> = {}
    let width = 1 // CSS pixels
    let height = 1
    let scale = 1
    let frame = 0
    let last = 0
    let elapsed = 8 // seconds of motion so far; a still frame shows this moment
    const pointer = { x: 0, y: 0, at: -9999, vx: 0, vy: 0 }
    const dented = { x: 0, y: 0 } // where the last dent was left
    const gusts: { x: number; y: number; strength: number; age: number }[] = [] // newest first

    const setUp = () => {
      program = link(gl)
      if (!program) return
      uniforms = Object.fromEntries(
        ['res', 'scale', 'time', 'cover', 'still', 'gusts', 'ages'].map((name) => [name, gl.getUniformLocation(program!, `u_${name}`)]),
      )
      buffer = gl.createBuffer()
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
      gl.enableVertexAttribArray(0)
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
      gl.useProgram(program)
    }

    const draw = () => {
      if (!program || gl.isContextLost()) return
      const amount = cover.get()
      gl.viewport(0, 0, canvas.width, canvas.height)
      if (amount <= 0.0005) {
        gl.clearColor(0, 0, 0, 0)
        gl.clear(gl.COLOR_BUFFER_BIT)
        return
      }
      const dents = new Float32Array(GUSTS * 4)
      const ages = new Float32Array(GUSTS).fill(-1)
      gusts.forEach((gust, i) => {
        dents.set([gust.x, gust.y, gust.strength, 0], i * 4)
        ages[i] = gust.age
      })
      gl.uniform2f(uniforms.res, width, height)
      gl.uniform1f(uniforms.scale, scale)
      gl.uniform1f(uniforms.time, elapsed)
      gl.uniform1f(uniforms.cover, Math.min(amount, 1))
      gl.uniform1f(uniforms.still, reduceRef.current ? 1 : 0)
      gl.uniform4fv(uniforms.gusts, dents)
      gl.uniform1fv(uniforms.ages, ages)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
    }

    const tick = (now: number) => {
      frame = 0
      if (!program) return
      // The cloth drifts slowly, so 30 frames a second are plenty until the pointer is denting it.
      if (last && now - last < (gusts.length ? 1000 / 61 : 1000 / 31)) {
        frame = requestAnimationFrame(tick)
        return
      }
      const dt = last ? Math.min(now - last, 100) / 1000 : 0
      last = now
      elapsed += dt
      for (const gust of gusts) gust.age += dt
      while (gusts.length && gusts[gusts.length - 1].age > LIFE) gusts.pop()
      draw()
      frame = requestAnimationFrame(tick)
    }

    // Moving only while it shows (cover above 0), the tab is visible and Reduce Motion is off.
    const wake = () => {
      const moving = !!program && cover.get() > 0.0005 && !document.hidden && !reduceRef.current
      if (moving && !frame) {
        last = 0
        frame = requestAnimationFrame(tick)
      } else if (!moving && frame) {
        cancelAnimationFrame(frame)
        frame = 0
      }
      if (!moving) draw() // clears it, or paints the one still frame
    }
    wakeRef.current = wake

    const resize = () => {
      width = Math.max(1, canvas.clientWidth)
      height = Math.max(1, canvas.clientHeight)
      scale = Math.min(devicePixelRatio || 1, SCALE)
      canvas.width = Math.max(1, Math.round(width * scale))
      canvas.height = Math.max(1, Math.round(height * scale))
      draw()
    }

    const dent = (x: number, y: number, strength: number) => {
      gusts.unshift({ x, y, strength, age: 0 })
      if (gusts.length > GUSTS) gusts.pop()
    }
    const move = (event: PointerEvent) => {
      if (cover.get() < 0.9 || reduceRef.current) return
      const dt = (event.timeStamp - pointer.at) / 1000
      if (dt > 0.001 && dt < 0.2) {
        // How fast it's going, smoothed a little because pointer events come in uneven steps.
        const speed = Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y) / dt
        pointer.vx = 0.5 * pointer.vx + 0.5 * speed
        if (Math.hypot(event.clientX - dented.x, event.clientY - dented.y) > 18) {
          dent(event.clientX, event.clientY, 0.3 + 0.7 * Math.min(pointer.vx / 900, 1))
          dented.x = event.clientX
          dented.y = event.clientY
        }
      } else {
        pointer.vx = 0
        dented.x = event.clientX
        dented.y = event.clientY
      }
      pointer.x = event.clientX
      pointer.y = event.clientY
      pointer.at = event.timeStamp
    }
    const press = (event: PointerEvent) => {
      if (cover.get() < 0.9 || reduceRef.current) return
      // Not when using a control.
      if ((event.target as Element | null)?.closest('button, a, input, [role="region"], [data-ui]')) return
      dent(event.clientX, event.clientY, 1)
    }

    setUp()
    resize()
    const unfollow = cover.on('change', wake)
    const sizes = new ResizeObserver(resize)
    sizes.observe(canvas)
    document.addEventListener('visibilitychange', wake)
    window.addEventListener('pointermove', move, { passive: true })
    window.addEventListener('pointerdown', press, { passive: true })

    const lost = (event: Event) => {
      event.preventDefault()
      cancelAnimationFrame(frame)
      frame = 0
      program = null
    }
    const restored = () => {
      setUp()
      draw()
      wake()
    }
    canvas.addEventListener('webglcontextlost', lost)
    canvas.addEventListener('webglcontextrestored', restored)

    wake()

    return () => {
      unfollow()
      cancelAnimationFrame(frame)
      wakeRef.current = () => {}
      sizes.disconnect()
      document.removeEventListener('visibilitychange', wake)
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerdown', press)
      canvas.removeEventListener('webglcontextlost', lost)
      canvas.removeEventListener('webglcontextrestored', restored)
      if (program) gl.deleteProgram(program)
      if (buffer) gl.deleteBuffer(buffer)
    }
  }, [cover])

  return <canvas ref={canvasRef} aria-hidden="true" className="pointer-events-none fixed inset-0 size-full" />
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
