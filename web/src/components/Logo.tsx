import { useId } from 'react'
import { cn } from '@/lib/utils'

/* The app's mark, the same artwork as on the current site and in the app: the notch pill, three drips
   of syrup and two pancakes. It's drawn in the text colour, so it follows whatever it sits in. */

export function Logo({ className }: { className?: string }) {
  const id = useId()
  const gap = `logo-gap-${id.replace(/:/g, '')}`
  return (
    <svg viewBox="0 0 18 18" aria-hidden="true" className={cn('size-[1em]', className)}>
      <defs>
        {/* The pancakes are cut away round the drips, so the syrup reads as running over them. */}
        <mask id={gap} maskUnits="userSpaceOnUse" x="0" y="0" width="18" height="18">
          <rect width="18" height="18" fill="#fff" />
          <g fill="#000" stroke="#000" strokeWidth="1.6">
            <rect x="4.6" y="5" width="1.7" height="5" rx=".85" />
            <rect x="7.6" y="5" width="1.7" height="6" rx=".85" />
            <rect x="10.6" y="5" width="1.7" height="4.4" rx=".85" />
          </g>
        </mask>
      </defs>
      <g fill="none" stroke="currentColor" strokeWidth="1.3" mask={`url(#${gap})`}>
        <rect x="1.65" y="8.55" width="14.7" height="2.6" rx="1.3" />
        <rect x="1.65" y="13.45" width="14.7" height="2.6" rx="1.3" />
      </g>
      <g fill="currentColor">
        <path fillRule="evenodd" d="M5 1.5h8a2.5 2.5 0 0 1 0 5H5a2.5 2.5 0 0 1 0-5ZM12.3 4a.9.9 0 1 0 1.8 0 .9.9 0 1 0-1.8 0Z" />
        <rect x="4.6" y="5" width="1.7" height="5" rx=".85" />
        <rect x="7.6" y="5" width="1.7" height="6" rx=".85" />
        <rect x="10.6" y="5" width="1.7" height="4.4" rx=".85" />
      </g>
    </svg>
  )
}
