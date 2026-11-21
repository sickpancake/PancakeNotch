import { useEffect, useReducer, useSyncExternalStore } from 'react'
import { THREADS, type Thread } from './data'

/* The practice agents: made-up threads you can answer. Nothing moves by itself; Allow or Deny starts
   one timer (the work, then done), and it only counts down while the demo is in view and the tab is
   showing. */

export type Agents = {
  threads: Thread[]
  settling: { id: number; ms: number; step: string } | null // the answered thread, and when it finishes
}

type Action = { type: 'allow' | 'deny'; id: number } | { type: 'settle' } | { type: 'seen' } | { type: 'reset' }

const START: Agents = { threads: THREADS, settling: null }

const ANSWERS = {
  allow: { now: { state: 'working', step: 'Rebuilding from scratch', status: 'Working · now' }, ms: 4000, step: 'Finished the refactor' },
  deny: { now: { state: 'error', step: 'You said no to the delete', status: 'Denied' }, ms: 2200, step: 'Finished without the delete' },
} as const

const change = (threads: Thread[], id: number, patch: Partial<Thread>) =>
  threads.map((thread) => (thread.id === id ? { ...thread, ...patch } : thread))

function reduce(s: Agents, a: Action): Agents {
  switch (a.type) {
    case 'allow':
    case 'deny': {
      const { now, ms, step } = ANSWERS[a.type]
      return { threads: change(s.threads, a.id, now), settling: { id: a.id, ms, step } }
    }
    case 'settle':
      if (!s.settling) return s
      return { threads: change(s.threads, s.settling.id, { state: 'done', step: s.settling.step, status: 'Done · now', fresh: true }), settling: null }
    case 'seen':
      return { ...s, threads: s.threads.map((thread) => (thread.fresh ? { ...thread, fresh: false } : thread)) }
    case 'reset':
      return START
  }
}

/* Whether the tab is hidden, kept up to date. */
function onVisibility(onChange: () => void) {
  document.addEventListener('visibilitychange', onChange)
  return () => document.removeEventListener('visibilitychange', onChange)
}

export function useAgents(active: boolean) {
  const [agents, dispatch] = useReducer(reduce, START)
  const hidden = useSyncExternalStore(onVisibility, () => document.hidden, () => false)

  const { settling } = agents
  useEffect(() => {
    if (!active || hidden || !settling) return
    const timer = setTimeout(() => dispatch({ type: 'settle' }), settling.ms)
    return () => clearTimeout(timer)
  }, [active, hidden, settling])

  const actions = {
    allow: (id: number) => dispatch({ type: 'allow', id }),
    deny: (id: number) => dispatch({ type: 'deny', id }),
    seen: () => dispatch({ type: 'seen' }),
    reset: () => dispatch({ type: 'reset' }),
  }
  return [agents, actions] as const
}

export type AgentsActions = ReturnType<typeof useAgents>[1]
