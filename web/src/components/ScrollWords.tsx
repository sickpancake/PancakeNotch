import { useRef } from 'react'
import { m, useReducedMotion, useScroll, useTransform, type MotionValue } from 'motion/react'

/* One sentence between the live notch and the rest of the page. It comes up out of the dark left by
   the zoom into the notch's screen (see Journey). Its words are dark gray and light up one by one as
   the sentence scrolls up the screen: the first word lights as the sentence comes into view, the last
   when it's about halfway up. No extra scrolling, it just moves with the page.
   Reduce Motion: all the words are lit. It's plain text throughout, so screen readers read it as is. */

const SENTENCE = 'Your notch sits idle all day. Give it a job, like music, AI agents or AI usage, and it still barely touches your Mac.'
const WORDS = SENTENCE.split(' ')

export function ScrollWords() {
  const ref = useRef<HTMLParagraphElement>(null)
  const reduce = useReducedMotion() ?? false
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start 0.85', 'end 0.5'] })

  return (
    <section className="relative pt-[clamp(3rem,12svh,7rem)] pb-[clamp(6rem,22svh,12rem)]">
      <div className="mx-auto max-w-[86rem] px-(--page-gutter)">
        <p
          ref={ref}
          className="max-w-[18em] font-display text-[clamp(2rem,5.2vw,4.75rem)] leading-[1.08] font-bold tracking-[-0.035em] text-balance text-ink"
        >
          {WORDS.map((word, i) => (
            <span key={i}>
              <Word progress={scrollYProgress} from={i / WORDS.length} to={(i + 1) / WORDS.length} lit={reduce}>
                {word}
              </Word>
              {i < WORDS.length - 1 && ' '}
            </span>
          ))}
        </p>
      </div>
    </section>
  )
}

type WordProps = { progress: MotionValue<number>; from: number; to: number; lit: boolean; children: string }

/** One word: dim until the sentence's progress reaches its turn, then lit. */
function Word({ progress, from, to, lit, children }: WordProps) {
  // Each word fades over a slice a bit longer than its own, so neighbours overlap and it reads as a sweep.
  const opacity = useTransform(progress, [from, Math.min(1, to + 0.08)], [0.17, 1])
  return <m.span style={lit ? undefined : { opacity }}>{children}</m.span>
}
