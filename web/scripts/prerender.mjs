// Writes the home page's words into dist/index.html, so search engines and link previews can read
// them without running the page's code. The page in the browser is unchanged: main.tsx draws it fresh
// over this copy. Runs after `vite build` and `vite build --ssr` (see package.json).
import { readFile, rm, writeFile } from 'node:fs/promises'

// The few browser features the page touches while it's being drawn. Only the first frame is written
// out, so stand-ins are enough: no touch screen, and ids written as they are.
globalThis.matchMedia ??= () => ({ matches: false, addEventListener() {}, removeEventListener() {} })
globalThis.CSS ??= { escape: (text) => String(text).replace(/[^\w-]/g, (c) => `\\${c}`) }

const page = new URL('../dist/index.html', import.meta.url)
const server = new URL('../dist-ssr/', import.meta.url)
const { render } = await import(new URL('entry-server.js', server).href)

const html = await readFile(page, 'utf8')
const empty = '<div id="root"></div>'
if (!html.includes(empty)) throw new Error(`dist/index.html has no ${empty} to fill`)
await writeFile(page, html.replace(empty, `<div id="root">${render()}</div>`))
await rm(server, { recursive: true, force: true })
console.log('Home page words written into dist/index.html')
