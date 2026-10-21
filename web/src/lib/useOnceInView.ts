import { useEffect, useRef, useState } from 'react'

/** Turns true the first time the element is on screen (and stays true). `amount` is how much of it has to show. */
export function useOnceInView<T extends Element>(amount = 0.35) {
  const ref = useRef<T>(null)
  const [seen, setSeen] = useState(false)

  useEffect(() => {
    const element = ref.current
    if (!element || seen) return
    const watcher = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return
        setSeen(true)
        watcher.disconnect()
      },
      { threshold: amount },
    )
    watcher.observe(element)
    return () => watcher.disconnect()
  }, [amount, seen])

  return [ref, seen] as const
}
