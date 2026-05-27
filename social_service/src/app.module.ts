import { Module } from "@nestjs/common";
import { HealthController } from "./health.controller";
import { FollowModule } from "./follow/follow.module";

@Module({
  imports: [FollowModule],
  controllers: [HealthController],
})
export class AppModule {}
