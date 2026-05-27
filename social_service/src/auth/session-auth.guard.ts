import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { PrismaService } from "../prisma.service";

export type SocialSessionUser = {
  id: string;
  role: "ADMIN" | "CUSTOMER";
  name: string;
};

export type SocialRequest = {
  headers: Record<string, string | string[] | undefined>;
  user?: SocialSessionUser;
};

type SessionPayload = {
  sub?: unknown;
  role?: unknown;
  name?: unknown;
  tv?: unknown;
};

const COOKIE_NAMES = ["member_session", "admin_session", "session"];

@Injectable()
export class SessionAuthGuard implements CanActivate {
  constructor(private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<SocialRequest>();
    const token = extractToken(request);
    if (!token) {
      throw new UnauthorizedException("Login dulu untuk akses fitur sosial.");
    }

    const secret = process.env.SESSION_SECRET;
    if (!secret || secret.length < 32) {
      throw new UnauthorizedException("Session secret belum dikonfigurasi.");
    }

    let payload: SessionPayload;
    try {
      const { jwtVerify } = await import("jose");
      const verified = await jwtVerify(
        token,
        new TextEncoder().encode(secret),
      );
      payload = verified.payload as SessionPayload;
    } catch {
      throw new UnauthorizedException("Sesi tidak valid.");
    }

    if (
      typeof payload.sub !== "string" ||
      (payload.role !== "CUSTOMER" && payload.role !== "ADMIN")
    ) {
      throw new UnauthorizedException("Sesi tidak valid.");
    }

    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, role: true, name: true, tokenVersion: true },
    });
    if (!user || user.role !== payload.role) {
      throw new UnauthorizedException("Sesi tidak valid.");
    }

    const tokenVersion =
      typeof payload.tv === "number" && Number.isFinite(payload.tv)
        ? payload.tv
        : 0;
    if (tokenVersion < user.tokenVersion) {
      throw new UnauthorizedException("Sesi sudah berakhir.");
    }

    request.user = {
      id: user.id,
      role: user.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
      name: user.name,
    };
    return true;
  }
}

function extractToken(request: SocialRequest) {
  const authorization = firstHeader(request.headers.authorization);
  const bearer = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (bearer) return bearer;

  const cookie = firstHeader(request.headers.cookie);
  if (!cookie) return null;

  for (const name of COOKIE_NAMES) {
    const token = findCookie(cookie, name);
    if (token) return token;
  }
  return null;
}

function firstHeader(value: string | string[] | undefined) {
  if (Array.isArray(value)) return value[0];
  return value;
}

function findCookie(cookieHeader: string, name: string) {
  const parts = cookieHeader.split(";");
  for (const part of parts) {
    const [rawKey, ...rawValue] = part.trim().split("=");
    if (rawKey === name) return rawValue.join("=").trim() || null;
  }
  return null;
}
