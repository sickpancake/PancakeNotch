import { useEffect, useState } from 'react'
import { useReducedMotion } from 'motion/react'
import { cn } from '@/lib/utils'
import { useOnceInView } from '@/lib/useOnceInView'

/* A line of text that decodes itself: when it comes into view every letter starts out as a random
   symbol, and the letters lock into place one after another, left to right. Each unlocked symbol sits
   in the width of the letter it will become, so nothing shifts while it runs. Screen readers get the
   plain text from the start; with Reduce Motion the text is just there. */

const SYMBOLS = '01<>/\\|_-+=*#'
const SHUFFLE_MS = 55 // how often the unlocked symbols change

const randomSymbol = () => SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)]

type Props = {
  text: string
  /** Milliseconds between one letter locking in and the next. */
  pace?: number
  className?: string
  /** The look of the symbols that haven't locked in yet. */
  scrambledClassName?: string
}

export function ScrambleText({ text, pace = 20, className, scrambledClassName }: Props) {
  const reduce = useReducedMotion() ?? false
  const [ref, seen] = useOnceInView<HTMLSpanElement>(0.1)
  const letters = Array.from(text)
  const [locked, setLocked] = useState(0)
  const [symbols, setSymbols] = useState(() => letters.map(randomSymbol))

  useEffect(() => {
    if (!seen || reduce) return
    const began = performance.now()
    let frame = 0
    let shuffled = began
    const tick = (now: number) => {
      const count = Math.min(letters.length, Math.floor((now - began) / pace))
      setLocked(count)
      if (now - shuffled >= SHUFFLE_MS) {
        shuffled = now
        setSymbols(letters.map(randomSymbol))
      }
      if (count < letters.length) frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the letters follow `text`
  }, [seen, reduce, pace, text])

  const done = reduce ? letters.length : locked
  // Where each word starts among all the letters (a space counts as one).
  let start = 0
  const words = text.split(' ').map((word) => {
    const entry = { letters: Array.from(word), start }
    start += entry.letters.length + 1
    return entry
  })

  return (
    <span ref={ref} className={className}>
      <span className="sr-only">{text}</span>
      <span aria-hidden="true">
        {words.map((word, w) => (
          <span key={w}>
            {w > 0 && ' '}
            {/* Words stay whole, so a line only ever breaks between words. */}
            <span className="inline-block whitespace-nowrap">
              {word.letters.map((letter, i) => {
                const index = word.start + i
                if (index < done) return letter
                return (
                  <span key={i} className="relative inline-block">
                    <span className="invisible">{letter}</span>
                    <span className={cn('absolute inset-0 text-center', scrambledClassName)}>{symbols[index] ?? '#'}</span>
                  </span>
                )
              })}
            </span>
          </span>
        ))}
      </span>
    </span>
  )
}
