import { useEffect, useRef } from 'react'

/* A grid of faint gray square dots with wisps of light blowing through it to the right, like air,
   behind the notch section (our own take on React Bits Pro's "Chroma Current", in grays). Moving the
   pointer stirs the air: each bit of its path becomes a small gust that the wind carries off and that
   dies away within a second, so nothing stays disturbed once the pointer stops. A click or tap away
   from the controls lets out a puff of light that the wind carries off too.

   Drawn by the graphics card in two passes: first one value per dot (how lit it is) into a tiny
   texture, then the dots themselves, square and sharp at the screen's own resolution. It only moves
   while `active`, on screen and in a visible tab; with Reduce Motion it holds still. */

const PITCH = 11 // CSS pixels from one dot to the next
const DOT = 0.44 // square dot size as a share of the pitch, before the lit ones swell
const BASE = 0.05 // how much an unlit dot shows
const LIT = 0.24 // how much more a fully lit one shows: kept dim, it's a backdrop
const PLUMES = 4
const GUSTS = 24 // bits of the pointer's recent path that still stir the air
const GUST_LIFE = 1.1 // seconds before one has died away completely

const VERTEX = `#version 300 es
layout(location = 0) in vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
`

// Pass 1: one pixel per dot, how lit it is.
const FIELD = `#version 300 es
precision highp float;

uniform float u_time;
uniform float u_pitch;      // CSS pixels between dots
uniform float u_height;     // of the whole grid, in CSS pixels
uniform vec4 u_gusts[${GUSTS}];   // x, y (CSS pixels from the bottom left), and the pointer's speed there (px a second)
uniform float u_gustAges[${GUSTS}]; // seconds since each was stirred (negative = unused)
uniform vec4 u_plumes[${PLUMES}]; // x, y, age in seconds, strength (0 = none)
uniform float u_intro;      // 0 to 1 as the currents first fade in

const float WIND = 150.0; // CSS pixels a second, to the right

out vec4 fragColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
  float sum = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 3; i++) { sum += amp * noise(p); p *= 2.03; amp *= 0.5; }
  return sum;
}

void main() {
  vec2 p = (floor(gl_FragCoord.xy) + 0.5) * u_pitch;
  float t = u_time;

  // Where the pointer has been stirs the air: each bit of its path is a gust that pushes the way the
  // pointer was going, rides downwind and spreads and fades. It leaves nothing behind, because
  // it only moves what we sample, and the gust itself is soon gone.
  vec2 stir = vec2(0.0);
  for (int i = 0; i < ${GUSTS}; i++) {
    float age = u_gustAges[i];
    if (age < 0.0) continue;
    vec4 gust = u_gusts[i];
    float r = 70.0 + age * 140.0;
    vec2 e = p - gust.xy - vec2(WIND * 1.1 * age, 0.0);
    float fade = 1.0 - smoothstep(0.0, ${GUST_LIFE.toFixed(2)}, age);
    stir += gust.zw * 0.16 * exp(-dot(e, e) / (r * r)) * fade * fade;
  }
  vec2 q = p - clamp(stir, vec2(-170.0), vec2(170.0));

  // The wind blows to the right, in gusts: a steady rush that now and then picks up and eases off.
  float rush = t * WIND + 110.0 * sin(t * 0.33) + 40.0 * sin(t * 0.9 + 1.3);
  // Air is stretched out along the way it blows: long, thin wisps.
  vec2 stretch = vec2(0.0014, 0.0085);

  // A slow, larger swirl bends the wisps up and down, so they curl like smoke rather than slide.
  // It travels slower than the wisps, so they keep changing shape as they pass through it.
  vec2 warp = vec2(
    fbm((q - vec2(rush * 0.5, 0.0)) * stretch * 0.6 + vec2(0.0, t * 0.05)),
    fbm((q - vec2(rush * 0.5, 0.0)) * stretch * 0.6 + vec2(4.7, 1.9 - t * 0.04))
  ) - 0.5;

  // Layers at different heights in the air move at different speeds, which is what makes it
  // read as air: broad slow wisps, quicker finer ones, and a thin fast haze on top.
  float broad = fbm((q - vec2(rush, 0.0)) * stretch + warp * 1.6 + vec2(0.0, t * 0.03));
  float fine = fbm((q - vec2(rush * 1.8, 0.0)) * stretch * vec2(1.7, 2.4) + warp * 1.0 + vec2(7.3, -t * 0.05));
  float haze = fbm((q - vec2(rush * 2.7, 0.0)) * stretch * vec2(2.6, 3.4) + warp * 0.6 + vec2(2.1, t * 0.04));
  float lit = smoothstep(0.38, 0.76, broad * 0.62 + fine * 0.34 + haze * 0.22);

  // Puffs of light from clicks spread out, ride the wind and fade.
  for (int i = 0; i < ${PLUMES}; i++) {
    vec4 plume = u_plumes[i];
    if (plume.w <= 0.0) continue;
    float r = 50.0 + plume.z * 150.0;
    vec2 e = p - plume.xy - vec2(plume.z * WIND * 1.1, 0.0);
    lit += plume.w * exp(-dot(e / vec2(1.4, 1.0), e / vec2(1.4, 1.0)) / (r * r)) * exp(-plume.z * 1.1);
  }

  fragColor = vec4(clamp(lit, 0.0, 1.0) * u_intro, 0.0, 0.0, 1.0);
}
`

