import { renderToString } from 'react-dom/server'
import { App } from './App.tsx'

// Used only at build time: turns the home page into plain HTML, so search engines can read its words
// without running the page's code (scripts/prerender.mjs puts it into dist/index.html).
export function render() {
  return renderToString(<App />)
}
