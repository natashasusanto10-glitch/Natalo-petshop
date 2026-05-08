"use client";

import { Fragment } from "react";
import { trustItems as defaultItems, type TrustItem, type TrustItemIcon } from "@/data/trustItems";

export default function TrustMarquee({
  items = defaultItems,
  durationSec = 22,
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
          target="_blank"
          rel="noopener noreferrer"
          className="group flex items-center gap-1.5 transition hover:text-natalo-800"
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
      <div className="marquee-group flex shrink-0 items-center gap-5 pr-5" aria-hidden={prefix === "b"}>
        {items.map((item, index) => (
          <Fragment key={`${prefix}-${index}`}>
            {renderItem(item, `${prefix}-${index}`)}
            <span className="text-slate-300" aria-hidden="true">
              |
            </span>
          </Fragment>
        ))}
      </div>
    );
  }

  return (
    <div className="marquee-wrap overflow-hidden border-b border-slate-200 bg-gradient-to-r from-natalo-50 via-amber-50 to-natalo-50">
      <div
        className="marquee-track flex w-max items-center whitespace-nowrap py-2 text-[11px] font-semibold text-slate-700"
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
          .marquee-track {
            animation: none;
          }
        }
      `}</style>
    </div>
  );
}

function TrustSvg({ name, className }: { name: TrustItemIcon; className?: string }) {
  const paths: Record<TrustItemIcon, React.ReactNode> = {
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
