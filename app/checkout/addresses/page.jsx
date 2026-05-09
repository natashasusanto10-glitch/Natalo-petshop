import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { CheckoutAddressList } from "@/components/CheckoutAddressList";

function safeReturnTo(value) {
  return typeof value === "string" && value.startsWith("/checkout") && !value.startsWith("//")
    ? value
    : "/checkout";
}

export default async function CheckoutAddressesPage({ searchParams }) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") redirect("/member/login");

  const sp = (await searchParams) ?? {};
  const returnTo = safeReturnTo(sp.returnTo);

  const addresses = await prisma.address.findMany({
    where: { userId: session.sub },
    orderBy: [{ isMain: "desc" }, { createdAt: "asc" }],
  });

  return (
    <CheckoutAddressList
      addresses={JSON.parse(JSON.stringify(addresses))}
      returnTo={returnTo}
    />
  );
}
