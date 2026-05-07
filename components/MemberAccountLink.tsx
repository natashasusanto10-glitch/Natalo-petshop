"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

type MemberProfile = {
  name?: string;
  email?: string | null;
  phone?: string | null;
};

export function MemberAccountLink() {
  const [member, setMember] = useState<MemberProfile | null>(null);

  useEffect(() => {
    let active = true;

    fetch("/api/auth/me", { cache: "no-store" })
      .then((res) => res.json())
      .then((data: MemberProfile) => {
        if (active && data.name) setMember(data);
      })
      .catch(() => {});

    return () => {
      active = false;
    };
  }, []);

  if (member) {
    return (
      <Link
        href="/member"
        aria-label="Halaman member"
        title="Halaman member"
        className="inline-flex h-8 w-8 items-center justify-center rounded-full border border-natalo-200 text-natalo-700 transition hover:border-natalo-400 hover:text-natalo-600 sm:h-9 sm:w-9"
      >
        <svg
          className="h-4 w-4 sm:h-5 sm:w-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={1.8}
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <path d="M20 21a8 8 0 0 0-16 0" />
          <circle cx="12" cy="7" r="4" />
        </svg>
      </Link>
    );
  }

  return (
    <Link
      href="/member"
      className="inline-flex shrink-0 rounded-full bg-[#468284] px-3 py-1.5 text-xs font-black text-white transition hover:brightness-95 sm:px-4 sm:py-2 sm:text-sm"
    >
      Masuk
    </Link>
  );
}
