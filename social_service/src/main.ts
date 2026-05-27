import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";
import { loadSocialEnv } from "./env";

async function bootstrap() {
  loadSocialEnv();

  const app = await NestFactory.create(AppModule);
  app.enableCors({
    origin: true,
    credentials: true,
  });

  const port = Number(process.env.SOCIAL_SERVICE_PORT ?? process.env.PORT ?? 4001);
  await app.listen(port, "0.0.0.0");
  // eslint-disable-next-line no-console
  console.log(`[social] service listening on :${port}`);
}

void bootstrap();
