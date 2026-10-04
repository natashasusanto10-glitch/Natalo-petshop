"use client";

import { useRef, type ComponentPropsWithoutRef } from "react";
import { formatAdminNumber } from "@/lib/admin/number-input";

type Props = Omit<
  ComponentPropsWithoutRef<"input">,
  "type" | "value" | "onChange"
> & {
  value: string;
  onValueChange(value: string): void;
  thousands?: boolean;
};

export function NumberInput({
  value,
  onValueChange,
  thousands = true,
  ...props
}: Props) {
  const input = useRef<HTMLInputElement>(null);
  const displayed = thousands ? formatAdminNumber(value) : value;
  return (
    <input
      {...props}
      ref={input}
      type="text"
      inputMode="numeric"
      value={displayed}
      onChange={(event) => {
        const field = event.currentTarget;
        const raw = field.value;
        if (!thousands) {
          onValueChange(raw);
          return;
        }
        const digitsBeforeCaret = raw
          .slice(0, field.selectionStart ?? raw.length)
          .replace(/\./g, "").length;
        const next = raw.replace(/\./g, "");
        onValueChange(next);
        // Update the formatted value immediately so caret restoration does not race a frame.
        const formatted = thousands ? formatAdminNumber(next) : next;
        field.value = formatted;
        let caret = 0,
          digits = 0;
        while (caret < formatted.length && digits < digitsBeforeCaret) {
          if (formatted[caret] !== ".") digits++;
          caret++;
        }
        field.setSelectionRange(caret, caret);
      }}
      onBeforeInput={(event) => {
        const field = event.currentTarget;
        const caret = field.selectionStart;
        if (!thousands || caret === null || caret !== field.selectionEnd)
          return;
        const kind = (event.nativeEvent as InputEvent).inputType;
        if (kind === "deleteContentBackward" && field.value[caret - 1] === ".")
          field.setSelectionRange(caret - 1, caret - 1);
        if (kind === "deleteContentForward" && field.value[caret] === ".")
          field.setSelectionRange(caret + 1, caret + 1);
      }}
    />
  );
}
