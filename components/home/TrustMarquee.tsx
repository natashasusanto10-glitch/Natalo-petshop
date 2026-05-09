"use client";

import { Fragment } from "react";
import { trustItems as defaultItems, type TrustItem, type TrustItemIcon } from "@/data/trustItems";

export default function TrustMarquee({
  items = defaultItems,
  durationSec = 34,
}: {
  items?: TrustItem[];
  durationSec?: number;
}) {
  function renderItem(item: TrustItem, key: string) {
    const inner = (
      <>
        <TrustSvg name={item.icon} className={`h-3.5 w-3.5 ${item.iconClass}`} />
        <span className={item.href ? "underline decoration-dotted underline-offset-2" : ""}>
          {item.text}
        </span>
        {item.showLinkIcon && (
          <svg
            className="h-2.5 w-2.5 opacity-50 transition group-hover:opacity-100"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path strokeLinecap="round" strokeLinejoin="round" d="M14 5h5v5M19 5l-9 9M9 5H5v14h14v-4" />
          </svg>
        )}
      </>
    );

    if (item.href) {
      return (
        <a
          key={key}
          href={item.href}
          target={item.external ? "_blank" : undefined}
          rel={item.external ? "noopener noreferrer" : undefined}
          className="group flex items-center gap-1.5 rounded-full px-0.5 transition hover:text-natalo-800"
        >
          {inner}
        </a>
      );
    }

    return (
      <span key={key} className="flex items-center gap-1.5">
        {inner}
      </span>
    );
  }

  function renderGroup(prefix: string) {
    return (
      <div
        className={`marquee-group flex shrink-0 items-center gap-6 pr-6 ${prefix === "b" ? "marquee-duplicate" : ""}`}
        aria-hidden={prefix === "b"}
      >
        {items.map((item, index) => (
          <Fragment key={`${prefix}-${index}`}>
            {renderItem(item, `${prefix}-${index}`)}
            <span className="h-1 w-1 rounded-full bg-natalo-200" aria-hidden="true" />
          </Fragment>
        ))}
      </div>
    );
  }

  return (
    <div className="marquee-wrap overflow-hidden border-y border-natalo-100 bg-gradient-to-r from-natalo-50 via-white to-amber-50">
      <div
        className="marquee-track flex h-9 w-max items-center whitespace-nowrap text-[11px] font-semibold text-slate-700 sm:h-10 sm:text-xs"
        style={{ animationDuration: `${durationSec}s` }}
      >
        {renderGroup("a")}
        {renderGroup("b")}
      </div>

      <style jsx>{`
        @keyframes marquee-slide {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(-50%, 0, 0);
          }
        }
        .marquee-track {
          animation-name: marquee-slide;
          animation-timing-function: linear;
          animation-iteration-count: infinite;
          will-change: transform;
        }
        @media (prefers-reduced-motion: reduce) {
          .marquee-wrap {
            overflow: visible;
          }
          .marquee-track {
            animation: none;
            height: auto;
            width: 100%;
            flex-wrap: wrap;
            gap: 0.4rem 0;
            padding: 0.45rem 0.75rem;
            white-space: normal;
          }
          .marquee-group {
            flex-wrap: wrap;
            gap: 0.55rem 1rem;
            padding-right: 0;
          }
          .marquee-duplicate {
            display: none;
          }
        }
      `}</style>
    </div>
  );
}

function TrustSvg({ name, className }: { name: TrustItemIcon; className?: string }) {
  const paths: Record<TrustItemIcon, React.ReactNode> = {
    truck: (
      <>
        <path d="M3 7h11v9H3z" />
        <path d="M14 10h4l3 3v3h-7" />
        <circle cx="7" cy="18" r="2" />
        <circle cx="17" cy="18" r="2" />
      </>
    ),
    shield: <path d="M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.5 7-10V6l-7-3Z" />,
    chat: (
      <>
        <path d="M5 18.5V7c0-1.5 1.2-2.5 2.8-2.5h8.4C17.8 4.5 19 5.5 19 7v5c0 1.5-1.2 2.5-2.8 2.5H10l-5 4Z" />
        <path d="M9 9h6" />
        <path d="M9 12h4" />
      </>
    ),
    paw: (
      <>
        <path d="M8 20c-2 0-3-1.2-3-2.7 0-2.4 3.1-4.8 7-4.8s7 2.4 7 4.8c0 1.5-1 2.7-3 2.7-1.4 0-2.5-.8-4-.8s-2.6.8-4 .8Z" />
        <circle cx="6.5" cy="10" r="1.8" />
        <circle cx="10" cy="7" r="1.8" />
        <circle cx="14" cy="7" r="1.8" />
        <circle cx="17.5" cy="10" r="1.8" />
      </>
    ),
    gift: (
      <>
        <path d="M4 11h16v9H4z" />
        <path d="M3 7h18v4H3z" />
        <path d="M12 7v13" />
        <path d="M12 7c-1.2-2.4-4.5-3-5-1-.5 2 2.5 2 5 1Z" />
        <path d="M12 7c1.2-2.4 4.5-3 5-1 .5 2-2.5 2-5 1Z" />
      </>
    ),
    star: <path d="m12 3 2.7 5.5 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.8 1-6.1-4.4-4.3 6.1-.9L12 3Z" />,
    users: (
      <>
        <path d="M16 19c0-2.2-1.8-4-4-4s-4 1.8-4 4" />
        <circle cx="12" cy="9" r="3" />
        <path d="M20 19c0-1.6-1-3-2.5-3.6" />
        <path d="M17 6.2a2.5 2.5 0 0 1 0 4.6" />
      </>
    ),
    calendar: (
      <>
        <path d="M7 3v4" />
        <path d="M17 3v4" />
        <path d="M4 8h16" />
        <path d="M5 5h14v16H5z" />
      </>
    ),
    bolt: <path d="M13 2 4 14h7l-1 8 10-13h-7l1-7Z" />,
  };

  return (
    <svg
      aria-hidden="true"
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
    >
      {paths[name]}
    </svg>
  );
}
