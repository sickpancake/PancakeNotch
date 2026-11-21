import { useEffect, useRef, useState } from 'react'
import { m, useMotionTemplate, useReducedMotion, useScroll, useTransform } from 'motion/react'

/* The end of the page: a dark middle with a big soft glow rising around its edge, in grays from black
   to near-white, high on the screen and slowly breathing. "PancakeNotch" sits over the glow, white at
   the top of its letters and melting into the lighter gray toward the bottom. As the footer scrolls in, the glow comes up out
   of the dark and the name rises and sharpens. The glow only breathes while it's on screen, and not
   at all with Reduce Motion. */

const REPO = 'https://github.com/sickpancake/PancakeNotch'
const DOWNLOAD = `${REPO}/releases/latest/download/PancakeNotch.zip`
const HELP = `${import.meta.env.BASE_URL}help/` // the Help page, which sits next to this one on the site

const LINKS = [
  { label: 'GitHub', href: REPO },
  { label: 'Releases', href: `${REPO}/releases` },
  { label: 'Help', href: HELP },
  { label: 'GPL-3.0', href: `${REPO}/blob/main/LICENSE` },
]

export function Footer() {
  const ref = useRef<HTMLElement>(null)
  const reduce = useReducedMotion() ?? false
  const [onScreen, setOnScreen] = useState(false)
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'start 0.2'] })
  const glow = useTransform(scrollYProgress, [0, 0.7], [0, 1])
  const nameOpacity = useTransform(scrollYProgress, [0.2, 0.85], [0, 1])
  const nameY = useTransform(scrollYProgress, [0.2, 1], [reduce ? 0 : 90, 0])
  const nameBlur = useTransform(scrollYProgress, [0.2, 0.85], [reduce ? 0 : 14, 0])
  const nameFilter = useMotionTemplate`blur(${nameBlur}px)`

  useEffect(() => {
    const footer = ref.current
    if (!footer) return
    const watcher = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting))
    watcher.observe(footer)
    return () => watcher.disconnect()
  }, [])

  return (
    <footer ref={ref} className="relative min-h-svh overflow-hidden">
      {/* The dark and the glow. Its top edge fades out, so it doesn't start with a hard line over the page. */}
      <m.div
        aria-hidden="true"
        style={{ opacity: glow }}
        className="absolute inset-0 bg-[#0a0a0a] [mask-image:linear-gradient(to_bottom,transparent,#000_16%)]" // taste-skill-ignore: a mask, not a visible gradient
      >
        <div className="footer-glow absolute inset-0" data-paused={!onScreen || reduce} />
      </m.div>

      <div className="relative mx-auto flex min-h-svh max-w-[86rem] flex-col items-center px-(--page-gutter) pt-[clamp(5rem,17svh,10rem)] pb-6 text-center">
        <h2 className="font-display text-[clamp(1.75rem,3.4vw,3.25rem)] leading-[1.05] font-bold tracking-[-0.035em] text-ink">
          Give your notch a job.
        </h2>
        <a
          href={DOWNLOAD}
          className="mt-8 inline-flex h-12 items-center rounded-full bg-white px-7 text-[1.0625rem] font-semibold text-black transition-transform duration-200 hover:scale-[1.04] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white active:scale-[.98]"
        >
          Download for Mac
        </a>
        <p className="mt-4 text-[.9375rem] text-balance text-soft">Free and open source. macOS 15 or later, Apple Silicon.</p>
        <a
          href={`${HELP}#first-launch`}
          className="mt-2 text-[.9375rem] text-soft underline decoration-white/30 underline-offset-4 transition-colors hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
        >
          macOS shows a warning the first time? Here&rsquo;s why.
        </a>

        <m.p
          style={{ opacity: nameOpacity, y: nameY, filter: nameFilter }}
          className="mt-auto pb-[clamp(5rem,38svh,16rem)] md:pb-[clamp(5rem,26svh,16rem)] font-display text-[clamp(3rem,14vw,17rem)] leading-[.86] font-bold tracking-[-0.055em] whitespace-nowrap text-ink [mask-image:linear-gradient(to_bottom,#000_22%,transparent_92%)]" // taste-skill-ignore: a mask, not a visible gradient
        >
          PancakeNotch
        </m.p>

        <nav aria-label="Project links" className="flex gap-7 pb-2 text-[.9375rem] font-semibold text-[#0a0a0a]">
          {LINKS.map((link) => (
            <a
              key={link.label}
              href={link.href}
              className="underline-offset-4 hover:underline focus-visible:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#0a0a0a]"
            >
              {link.label}
            </a>
          ))}
        </nav>
      </div>
    </footer>
  )
}
