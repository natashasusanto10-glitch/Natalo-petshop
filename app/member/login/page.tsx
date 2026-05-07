import { MemberLoginForm } from "@/components/MemberLoginForm";

export default async function MemberLoginPage({
  searchParams,
}: {
  searchParams: Promise<{ registered?: string }>;
}) {
  const { registered } = await searchParams;

  return <MemberLoginForm registered={!!registered} />;
}
