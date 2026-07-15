export type DescriptionContextInput = {
  name: string;
  categoryName?: string | null;
  brandName?: string | null;
  variants?: Array<{ optionRefs?: string[]; optionValues?: string[] }>;
};

export function buildDescriptionContext(input: DescriptionContextInput) {
  const variantOptions = (input.variants ?? []).flatMap((variant) =>
    (variant.optionValues?.length ? variant.optionValues : variant.optionRefs ?? []).filter(Boolean),
  );
  return {
    name: input.name.trim(),
    categoryName: input.categoryName?.trim() || null,
    brandName: input.brandName?.trim() || null,
    variantOptions,
  };
}

export function buildGenerationPayload(context: DescriptionContextInput, name: string) {
  return buildDescriptionContext({ ...context, name: name || context.name });
}
