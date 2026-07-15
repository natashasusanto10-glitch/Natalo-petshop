export type VariantPersistenceMode = "parent-save" | "endpoint";

export function variantPersistenceMode(mode: "controlled" | "standalone" = "standalone"): VariantPersistenceMode {
  return mode === "controlled" ? "parent-save" : "endpoint";
}
