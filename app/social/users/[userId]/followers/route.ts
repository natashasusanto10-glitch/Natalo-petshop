import { listFollowers, socialError, socialJson } from "../../_follow";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  try {
    const { userId } = await params;
    const url = new URL(request.url);
    return socialJson(
      await listFollowers(userId, {
        cursor: url.searchParams.get("cursor"),
        limit: url.searchParams.get("limit"),
      }),
    );
  } catch (error) {
    return socialError(error);
  }
}
