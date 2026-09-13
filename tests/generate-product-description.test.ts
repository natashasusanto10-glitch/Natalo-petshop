import assert from "node:assert/strict";
import test, { describe } from "node:test";
import type Anthropic from "@anthropic-ai/sdk";
import { extractDescriptionText } from "@/lib/ai/generate-product-description";

const text = (t: string) =>
  ({ type: "text", text: t, citations: null }) as unknown as Anthropic.ContentBlock;

describe("extractDescriptionText", () => {
  test("menggabungkan beberapa text block yang dipecah sitasi", () => {
    assert.equal(
      extractDescriptionText([text("Makanan kucing "), text("dewasa.")]),
      "Makanan kucing dewasa.",
    );
  });

  test("melewati blok server tool web search", () => {
    const blocks = [
      { type: "server_tool_use", name: "web_search" },
      { type: "web_search_tool_result", content: [] },
      text("Deskripsi produk."),
    ] as unknown as Anthropic.ContentBlock[];
    assert.equal(extractDescriptionText(blocks), "Deskripsi produk.");
  });

  test("membuang fence markdown", () => {
    assert.equal(
      extractDescriptionText([text("```\nDeskripsi produk.\n```")]),
      "Deskripsi produk.",
    );
  });

  test("balikan kosong kalau tak ada text block", () => {
    const blocks = [
      { type: "web_search_tool_result", content: [] },
    ] as unknown as Anthropic.ContentBlock[];
    assert.equal(extractDescriptionText(blocks), "");
  });
});
