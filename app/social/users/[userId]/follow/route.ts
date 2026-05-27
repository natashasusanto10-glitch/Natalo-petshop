import {
  followUser,
  requireSocialUserId,
  socialError,
  socialJson,
  unfollowUser,
} from "../../_follow";

export async function POST(
  _request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  try {
    const viewerUserId = await requireSocialUserId();
    const { userId } = await params;
    return socialJson(await followUser(viewerUserId, userId));
  } catch (error) {
    return socialError(error);
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  try {
    const viewerUserId = await requireSocialUserId();
    const { userId } = await params;
    return socialJson(await unfollowUser(viewerUserId, userId));
  } catch (error) {
    return socialError(error);
  }
}
