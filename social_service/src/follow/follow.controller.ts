import {
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  Req,
  UnauthorizedException,
  UseGuards,
} from "@nestjs/common";
import {
  SessionAuthGuard,
  type SocialRequest,
} from "../auth/session-auth.guard";
import { FollowService } from "./follow.service";

@Controller("social/users")
export class FollowController {
  constructor(private readonly followService: FollowService) {}

  @Post(":userId/follow")
  @UseGuards(SessionAuthGuard)
  follow(@Param("userId") userId: string, @Req() request: SocialRequest) {
    return this.followService.follow(requireUserId(request), userId);
  }

  @Delete(":userId/follow")
  @UseGuards(SessionAuthGuard)
  unfollow(@Param("userId") userId: string, @Req() request: SocialRequest) {
    return this.followService.unfollow(requireUserId(request), userId);
  }

  @Get(":userId/follow-state")
  @UseGuards(SessionAuthGuard)
  state(@Param("userId") userId: string, @Req() request: SocialRequest) {
    return this.followService.getState(requireUserId(request), userId);
  }

  @Get(":userId/followers")
  followers(
    @Param("userId") userId: string,
    @Query("cursor") cursor?: string,
    @Query("limit") limit?: string,
  ) {
    return this.followService.listFollowers(userId, { cursor, limit });
  }

  @Get(":userId/following")
  following(
    @Param("userId") userId: string,
    @Query("cursor") cursor?: string,
    @Query("limit") limit?: string,
  ) {
    return this.followService.listFollowing(userId, { cursor, limit });
  }
}

function requireUserId(request: SocialRequest) {
  if (!request.user?.id) {
    throw new UnauthorizedException("Sesi tidak valid.");
  }
  return request.user.id;
}
