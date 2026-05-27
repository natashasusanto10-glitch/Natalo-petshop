import { Module } from "@nestjs/common";
import { PrismaService } from "../prisma.service";
import { SessionAuthGuard } from "../auth/session-auth.guard";
import { FollowController } from "./follow.controller";
import { FollowService } from "./follow.service";

@Module({
  controllers: [FollowController],
  providers: [FollowService, PrismaService, SessionAuthGuard],
})
export class FollowModule {}
