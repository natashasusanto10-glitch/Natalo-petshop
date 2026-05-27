import {
  getFollowState,
  requireSocialUserId,
  socialError,
  socialJson,
} from "../../_follow";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  try {
    const viewerUserId = await requireSocialUserId();
    const { userId } = await params;
    return socialJson(await getFollowState(viewerUserId, userId));
  } catch (error) {
    return socialError(error);
  }
}
