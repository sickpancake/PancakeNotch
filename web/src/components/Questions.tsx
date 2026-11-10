import type { ReactNode } from 'react'

/* The questions people ask before they download, each answered in a sentence or two, with a link to
   the Help page where there's more. Laid out like the rest of the page: the same heading, the card
   titles' type for the questions and the cards' gray for the answers, with a thin line above each.
   No animation, and everything is open: nothing to click to read it. */

const REPO = 'https://github.com/sickpancake/PancakeNotch'
const HELP = `${import.meta.env.BASE_URL}help/`

function More({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      className="text-ink underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
    >
      {children}
    </a>
  )
}

const QUESTIONS: { question: string; answer: ReactNode }[] = [
  {
    question: 'Is it really free?',
    answer: (
      <>
        Yes: no price, no paid tier, no account and no ads. It’s open source under GPL-3.0, so it has to stay
        free. <More href={REPO}>The code is on GitHub.</More>
      </>
    ),
  },
  {
    question: 'Which Macs does it run on?',
    answer:
      'MacBooks with a notch, on macOS 15 or later: the 14″ and 16″ MacBook Pro from M1 Pro on, and the MacBook Air from M2 on. It lives on the built-in screen.',
  },
  {
    question: 'Is it like the iPhone’s Dynamic Island?',
    answer:
      'Close. The closed notch stays plain black until something’s going on. Then the song, a running timer or an agent that needs you shows beside it. Hover or click the notch to open it into a small panel.',
  },
  {
    question: 'Which AI tools does it work with?',
    answer: (
      <>
        Agents follows Claude Code and Codex with no setup, and Cursor once you connect it. Connect Claude Code or
        Codex too, and you can Allow or Deny their requests from the notch. AI Usage shows how much of your Claude
        and Codex limits is left. <More href={`${HELP}#agents`}>How Agents works</More>
      </>
    ),
  },
  {
    question: 'Why does macOS warn me the first time?',
    answer: (
      <>
        PancakeNotch isn’t notarized by Apple, because that needs a paid developer account. You confirm it once in
        System Settings, and updates don’t need it again. <More href={`${HELP}#first-launch`}>The steps</More>
      </>
    ),
  },
  {
    question: 'Does it collect anything?',
    answer: (
      <>
        No analytics, no tracking and no account. Your history stays on your Mac, and the once-a-day update check
        can be switched off. <More href={`${HELP}#privacy`}>Privacy, in full</More>
      </>
    ),
  },
]

export function Questions() {
  return (
    <section aria-labelledby="questions-title" className="relative py-[clamp(4rem,12svh,8rem)]">
      <div className="mx-auto max-w-[86rem] px-(--page-gutter)">
        <h2
          id="questions-title"
          className="font-display text-[clamp(2rem,4.2vw,3.75rem)] leading-none font-bold tracking-[-0.035em] text-ink"
        >
          Questions.
        </h2>
        <ul className="mt-[clamp(2rem,6svh,3.5rem)] grid gap-x-[clamp(2.5rem,5vw,5.5rem)] md:grid-cols-2">
          {QUESTIONS.map(({ question, answer }) => (
            <li key={question} className="border-t border-white/10 pt-5 pb-8">
              <h3 className="text-lg font-semibold tracking-[-0.01em] text-ink">{question}</h3>
              <p className="mt-1.5 max-w-[36rem] text-[15px] leading-snug text-soft">{answer}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
