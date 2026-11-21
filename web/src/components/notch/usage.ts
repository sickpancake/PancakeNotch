import { useReducer } from 'react'
import type { AccountId, Range, Selection } from './data'

/* The practice AI Usage: which account and range are showing, whether the account menu is open and
   which emails have been uncovered. The numbers are fixed (see data.ts), so nothing here is timed. */

export type Usage = {
  account: Selection
  range: Range
  menu: boolean
  shown: AccountId[] // emails clicked open; they cover themselves again when the menu closes
}

type Action =
  | { type: 'menu' }
  | { type: 'close' }
  | { type: 'choose'; account: Selection }
  | { type: 'range'; range: Range }
  | { type: 'email'; id: AccountId }

const START: Usage = { account: 'personal', range: 'today', menu: false, shown: [] }

function reduce(s: Usage, a: Action): Usage {
  switch (a.type) {
    case 'menu':
      return { ...s, menu: !s.menu, shown: [] }
    case 'close':
      return s.menu || s.shown.length ? { ...s, menu: false, shown: [] } : s
    case 'choose':
      return { ...s, account: a.account, menu: false, shown: [] }
    case 'range':
      return { ...s, range: a.range }
    case 'email':
      return { ...s, shown: s.shown.includes(a.id) ? s.shown.filter((id) => id !== a.id) : [...s.shown, a.id] }
  }
}

export function useUsage() {
  const [usage, dispatch] = useReducer(reduce, START)
  const actions = {
    toggleMenu: () => dispatch({ type: 'menu' }),
    close: () => dispatch({ type: 'close' }),
    choose: (account: Selection) => dispatch({ type: 'choose', account }),
    setRange: (range: Range) => dispatch({ type: 'range', range }),
    toggleEmail: (id: AccountId) => dispatch({ type: 'email', id }),
  }
  return [usage, actions] as const
}
