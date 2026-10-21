import { useId, type ReactNode } from 'react'
import { cn } from '@/lib/utils'
import type { Item } from './data'

/* The notch's pictures: icons drawn on a 24 × 24 grid, the made-up album covers of the practice
   player, and the Shelf's previews. All of it is drawn here, so nothing is downloaded. */

const ICONS = {
  play: <path fill="currentColor" stroke="none" d="M7.5 5.6v12.8c0 .9 1 1.5 1.8 1l10.4-6.4c.7-.4.7-1.5 0-2L9.3 4.6c-.8-.5-1.8.1-1.8 1Z" />,
  pause: (
    <g fill="currentColor" stroke="none">
      <rect x="6" y="4.5" width="4.4" height="15" rx="1.3" />
      <rect x="13.6" y="4.5" width="4.4" height="15" rx="1.3" />
    </g>
  ),
  back: <path fill="currentColor" stroke="none" d="M11.4 6.7v10.6c0 .8-.9 1.2-1.5.8l-7.1-5.3a1 1 0 0 1 0-1.6l7.1-5.3c.6-.4 1.5 0 1.5.8Zm10 0v10.6c0 .8-.9 1.2-1.5.8l-7.1-5.3a1 1 0 0 1 0-1.6l7.1-5.3c.6-.4 1.5 0 1.5.8Z" />,
  forward: <path fill="currentColor" stroke="none" d="M12.6 6.7v10.6c0 .8.9 1.2 1.5.8l7.1-5.3a1 1 0 0 0 0-1.6l-7.1-5.3c-.6-.4-1.5 0-1.5.8Zm-10 0v10.6c0 .8.9 1.2 1.5.8l7.1-5.3a1 1 0 0 0 0-1.6L4.1 5.9c-.6-.4-1.5 0-1.5.8Z" />,
  shuffle: <path d="M3.5 7.5h3c2.2 0 3.4 1.1 4.6 3l1.8 3c1.2 1.9 2.4 3 4.6 3h3M3.5 16.5h3c1.4 0 2.4-.4 3.2-1.2M14.3 8.7c.8-.8 1.8-1.2 3.2-1.2h3M18 5l2.5 2.5L18 10M18 14l2.5 2.5L18 19" />,
  repeat: <path d="M4 11V9.5a3 3 0 0 1 3-3h13M17 3.5l3 3-3 3M20 13v1.5a3 3 0 0 1-3 3H4M7 20.5l-3-3 3-3" />,
  grid: (
    <>
      <rect x="4" y="4" width="6.5" height="6.5" rx="1.8" />
      <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.8" />
      <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.8" />
      <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.8" />
    </>
  ),
  note: (
    <>
      <path d="M11.2 17.3V4.4c0-.6.6-1 1.2-.8l4.4 1.6c.5.2.8.6.8 1.1v1.6l-6.4-2.2" />
      <ellipse cx="7.9" cy="17.4" rx="3.3" ry="2.8" fill="currentColor" stroke="none" />
    </>
  ),
  tray: (
    <>
      <path d="M3.5 13.5 5.8 6.4A2 2 0 0 1 7.7 5h8.6a2 2 0 0 1 1.9 1.4l2.3 7.1V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z" />
      <path d="M3.5 13.5h4.3l1.3 2h5.8l1.3-2h4.3" />
    </>
  ),
  link: <path d="M10.3 13.7a3.8 3.8 0 0 0 5.4 0l3-3a3.8 3.8 0 1 0-5.4-5.4l-1.1 1.1M13.7 10.3a3.8 3.8 0 0 0-5.4 0l-3 3a3.8 3.8 0 1 0 5.4 5.4l1.1-1.1" />,
  text: <path d="M4 6h16M4 10.5h16M4 15h10M4 19.5h7" />,
  chevronLeft: <path d="M14.5 5.5 8 12l6.5 6.5" />,
  trash: <path d="M4.5 6.5h15M9.5 6.5V5a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v1.5M6.5 6.5l.9 12.1a1.5 1.5 0 0 0 1.5 1.4h6.2a1.5 1.5 0 0 0 1.5-1.4l.9-12.1M10.3 10.5V16M13.7 10.5V16" />,
  cursor: (
    <>
      <path d="m10 10 3.6 10.3 1.7-4.4 4.4-1.7Z" />
      <path d="M10 2.8v2.6M4.9 4.9l1.8 1.8M2.8 10h2.6M15.1 4.9l-1.8 1.8M4.9 15.1l1.8-1.8" />
    </>
  ),
  tap: (
    <>
      <circle cx="12" cy="12" r="3.2" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="7.5" />
    </>
  ),
  key: <path d="M5 7.5h14a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 15V9A1.5 1.5 0 0 1 5 7.5ZM7 12h.01M10.5 12h.01M14 12h.01M17 12h.01" />,
} satisfies Record<string, ReactNode>

export type IconName = keyof typeof ICONS

export function Icon({ name, className }: { name: IconName; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className={cn('size-[1em] flex-none fill-none stroke-current stroke-2 [stroke-linecap:round] [stroke-linejoin:round]', className)}
    >
      {ICONS[name]}
    </svg>
  )
}

