export type VideoMutationInput = {
  existingGuid?: string | null;
  removeRequested: boolean;
  saveSucceeded: boolean;
};

export type VideoMutation = { deleteGuid: string | null; preserveGuid: string | null };

/** Resolve Bunny cleanup only after the parent product transaction succeeds. */
export function nextVideoMutation(input: VideoMutationInput): VideoMutation {
  const existingGuid = input.existingGuid || null;
  if (!input.saveSucceeded) return { deleteGuid: null, preserveGuid: existingGuid };
  return input.removeRequested
    ? { deleteGuid: existingGuid, preserveGuid: null }
    : { deleteGuid: null, preserveGuid: existingGuid };
}

export function resolveHiddenCreateFailure(input: {
  productId: string;
  uploadSucceeded: boolean;
}): { compensateProductId: string } | null {
  return input.uploadSucceeded ? null : { compensateProductId: input.productId };
}
