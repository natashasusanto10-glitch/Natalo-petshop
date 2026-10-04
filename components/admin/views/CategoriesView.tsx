import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import { FiEdit2, FiTrash2 } from "react-icons/fi";
import {
  PageHeader,
  EmptyState,
  Badge,
  AdminPage,
  Button,
} from "@/components/admin/ui";

export function CategoriesView({
  categories,
  deleteCategory,
}: {
  categories: Array<{
    id: string;
    name: string;
    slug: string;
    _count: { products: number };
  }>;
  deleteCategory: (formData: FormData) => Promise<void>;
}) {
  return (
    <AdminPage maxWidth="lg" className="admin-operational-page">
      <PageHeader
        title="Kategori"
        subtitle={`${categories.length} kategori terdaftar.`}
        actions={
          <>
            <Button href="/admin/dashboard" variant="secondary" size="sm">
              Kembali ke ringkasan
            </Button>
            <Button href="/admin/categories/new" size="sm">
              + Tambah Kategori
            </Button>
          </>
        }
      />

      {categories.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon="🏷️"
            title="Belum ada kategori"
            description="Tambahkan kategori pertama untuk mengelompokkan produk."
            action={{
              label: "Tambah kategori pertama",
              href: "/admin/categories/new",
            }}
            size="full"
          />
        </div>
      ) : (
        <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
          <div className="divide-y divide-zinc-100">
            {categories.map((cat) => (
              <div
                key={cat.id}
                className="flex flex-wrap items-center gap-3 px-5 py-4 transition hover:bg-slate-50"
              >
                <div className="min-w-[120px] flex-1">
                  <span className="truncate text-sm font-bold text-zinc-900">
                    {cat.name}
                  </span>
                  <span className="mt-1 block break-all text-xs text-slate-500">
                    /{cat.slug}
                  </span>
                </div>

                <Badge variant={cat._count.products > 0 ? "info" : "neutral"}>
                  {cat._count.products} produk
                </Badge>

                <div className="flex shrink-0 items-center gap-1.5">
                  <Button
                    href={`/admin/categories/${cat.id}/edit`}
                    variant="secondary"
                    size="sm"
                    aria-label={`Edit ${cat.name}`}
                    title="Edit"
                  >
                    <FiEdit2 className="h-3.5 w-3.5" />
                  </Button>

                  <form action={deleteCategory}>
                    <input type="hidden" name="id" value={cat.id} />
                    <ConfirmSubmitButton
                      title="Hapus kategori?"
                      message={`Hapus kategori ${cat.name}? Tindakan ini tidak dapat dibatalkan.`}
                      confirmLabel="Hapus kategori"
                      disabled={cat._count.products > 0}
                      ariaLabel={`Hapus ${cat.name}${
                        cat._count.products > 0
                          ? " (masih memiliki produk)"
                          : ""
                      }`}
                      className="admin-button inline-flex min-h-10 items-center justify-center rounded-lg border border-red-200 bg-white px-3 py-2 text-red-600 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <FiTrash2 className="h-3.5 w-3.5" />
                    </ConfirmSubmitButton>
                  </form>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </AdminPage>
  );
}