/** One of the three made-up album covers. */
export function Cover({ song, className }: { song: number; className?: string }) {
  const id = useId()
  const fill = `url(#${CSS.escape(id)})`
  return (
    <svg viewBox="0 0 100 100" aria-hidden="true" className={cn('block size-full', className)}>
      {song === 0 && (
        <>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="75" gradientUnits="userSpaceOnUse">
            <stop offset="0" stopColor="#ff8c5c" />
            <stop offset=".5" stopColor="#fac77a" />
            <stop offset="1" stopColor="#ffebbf" />
          </linearGradient>
          <rect width="100" height="100" fill={fill} />
          <circle cx="50" cy="44" r="22" fill="#fff7e0" fillOpacity=".95" />
          <ellipse cx="50" cy="104" rx="80" ry="50" fill="#d98550" />
          <ellipse cx="50" cy="116" rx="80" ry="50" fill="#d96b4d" />
          <ellipse cx="50" cy="128" rx="80" ry="50" fill="#d9524d" />
        </>
      )}
      {song === 1 && (
        <>
          <linearGradient id={id} x1="0" y1="100" x2="100" y2="0" gradientUnits="userSpaceOnUse">
            <stop offset="0" stopColor="#4d2914" />
            <stop offset="1" stopColor="#8c4d1a" />
          </linearGradient>
          <rect width="100" height="100" fill={fill} />
          <g transform="translate(62 58)">
            {['#ff7333', '#ff823b', '#ff9142', '#ffa14a', '#ffb052', '#ffbf59', '#ffcf61', '#ffde69', '#ffed70'].map((color, i) => (
              <circle key={color} r={81 - 9 * i} fill={color} fillOpacity={i % 2 ? 0.9 : 0.75} />
            ))}
          </g>
        </>
      )}
      {song === 2 && (
        <>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
            <stop offset="0" stopColor="#0f1240" />
            <stop offset="1" stopColor="#472973" />
          </linearGradient>
          <rect width="100" height="100" fill={fill} />
          <circle cx="66" cy="30" r="14" fill="#f7f2d9" />
          <circle cx="73" cy="27" r="13" fill="#211a54" />
          <g fill="#fff" fillOpacity=".85">
            <circle cx="15" cy="20" r="1.6" />
            <circle cx="32" cy="34" r="1.2" />
            <circle cx="22" cy="52" r="1" />
            <circle cx="42" cy="14" r="1" />
            <circle cx="85" cy="70" r="1.2" />
            <circle cx="12" cy="75" r=".8" />
          </g>
          <rect y="84" width="100" height="16" fill="#0d0d29" fillOpacity=".9" />
        </>
      )}
    </svg>
  )
}

/** A Shelf item's picture: a page, a photo, a note or a link. `large` is the open item's preview. */
export function Thumb({ item, large = false }: { item: Item; large?: boolean }) {
  const id = useId()
  if (item.kind === 'text') {
    return (
      <span className="relative block size-14 overflow-hidden rounded-[9px] bg-[#1c1c1c] p-1.5 text-left text-[9px] leading-[1.2] font-semibold [overflow-wrap:anywhere] text-white/85">
        {item.text.slice(0, 60)}
        <Icon name="text" className="absolute right-[5px] bottom-[5px] text-[10px] text-white/50" />
      </span>
    )
  }
  if (item.kind === 'link') {
    return (
      <span className={cn('grid place-items-center bg-[#1c1c1c]', large ? 'size-24 rounded-2xl text-4xl' : 'size-14 rounded-[9px] text-[22px]')}>
        <Icon name="link" />
      </span>
    )
  }
  if (item.thumb === 'photo') {
    return (
      <svg viewBox="0 0 60 40" preserveAspectRatio="xMidYMid slice" aria-hidden="true" className={large ? 'h-[100px] w-[150px] rounded-lg' : 'h-[38px] w-14 rounded-[3px]'}>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="26" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#d4d4d4" />
          <stop offset="1" stopColor="#f6f6f6" />
        </linearGradient>
        <rect width="60" height="40" fill={`url(#${CSS.escape(id)})`} />
        <circle cx="43.1" cy="11.7" r="3.5" fill="#fbfbfb" />
        <path fill="#bdbdbd" d="M0 40V20.4c10-4 20-4 30 0s20 4 30 0V40Z" />
        <path fill="#949494" d="M0 40V23.2c10-1 20 9 30 4.8s20-5 30-4.8V40Z" />
        <path fill="#666" d="M0 40v-8.5c10 3 20 3 30 0s20-3 30 0V40Z" />
      </svg>
    )
  }
  return (
    <svg viewBox="0 0 42 56" aria-hidden="true" className={large ? 'h-[106px] w-20' : 'h-14 w-[42px]'}>
      <rect width="42" height="56" rx="2" fill="#fff" />
      <rect x="6" y="7" width="15" height="2.2" fill="#222" />
      <g fill="#a3a3a3">
        {[13, 16.5, 20, 23.5, 27, 33, 36.5].map((y, i) => (
          <rect key={y} x="6" y={y} width={[30, 30, 26, 30, 18, 30, 24][i]} height="1.3" />
        ))}
      </g>
    </svg>
  )
}
