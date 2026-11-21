import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App.tsx'
import './index.css'

// Every visit starts at the splash, with its intro (a reload doesn't drop you halfway through the swirl).
if ('scrollRestoration' in history) history.scrollRestoration = 'manual'

// The built page already holds a plain copy of the page for search engines (scripts/prerender.mjs);
// this draws the live page over it.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
