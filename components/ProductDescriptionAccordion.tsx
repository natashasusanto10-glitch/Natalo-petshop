type Props = {
  description: string;
};

type Section = {
  title: string;
  body: string;
};

function stripMarkdown(input: string) {
  return input
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\*\*(.*?)\*\*/g, "$1")
    .replace(/\*(.*?)\*/g, "$1")
    .replace(/^---+$/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}

function parseSections(markdown: string): Section[] {
  const normalized = markdown.replace(/\r\n/g, "\n").trim();
  const matches = Array.from(normalized.matchAll(/^##\s+(.+)$/gm));

  if (!matches.length) {
    return [{ title: "Deskripsi Produk", body: normalized }];
  }

  return matches.map((match, index) => {
    const start = (match.index ?? 0) + match[0].length;
    const end = matches[index + 1]?.index ?? normalized.length;
    return {
      title: match[1].trim(),
      body: normalized.slice(start, end).trim(),
    };
  });
}

function renderInline(text: string) {
  const parts = text.split(/(\*\*.*?\*\*|\*.*?\*)/g).filter(Boolean);
  return parts.map((part, index) => {
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={index}>{part.slice(2, -2)}</strong>;
    }
    if (part.startsWith("*") && part.endsWith("*")) {
      return <em key={index}>{part.slice(1, -1)}</em>;
    }
    return <span key={index}>{part}</span>;
  });
}

function MarkdownBlock({ body }: { body: string }) {
  const blocks = body
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter(Boolean);

  return (
    <div className="space-y-3 text-sm leading-6 text-gray-600">
      {blocks.map((block, index) => {
        if (/^---+$/.test(block)) {
          return <hr key={index} className="border-gray-100" />;
        }

        const lines = block.split("\n").map((line) => line.trim()).filter(Boolean);
        if (lines.every((line) => line.startsWith("- "))) {
          return (
            <ul key={index} className="list-disc space-y-1 pl-5">
              {lines.map((line, lineIndex) => (
                <li key={lineIndex}>{renderInline(line.slice(2))}</li>
              ))}
            </ul>
          );
        }

        return <p key={index}>{renderInline(block)}</p>;
      })}
    </div>
  );
}

export function ProductDescriptionAccordion({ description }: Props) {
  const sections = parseSections(description);
  const summary = stripMarkdown(description);
  const preferred = [
    "Detail Produk",
    "Deskripsi Produk",
    "Manfaat Utama",
    "Cocok Untuk",
    "Informasi Pengiriman",
    "Cara Penyimpanan",
  ];
  const normalizedSections = preferred.map((title) => {
    const found = sections.find((section) =>
      section.title.toLowerCase().includes(title.toLowerCase().replace("produk", "").trim()),
    );
    return {
      title,
      body: found?.body ?? (title === "Deskripsi Produk" ? sections[0]?.body ?? description : ""),
    };
  });

  return (
    <section className="border-t border-gray-100 bg-white px-4 py-4 md:rounded-3xl md:border md:p-6">
      <h2 className="text-base font-black text-gray-900">Deskripsi Produk</h2>
      <p className="mt-2 line-clamp-3 text-sm leading-6 text-gray-600">{summary}</p>
      <p className="mt-2 text-sm font-extrabold text-natalo-600">Lihat Selengkapnya</p>

      <div className="mt-3 divide-y divide-gray-100">
        {normalizedSections.map((section, index) => (
          <details key={section.title} className="group py-3" open={index === 0}>
            <summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-sm font-extrabold text-gray-900">
              <span>{section.title}</span>
              <span className="text-lg leading-none text-gray-400 group-open:rotate-45">+</span>
            </summary>
            <div className="pt-3">
              {section.body ? (
                <MarkdownBlock body={section.body} />
              ) : (
                <p className="text-sm leading-6 text-gray-500">Informasi belum tersedia.</p>
              )}
            </div>
          </details>
        ))}
      </div>
    </section>
  );
}
