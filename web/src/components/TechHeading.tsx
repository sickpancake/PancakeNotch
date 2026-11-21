import { useLayoutEffect, useRef, useState } from 'react'
import OutlineText from './OutlineText'

/* "This notch has a job." as two lines drawn by OutlineText: the little squares fly in and build the
   letters when `play` turns true, and hovering a letter turns it into a dashed outline with a frame,
   its size and a few specks. Each line gets its own canvas that reaches beyond its box (so the frame
   has room) but ignores the pointer: only the boxes, which just touch, listen to it, so a letter is
   always under the pointer it's drawn for.
   Screen readers get the plain text. Sizes follow the heading's own font size. */

const LINES = ['This notch', 'has a job.']

type Props = {
  id: string
  /** Builds the letters when it turns true; nothing is drawn while it's false. */
  play: boolean
  /** Tailwind classes for the heading's font size and look. */
  className?: string
}

export function TechHeading({ id, play, className }: Props) {
  const headingRef = useRef<HTMLHeadingElement>(null)
  const [size, setSize] = useState(64)

  // The font size comes from CSS (it scales with the screen), the canvas needs it in pixels.
  useLayoutEffect(() => {
    const heading = headingRef.current
    if (!heading) return
    const measure = () => setSize(parseFloat(getComputedStyle(heading).fontSize) || 64)
    measure()
    addEventListener('resize', measure)
    return () => removeEventListener('resize', measure)
  }, [])

  return (
    <h2 ref={headingRef} id={id} className={className}>
      <span className="sr-only">{LINES.join(' ')}</span>
      <span aria-hidden="true" className="block">
        {LINES.map((line) => (
          <span key={line} className="relative block h-[.98em]">
            {play && (
              <OutlineText
                text={line}
                fontSize={size}
                fontWeight={700}
                letterSpacing={-0.04}
                build={1.8}
                className="absolute inset-0"
                canvasClassName="pointer-events-none absolute -top-[.55em] -left-7 h-[calc(100%+1.1em)] w-[calc(100%+3.5rem)]"
              />
            )}
          </span>
        ))}
      </span>
    </h2>
  )
}
