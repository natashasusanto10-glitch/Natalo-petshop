"use client";

interface LogoutButtonProps {
  redirectTo: string;
  className?: string;
}

export function LogoutButton({ redirectTo, className = "" }: LogoutButtonProps) {
  function clearCart() {
    localStorage.removeItem("cart");
    window.dispatchEvent(new Event("cart-updated"));
  }

  async function handleLogout() {
    clearCart();
    await fetch("/api/auth/logout", { method: "POST" }).catch(() => {});
    clearCart();
    window.location.replace(redirectTo);
  }

  return (
    <button
      onClick={handleLogout}
      className={`rounded-full border border-gray-200 px-5 py-2.5 text-sm font-semibold text-gray-700 transition hover:border-red-300 hover:text-red-500 ${className}`}
    >
      Keluar
    </button>
  );
}