// Pass 2: the dots, at full resolution.
const DOTS = `#version 300 es
precision highp float;

uniform sampler2D u_field;
uniform float u_pitch; // device pixels between dots

out vec4 fragColor;

void main() {
  vec2 cell = floor(gl_FragCoord.xy / u_pitch);
  float lit = texelFetch(u_field, ivec2(cell), 0).r;
  float r = u_pitch * 0.5 * ${DOT.toFixed(2)} * (0.75 + 0.55 * lit); // lit dots swell a little
  vec2 off = abs(gl_FragCoord.xy - (cell + 0.5) * u_pitch);
  float edge = max(off.x, off.y); // square dots
  float shape = 1.0 - smoothstep(r - 0.5, r + 0.5, edge);
  float v = shape * (${BASE.toFixed(2)} + ${LIT.toFixed(2)} * lit);
  fragColor = vec4(vec3(v), v); // gray, see-through
}
`

type Props = {
  /** Moving (and listening to the pointer) only while true. */
  active: boolean
  className?: string
}

export function CurrentGrid({ active, className }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const activeRef = useRef(active)
  const playRef = useRef<() => void>(() => {})

  useEffect(() => {
    activeRef.current = active
    playRef.current()
  }, [active])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const gl = canvas.getContext('webgl2', { antialias: false, premultipliedAlpha: true, powerPreference: 'low-power' })
    if (!gl) return // No WebGL 2: a plain black backdrop.

    const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)')
    let field: Program | null = null
    let dots: Program | null = null
    let buffer: WebGLBuffer | null = null
    let texture: WebGLTexture | null = null
    let framebuffer: WebGLFramebuffer | null = null
    let width = 0 // CSS pixels
    let height = 0
    let scale = 1 // device pixels per CSS pixel
    let cols = 0
    let rows = 0
    let frame = 0
    let last = 0
    let elapsed = 8 // seconds of motion so far; a still frame shows this moment
    let intro = 0
    let onScreen = true
    const pointer = { x: 0, y: 0, at: -9999, vx: 0, vy: 0 } // where it was at the last move, and its speed
    const gusted = { x: 0, y: 0 } // where the last gust was left
    const gusts: { x: number; y: number; vx: number; vy: number; age: number }[] = [] // newest first
    const plumes: { x: number; y: number; age: number }[] = []

    const setUp = () => {
      field = link(gl, FIELD, ['time', 'pitch', 'height', 'gusts', 'gustAges', 'plumes', 'intro'])
      dots = link(gl, DOTS, ['field', 'pitch'])
      buffer = gl.createBuffer()
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
      gl.enableVertexAttribArray(0)
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
      texture = gl.createTexture()
      framebuffer = gl.createFramebuffer()
      sizeField()
    }

    const sizeField = () => {
      if (!texture || !framebuffer) return
      gl.bindTexture(gl.TEXTURE_2D, texture)
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, Math.max(cols, 1), Math.max(rows, 1), 0, gl.RGBA, gl.UNSIGNED_BYTE, null)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
      gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer)
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0)
      gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    }

    const draw = () => {
      if (!field || !dots || gl.isContextLost()) return
      gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer)
      gl.viewport(0, 0, cols, rows)
      gl.useProgram(field.program)
      const u = field.uniforms
      gl.uniform1f(u.time, elapsed)
      gl.uniform1f(u.pitch, PITCH)
      gl.uniform1f(u.height, height)
      const stirred = new Float32Array(GUSTS * 4)
      const ages = new Float32Array(GUSTS).fill(-1)
      gusts.forEach((gust, i) => {
        stirred.set([gust.x, height - gust.y, gust.vx, -gust.vy], i * 4)
        ages[i] = gust.age
      })
      gl.uniform4fv(u.gusts, stirred)
      gl.uniform1fv(u.gustAges, ages)
      const data = new Float32Array(PLUMES * 4)
      plumes.forEach((plume, i) => data.set([plume.x, height - plume.y, plume.age, 1.4], i * 4))
      gl.uniform4fv(u.plumes, data)
      gl.uniform1f(u.intro, reduceMotion.matches ? 1 : intro)
      gl.drawArrays(gl.TRIANGLES, 0, 3)

      gl.bindFramebuffer(gl.FRAMEBUFFER, null)
      gl.viewport(0, 0, canvas.width, canvas.height)
      gl.useProgram(dots.program)
      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, texture)
      gl.uniform1i(dots.uniforms.field, 0)
      gl.uniform1f(dots.uniforms.pitch, PITCH * scale)
      gl.clearColor(0, 0, 0, 0)
      gl.clear(gl.COLOR_BUFFER_BIT)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
    }

    const tick = (now: number) => {
      frame = 0
      if (!field) return
      // 60 frames a second at most, even on 120 Hz screens.
      if (last && now - last < 1000 / 61) {
        frame = requestAnimationFrame(tick)
        return
      }
      const dt = last ? Math.min(now - last, 100) / 1000 : 0
      last = now
      elapsed += dt
      intro = Math.min(intro + dt / 1.6, 1)
      for (const gust of gusts) gust.age += dt
      while (gusts.length && gusts[gusts.length - 1].age > GUST_LIFE) gusts.pop()
      for (const plume of plumes) plume.age += dt
      while (plumes.length && plumes[0].age > 4) plumes.shift()
      draw()
      frame = requestAnimationFrame(tick)
    }

    const play = () => {
      const moving = !!field && activeRef.current && onScreen && !document.hidden && !reduceMotion.matches
      if (moving && !frame) {
        last = 0
        frame = requestAnimationFrame(tick)
      } else if (!moving && frame) {
        cancelAnimationFrame(frame)
        frame = 0
      }
      if (!activeRef.current) intro = 0 // fade in again on the next arrival
    }
    playRef.current = play

    const resize = () => {
      const box = canvas.parentElement
      if (!box) return
      width = box.clientWidth
      height = box.clientHeight
      scale = Math.min(Math.round(devicePixelRatio || 1), 2)
      canvas.width = Math.max(1, width * scale)
      canvas.height = Math.max(1, height * scale)
      canvas.style.width = `${width}px`
      canvas.style.height = `${height}px`
      cols = Math.ceil(width / PITCH) + 1
      rows = Math.ceil(height / PITCH) + 1
      sizeField()
      draw()
    }

    const local = (event: PointerEvent) => {
      const box = canvas.getBoundingClientRect()
      return { x: event.clientX - box.left, y: event.clientY - box.top }
    }
    const move = (event: PointerEvent) => {
      if (!activeRef.current) return
      const at = local(event)
      const dt = (event.timeStamp - pointer.at) / 1000
      if (dt > 0.001 && dt < 0.2) {
        // How fast it's going, smoothed a little because pointer events come in uneven steps.
        pointer.vx = clamp(0.5 * pointer.vx + (0.5 * (at.x - pointer.x)) / dt, 1100)
        pointer.vy = clamp(0.5 * pointer.vy + (0.5 * (at.y - pointer.y)) / dt, 1100)
        // A new gust every few pixels along the way, so a quick flick leaves a continuous trail.
        if (Math.hypot(at.x - gusted.x, at.y - gusted.y) > 6) {
          gusts.unshift({ x: at.x, y: at.y, vx: pointer.vx, vy: pointer.vy, age: 0 })
          if (gusts.length > GUSTS) gusts.pop()
          gusted.x = at.x
          gusted.y = at.y
        }
      } else {
        // First move, or the pointer was still for a while: no speed to go on yet.
        pointer.vx = pointer.vy = 0
        gusted.x = at.x
        gusted.y = at.y
      }
      pointer.x = at.x
      pointer.y = at.y
      pointer.at = event.timeStamp
    }
    const press = (event: PointerEvent) => {
      if (!activeRef.current || reduceMotion.matches) return
      // Not when using the notch or another control.
      if ((event.target as Element | null)?.closest('button, a, input, [data-ui]')) return
      const at = local(event)
      plumes.push({ ...at, age: 0 })
      if (plumes.length > PLUMES) plumes.shift()
    }

    setUp()
    resize()

    const sizes = new ResizeObserver(resize)
    if (canvas.parentElement) sizes.observe(canvas.parentElement)
    const visibility = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting
      play()
    })
    visibility.observe(canvas)
    document.addEventListener('visibilitychange', play)
    reduceMotion.addEventListener('change', play)
    window.addEventListener('pointermove', move, { passive: true })
    window.addEventListener('pointerdown', press, { passive: true })

    const lost = (event: Event) => {
      event.preventDefault()
      cancelAnimationFrame(frame)
      frame = 0
      field = dots = null
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
      playRef.current = () => {}
      sizes.disconnect()
      visibility.disconnect()
      document.removeEventListener('visibilitychange', play)
      reduceMotion.removeEventListener('change', play)
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerdown', press)
      canvas.removeEventListener('webglcontextlost', lost)
      canvas.removeEventListener('webglcontextrestored', restored)
      if (field) gl.deleteProgram(field.program)
      if (dots) gl.deleteProgram(dots.program)
      if (buffer) gl.deleteBuffer(buffer)
      if (texture) gl.deleteTexture(texture)
      if (framebuffer) gl.deleteFramebuffer(framebuffer)
    }
  }, [])

  return (
    <div className={className} aria-hidden="true">
      <canvas ref={canvasRef} className="absolute top-0 left-0" />
    </div>
  )
}

const clamp = (value: number, limit: number) => Math.max(-limit, Math.min(limit, value))

type Program = { program: WebGLProgram; uniforms: Record<string, WebGLUniformLocation | null> }

function link(gl: WebGL2RenderingContext, fragmentSource: string, names: string[]): Program | null {
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
  const fragment = compile(gl.FRAGMENT_SHADER, fragmentSource)
  if (!vertex || !fragment) return null
  const program = gl.createProgram()
  gl.attachShader(program, vertex)
  gl.attachShader(program, fragment)
  gl.linkProgram(program)
  gl.deleteShader(vertex)
  gl.deleteShader(fragment)
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error(gl.getProgramInfoLog(program))
    gl.deleteProgram(program)
    return null
  }
  const uniforms = Object.fromEntries(names.map((name) => [name, gl.getUniformLocation(program, `u_${name}`)]))
  return { program, uniforms }
}
