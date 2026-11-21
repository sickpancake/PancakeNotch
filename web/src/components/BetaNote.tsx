/* A small, quiet note before the download: PancakeNotch is still in beta, so there may be bugs, and
   where to tell us about one. One line, no animation. */

const REPORT = `${import.meta.env.BASE_URL}help/#report` // the Help page's "Report a problem" steps

export function BetaNote() {
  return (
    <section aria-label="Beta" className="relative pb-[clamp(3rem,8svh,5rem)]">
      <div className="mx-auto max-w-[86rem] px-(--page-gutter)">
        <p className="flex flex-wrap items-center gap-x-3 gap-y-2 text-[.9375rem] leading-snug text-soft">
          <span className="rounded-full px-2.5 py-1 text-xs leading-none font-semibold text-ink ring-1 ring-white/20">Beta</span>
          <span>
            PancakeNotch is still being tested, so you might run into bugs.{' '}
            <a
              href={REPORT}
              className="text-ink underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
            >
              Found one? Tell us.
            </a>
          </span>
        </p>
      </div>
    </section>
  )
}
