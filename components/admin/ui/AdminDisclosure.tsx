"use client";

import { useId, useState, type ReactNode } from "react";

export function AdminDisclosure({
  title,
  id,
  children,
}: {
  title: string;
  id?: string;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const contentId = useId();
  return (
    <section id={id} className="admin-section">
      <button
        type="button"
        className="admin-disclosure-trigger"
        aria-expanded={open}
        aria-controls={contentId}
        onClick={() => setOpen((value) => !value)}
      >
        {title}
        <span aria-hidden="true">{open ? "−" : "+"}</span>
      </button>
      <div
        className={`admin-variant-disclosure ${open ? "is-open" : ""}`}
        inert={!open}
        aria-hidden={!open}
      >
        <div id={contentId} className="admin-variant-disclosure-content">
          <div className="admin-section-body">{children}</div>
        </div>
      </div>
    </section>
  );
}
