"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Script from "next/script";
import { FiArrowLeft, FiGift } from "react-icons/fi";
import { formatRupiah, formatShippingDuration } from "@/lib/format";
import { toCustomerShippingErrorMessage } from "@/lib/shipping-messages";
import { BottomSheet } from "@/components/BottomSheet";
import { MetodePengiriman } from "@/components/MetodePengiriman";
import {
  DELIVERY_METHOD,
  SELF_PICKUP_METHOD,
  SELF_PICKUP_STORE,
  buildSelfPickupMapsUrl,
  isSelfPickupMethod,
} from "@/lib/self-pickup";
import {
  CheckoutVoucherCard,
  type AppliedVoucher,
  type EligibleVoucher,
  type IneligibleVoucher,
} from "@/components/checkout/CheckoutVoucherCard";
import {
  MetodePembayaran,
  type PaymentSelection,
} from "@/components/MetodePembayaran";
import { loadCart, saveCart, clearCartEverywhere, type CartItem } from "@/lib/cart";
import type { CartStockIssue } from "@/lib/cart-stock";
import { BiteshipAreaCombobox, type ShippingArea } from "@/components/BiteshipAreaCombobox";

type RateOption = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  service_type: string;
  price: number;
  duration: string;
  available: boolean;
  unavailable_reason?: string;
};

type CheckoutPricing = {
  subtotal: number;
  shipping_fee: number;
  discount: number;
  total: number;
};

type AppliedVoucherShape = (EligibleVoucher & {
  title?: string;
  autoApplied?: boolean;
}) | null;

type CheckoutRecalculateResponse = CheckoutPricing & {
  applied_voucher?: AppliedVoucherShape;
  auto_applied_voucher?: {
    code: string;
    title: string;
    description: string;
    discount: number;
  } | null;
  // Dual-slot fields (lihat aturan voucher di CLAUDE.md)
  applied_customer_voucher?: AppliedVoucherShape;
  applied_manual_voucher?: AppliedVoucherShape;
  available_vouchers?: EligibleVoucher[];
  unavailable_vouchers?: IneligibleVoucher[];
  voucher_invalidated?: boolean;
  invalidated_message?: string | null;
  customer_voucher_error?: string | null;
  manual_voucher_error?: string | null;
};

type CheckoutBenefit = {
  key: string;
  label: string;
  value: string;
  amount?: number;
};

declare global {
  interface Window {
    snap?: {
      pay: (token: string, options: {
        onSuccess: (result: unknown) => void;
        onPending: (result: unknown) => void;
        onError: (result: unknown) => void;
        onClose: () => void;
      }) => void;
    };
  }
}

const isMidtransEnabled = !!process.env.NEXT_PUBLIC_MIDTRANS_CLIENT_KEY;
const CHECKOUT_SELECTION_KEY = "checkout:selectedCartItems";
const CHECKOUT_DRAFT_KEY = "checkout:draft";
const CHECKOUT_SELECTED_ADDRESS_KEY = "checkout:selectedAddressId";
const CHECKOUT_ADDRESS_FORCE_APPLY_KEY = "checkout:addressForceApply";

type CheckoutReturnTarget = {
  href: string;
  ariaLabel: string;
  buttonLabel: string;
  title: string;
  message: string;
};

const DEFAULT_CHECKOUT_RETURN_TARGET: CheckoutReturnTarget = {
  href: "/cart",
  ariaLabel: "Kembali ke keranjang",
  buttonLabel: "Kembali ke Keranjang",
  title: "Yakin kembali ke keranjang?",
  message:
    "Pesanan kamu belum selesai. Kamu bisa lanjut checkout atau kembali mengatur keranjang.",
};

function sanitizeCheckoutReturnPath(rawReturnTo: string | null) {
  if (!rawReturnTo) return null;
  const value = rawReturnTo.trim();
  if (!value || !value.startsWith("/") || value.startsWith("//")) return null;
  if (value.startsWith("/checkout")) return null;
  return value;
}

function resolveCheckoutReturnTarget(rawReturnTo: string | null): CheckoutReturnTarget {
  const href = sanitizeCheckoutReturnPath(rawReturnTo);

  if (href?.startsWith("/feed")) {
    return {
      href,
      ariaLabel: "Kembali ke Feed",
      buttonLabel: "Kembali ke Feed",
      title: "Yakin kembali ke Feed?",
      message:
        "Pesanan kamu belum selesai. Kamu bisa lanjut checkout atau kembali ke Feed.",
    };
  }

  return DEFAULT_CHECKOUT_RETURN_TARGET;
}

function cartKey(item: CartItem) {
  return `${item.productId}:${item.variantId ?? ""}`;
}

function hasUsablePinpoint(latitude?: number | null, longitude?: number | null) {
  return (
    typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    !(latitude === 0 && longitude === 0)
  );
}

function isInstantCheckoutRate(rate: RateOption) {
  const courierCode = rate.courier_code.toLowerCase();
  return (
    (courierCode === "gojek" || courierCode === "grab") &&
    (rate.service_type === "instant" || rate.service_type === "same_day") &&
    rate.available
  );
}

export default function CheckoutPage() {
  const router = useRouter();
  const [items, setItems] = useState<CartItem[]>([]);
  const [checkoutItemKeys, setCheckoutItemKeys] = useState<Set<string> | null>(null);
  const [rates, setRates] = useState<RateOption[]>([]);
  const [selectedRate, setSelectedRate] = useState<RateOption | null>(null);
  const [shippingSheetOpen, setShippingSheetOpen] = useState(false);
  const [shippingError, setShippingError] = useState("");
  const [instantShippingHint, setInstantShippingHint] = useState("");
  const [payment, setPayment] = useState<PaymentSelection | null>(null);
  const paymentMethod = payment?.provider ?? null;
  const [ratesLoading, setRatesLoading] = useState(false);
  const [orderLoading, setOrderLoading] = useState(false);
  const [error, setError] = useState("");
  const [addressBookLoading, setAddressBookLoading] = useState(true);
  const [addressBookError, setAddressBookError] = useState("");
  const [addressMode, setAddressMode] = useState<"saved" | "manual" | "select">("manual");

  const [form, setForm] = useState({
    customerName: "",
    customerPhone: "",
    customerEmail: "",
    shippingAddress: "",
    shippingCity: "",
    shippingPostalCode: "",
    shippingLatitude: null as number | null,
    shippingLongitude: null as number | null,
    shippingPinpointAddress: null as string | null,
    shippingAreaId: "",
    shippingAreaLabel: "",
    shippingProvinceName: "",
    shippingDistrictName: "",
    voucherCode: "",
    manualVoucherCode: "",
    notes: "",
  });

  type SavedAddress = {
    id: string; label: string; recipientName: string; phone: string;
    address: string; city: string; postalCode: string; isMain: boolean;
    areaId?: string | null; areaLabel?: string | null; provinceName?: string | null; cityName?: string | null; districtName?: string | null;
    latitude?: number | null; longitude?: number | null; pinpointAddress?: string | null; streetName?: string | null;
  };
  const [savedAddresses, setSavedAddresses] = useState<SavedAddress[]>([]);
  const [selectedAddressId, setSelectedAddressId] = useState<string>("");
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [saveToAddressBook, setSaveToAddressBook] = useState(false);
  const [addressLabel, setAddressLabel] = useState("");

  const [voucherInput, setVoucherInput] = useState("");
  const [voucherApplied, setVoucherApplied] = useState<AppliedVoucher | null>(null);
  // Slot voucher manual penjual (SELLER_MANUAL) — paralel dgn voucherApplied
  // (CUSTOMER). Maks 1 dari masing-masing per checkout.
  const [manualVoucherApplied, setManualVoucherApplied] =
    useState<AppliedVoucher | null>(null);
  const [eligibleVouchers, setEligibleVouchers] = useState<EligibleVoucher[]>([]);
  const [ineligibleVouchers, setIneligibleVouchers] = useState<IneligibleVoucher[]>([]);
  const [voucherInvalidated, setVoucherInvalidated] = useState<string | null>(null);
  const [voucherSyncLoading, setVoucherSyncLoading] = useState(false);
  // `voucherSyncFailed`: true kalau server-side recalculate gagal (network).
  // Sebelumnya kita silently fallback ke client-side discount calculation,
  // padahal voucher belum di-validate server-side → user lihat diskon
  // yang mungkin sudah tidak valid (mis. voucher expired, atau subtotal
  // turun di bawah min_order). Sekarang clear discount + disable CTA
  // sampai recalculation succeed lagi.
  const [voucherSyncFailed, setVoucherSyncFailed] = useState(false);
  const [autoVoucherSuppressed, setAutoVoucherSuppressed] = useState(false);
  const [checkoutPricing, setCheckoutPricing] = useState<CheckoutPricing | null>(null);
  const [showAllCheckoutItems, setShowAllCheckoutItems] = useState(false);
  const [draftReady, setDraftReady] = useState(false);
  const [stockIssues, setStockIssues] = useState<CartStockIssue[]>([]);
  const [stockRefreshing, setStockRefreshing] = useState(false);
  const [backConfirmOpen, setBackConfirmOpen] = useState(false);
  const [checkoutReturnTarget, setCheckoutReturnTarget] = useState<CheckoutReturnTarget>(
    DEFAULT_CHECKOUT_RETURN_TARGET,
  );
  const returningToCartRef = useRef(false);

  useEffect(() => {
    let restoredDraft: {
      form?: typeof form;
      selectedAddressId?: string;
      addressMode?: "saved" | "manual" | "select";
      voucherInput?: string;
      voucherApplied?: typeof voucherApplied;
      selectedRate?: RateOption | null;
      rates?: RateOption[];
      payment?: PaymentSelection | null;
      saveToAddressBook?: boolean;
      addressLabel?: string;
    } | null = null;

    try {
      restoredDraft = JSON.parse(sessionStorage.getItem(CHECKOUT_DRAFT_KEY) || "null");
    } catch {
      restoredDraft = null;
    }

    if (restoredDraft) {
      if (restoredDraft.form) setForm((current) => ({ ...current, ...restoredDraft.form }));
      if (restoredDraft.selectedAddressId) setSelectedAddressId(restoredDraft.selectedAddressId);
      if (restoredDraft.addressMode) {
        setAddressMode(restoredDraft.addressMode === "select" ? "saved" : restoredDraft.addressMode);
      }
      if (restoredDraft.voucherInput !== undefined) setVoucherInput(restoredDraft.voucherInput);
      if (restoredDraft.voucherApplied !== undefined) setVoucherApplied(restoredDraft.voucherApplied);
      if (restoredDraft.selectedRate !== undefined) setSelectedRate(restoredDraft.selectedRate);
      if (Array.isArray(restoredDraft.rates)) setRates(restoredDraft.rates);
      if (restoredDraft.payment !== undefined) setPayment(restoredDraft.payment);

    }

    // Pickup voucher pre-selection dari cart (cart:voucher sessionStorage).
    // Backend tetap re-validate semua voucher di /api/checkout/recalculate.
    try {
      const cartVoucherRaw = sessionStorage.getItem("cart:voucher");
      if (cartVoucherRaw) {
        const parsed = JSON.parse(cartVoucherRaw) as {
          member?: { code: string; discount: number; description: string } | null;
          private?: { code: string; discount: number; description: string } | null;
        };
        if (parsed.member?.code) {
          setForm((current) =>
            current.voucherCode
              ? current
              : { ...current, voucherCode: parsed.member!.code },
          );
        }
        if (parsed.private?.code) {
          setForm((current) =>
            current.manualVoucherCode
              ? current
              : { ...current, manualVoucherCode: parsed.private!.code },
          );
        }
      }
    } catch {
      // ignore corrupt session
    }

    if (restoredDraft) {
      if (restoredDraft.saveToAddressBook !== undefined) {
        setSaveToAddressBook(Boolean(restoredDraft.saveToAddressBook));
      }
      if (restoredDraft.addressLabel !== undefined) setAddressLabel(restoredDraft.addressLabel);
    }
    setDraftReady(true);

    const cartItems = loadCart();
    const params = new URLSearchParams(window.location.search);
    setCheckoutReturnTarget(resolveCheckoutReturnTarget(params.get("returnTo")));
    const selectedParam = params.get("cart_item_ids");
    const selectedKeys = selectedParam
      ? selectedParam.split(",").map((key) => decodeURIComponent(key)).filter(Boolean)
      : [];

    if (selectedKeys.length > 0) {
      const keySet = new Set(selectedKeys);
      let selectedCartItems = cartItems.filter((item) => keySet.has(cartKey(item)));

      if (selectedCartItems.length === 0) {
        try {
          const stored = JSON.parse(sessionStorage.getItem(CHECKOUT_SELECTION_KEY) || "[]");
          selectedCartItems = Array.isArray(stored)
            ? stored.filter((item: CartItem) => keySet.has(cartKey(item)))
            : [];
        } catch {
          selectedCartItems = [];
        }
      }

      setItems(selectedCartItems);
      setCheckoutItemKeys(new Set(selectedCartItems.map(cartKey)));
      void refreshCheckoutStock(selectedCartItems, {
        silent: true,
        checkoutKeys: new Set(selectedCartItems.map(cartKey)),
      });
    } else {
      setItems(cartItems);
      setCheckoutItemKeys(null);
      void refreshCheckoutStock(cartItems, { silent: true, checkoutKeys: null });
    }

    fetch("/api/auth/me")
      .then((r) => r.json())
      .then((data) => {
        if (data?.name) setIsLoggedIn(true);
        if (data.name) setForm((f) => ({ ...f, customerName: f.customerName || data.name }));
        if (data.email) setForm((f) => ({ ...f, customerEmail: f.customerEmail || data.email }));
        if (data.phone) setForm((f) => ({ ...f, customerPhone: f.customerPhone || data.phone }));
      })
      .catch(() => {});

    fetch("/api/alamat")
      .then((r) => (r.ok ? r.json() : { addresses: [] }))
      .then((data) => {
        const list = Array.isArray(data?.addresses) ? data.addresses : [];
        if (list.length === 0) return;
        const mapped: SavedAddress[] = list.map((a: {
          id: string; label: string | null; recipient: string; phone: string;
          address: string; city: string | null; postalCode: string | null;
          areaId: string | null; areaLabel: string | null; provinceName: string | null; cityName: string | null; districtName: string | null;
          isMain: boolean; latitude: number | null; longitude: number | null;
          pinpointAddress: string | null; streetName: string | null;
        }) => {
          const hasPinpoint = hasUsablePinpoint(a.latitude, a.longitude);
          return {
            id: a.id,
            label: a.label ?? "Alamat",
            recipientName: a.recipient,
            phone: a.phone,
            address: a.address,
            city: a.city ?? "",
            postalCode: a.postalCode ?? "",
            areaId: a.areaId,
            areaLabel: a.areaLabel,
            provinceName: a.provinceName,
            cityName: a.cityName,
            districtName: a.districtName,
            isMain: a.isMain,
            latitude: hasPinpoint ? a.latitude : null,
            longitude: hasPinpoint ? a.longitude : null,
            pinpointAddress: hasPinpoint ? a.pinpointAddress : null,
            streetName: a.streetName,
          };
        });
        setSavedAddresses(mapped);

        let checkoutSelectedId = "";
        let draftSelectedId = restoredDraft?.selectedAddressId || "";
        let draftMode = restoredDraft?.addressMode === "select" ? "saved" : restoredDraft?.addressMode;
        let forceAddressApply = false;

        try {
          checkoutSelectedId = sessionStorage.getItem(CHECKOUT_SELECTED_ADDRESS_KEY) || "";
          forceAddressApply = sessionStorage.getItem(CHECKOUT_ADDRESS_FORCE_APPLY_KEY) === "1";
          if (forceAddressApply) sessionStorage.removeItem(CHECKOUT_ADDRESS_FORCE_APPLY_KEY);
        } catch {
          checkoutSelectedId = "";
        }

        const nextSelectedId = checkoutSelectedId || draftSelectedId;
        const selected = nextSelectedId
          ? mapped.find((addr) => addr.id === nextSelectedId)
          : null;

        if (selected) {
          setSelectedAddressId(selected.id);
          setAddressMode("saved");
          if (forceAddressApply || !draftSelectedId || checkoutSelectedId !== draftSelectedId) {
            applyAddressToForm(selected);
          }
          return;
        }

        if (draftMode === "manual") {
          setAddressMode("manual");
          return;
        }

        const main = mapped.find((a) => a.isMain) ?? mapped[0];
        setSelectedAddressId(main.id);
        if (!restoredDraft?.form) applyAddressToForm(main);
        setAddressMode("saved");
      })
      .catch(() => {
        setAddressBookError("Alamat tersimpan belum bisa dimuat. Kamu tetap bisa isi alamat baru.");
        setAddressMode("manual");
      })
      .finally(() => setAddressBookLoading(false));
  }, []);

  useEffect(() => {
    if (!draftReady) return;
    try {
      sessionStorage.setItem(
        CHECKOUT_DRAFT_KEY,
        JSON.stringify({
          form,
          selectedAddressId,
          addressMode: addressMode === "select" ? "saved" : addressMode,
          voucherInput,
          voucherApplied,
          selectedRate,
          rates,
          payment,
          saveToAddressBook,
          addressLabel,
        }),
      );
    } catch {}
  }, [
    draftReady,
    form,
    selectedAddressId,
    addressMode,
    voucherInput,
    voucherApplied,
    selectedRate,
    rates,
    payment,
    saveToAddressBook,
    addressLabel,
  ]);

  function applyAddressToForm(addr: {
    recipientName: string;
    phone: string;
    address: string;
    city: string;
    postalCode: string;
    areaId?: string | null;
    areaLabel?: string | null;
    provinceName?: string | null;
    cityName?: string | null;
    districtName?: string | null;
    latitude?: number | null;
    longitude?: number | null;
    pinpointAddress?: string | null;
  }) {
    const hasPinpoint = hasUsablePinpoint(addr.latitude, addr.longitude);
    setForm((f) => ({
      ...f,
      customerName: addr.recipientName || f.customerName,
      customerPhone: addr.phone || f.customerPhone,
      shippingAddress: addr.address,
      shippingCity: addr.cityName || addr.city,
      shippingPostalCode: addr.postalCode,
      shippingAreaId: addr.areaId || "",
      shippingAreaLabel: addr.areaLabel || addr.city || "",
      shippingProvinceName: addr.provinceName || "",
      shippingDistrictName: addr.districtName || "",
      shippingLatitude: hasPinpoint ? addr.latitude ?? null : null,
      shippingLongitude: hasPinpoint ? addr.longitude ?? null : null,
      shippingPinpointAddress: hasPinpoint ? addr.pinpointAddress ?? null : null,
    }));
    setSelectedRate(null);
    setPayment(null);
    setRates([]);
    setShippingError("");
  }

  function resetShippingSelection() {
    setSelectedRate(null);
    setPayment(null);
    setRates([]);
  }

  function selectShippingArea(area: ShippingArea) {
    setForm((current) => ({
      ...current,
      shippingAreaId: area.area_id,
      shippingAreaLabel: area.label,
      shippingProvinceName: area.province_name,
      shippingCity: area.city_name,
      shippingDistrictName: area.district_name,
      shippingPostalCode: area.postal_code,
    }));
    resetShippingSelection();
    setShippingError("");
  }

  function clearShippingArea() {
    setForm((current) => ({
      ...current,
      shippingAreaId: "",
      shippingAreaLabel: "",
      shippingProvinceName: "",
      shippingCity: "",
      shippingDistrictName: "",
      shippingPostalCode: "",
    }));
    resetShippingSelection();
  }

  function persistValidatedCheckoutItems(
    nextCheckoutItems: CartItem[],
    keysOverride?: Set<string> | null,
  ) {
    const keys = keysOverride === undefined ? checkoutItemKeys : keysOverride;
    setItems(nextCheckoutItems);

    if (keys && keys.size > 0) {
      const nextMap = new Map(nextCheckoutItems.map((item) => [cartKey(item), item]));
      const nextCart = loadCart()
        .map((item) => {
          const key = cartKey(item);
          return keys.has(key) ? nextMap.get(key) ?? null : item;
        })
        .filter((item): item is CartItem => Boolean(item));
      saveCart(nextCart);
      sessionStorage.setItem(CHECKOUT_SELECTION_KEY, JSON.stringify(nextCheckoutItems));
      setCheckoutItemKeys(new Set(nextCheckoutItems.map(cartKey)));
      return;
    }

    saveCart(nextCheckoutItems);
  }

  async function refreshCheckoutStock(
    itemsToValidate = items,
    opts: { silent?: boolean; checkoutKeys?: Set<string> | null } = {},
  ) {
    if (itemsToValidate.length === 0) {
      setStockIssues([]);
      return { ok: true, items: itemsToValidate, issues: [] as CartStockIssue[] };
    }

    if (!opts.silent) setStockRefreshing(true);
    try {
      const response = await fetch("/api/cart/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items: itemsToValidate }),
      });
      const data = (await response.json()) as {
        ok?: boolean;
        changed?: boolean;
        items?: CartItem[];
        issues?: CartStockIssue[];
      };
      if (!response.ok || !Array.isArray(data.items)) {
        throw new Error("Gagal mengecek stok terbaru.");
      }

      const issues = Array.isArray(data.issues) ? data.issues : [];
      if (data.changed) {
        persistValidatedCheckoutItems(data.items, opts.checkoutKeys);
        setSelectedRate(null);
        setPayment(null);
        setRates([]);
      }
      setStockIssues(issues);
      return { ok: issues.length === 0, items: data.items, issues };
    } catch {
      const issues = [
        {
          key: "__stock-refresh__",
          productId: "",
          variantId: null,
          variantLabel: null,
          name: "Keranjang",
          requestedQuantity: 0,
          availableStock: 0,
          action: "removed" as const,
          message: "Stok terbaru belum bisa dicek. Coba refresh sebelum membuat pesanan.",
        },
      ];
      setStockIssues(issues);
      return { ok: false, items: itemsToValidate, issues };
    } finally {
      if (!opts.silent) setStockRefreshing(false);
    }
  }

  function openCheckoutAddressList() {
    const returnTo = `${window.location.pathname}${window.location.search}`;
    router.push(`/checkout/addresses?returnTo=${encodeURIComponent(returnTo)}`);
  }

  const localSubtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const isSelfPickup = isSelfPickupMethod(selectedRate?.courier_code);
  const shippingCost = isSelfPickup ? 0 : selectedRate?.price ?? 0;
  const subtotal = checkoutPricing?.subtotal ?? localSubtotal;
  const discount = checkoutPricing?.discount ?? voucherApplied?.discount ?? 0;
  const total = checkoutPricing?.total ?? Math.max(subtotal + shippingCost - discount, 0);
  const checkoutBenefits = useMemo<CheckoutBenefit[]>(() => {
    const benefits: CheckoutBenefit[] = [];
    const customerVoucherDiscount = voucherApplied?.discount ?? 0;
    const manualVoucherDiscount = manualVoucherApplied?.discount ?? 0;

    if (customerVoucherDiscount > 0) {
      benefits.push({
        key: "customer-voucher",
        label: "Hemat Voucher",
        value: formatRupiah(customerVoucherDiscount),
        amount: customerVoucherDiscount,
      });
    }

    if (manualVoucherDiscount > 0) {
      benefits.push({
        key: "manual-voucher",
        label: "Voucher khusus",
        value: formatRupiah(manualVoucherDiscount),
        amount: manualVoucherDiscount,
      });
    }

    const unclassifiedDiscount = Math.max(
      0,
      discount - customerVoucherDiscount - manualVoucherDiscount,
    );
    if (unclassifiedDiscount > 0) {
      benefits.push({
        key: "promo-discount",
        label: "Diskon promo",
        value: formatRupiah(unclassifiedDiscount),
        amount: unclassifiedDiscount,
      });
    }

    const serverShippingFee = checkoutPricing?.shipping_fee ?? shippingCost;
    const shippingDiscount =
      selectedRate && !isSelfPickup
        ? Math.max(0, selectedRate.price - serverShippingFee)
        : 0;

    if (shippingDiscount > 0) {
      benefits.push({
        key: "shipping-discount",
        label: "Subsidi ongkir",
        value: formatRupiah(shippingDiscount),
        amount: shippingDiscount,
      });
    } else if (selectedRate && !isSelfPickup && serverShippingFee === 0 && selectedRate.price === 0) {
      benefits.push({
        key: "free-shipping",
        label: "Ongkir",
        value: "Gratis",
      });
    }

    return benefits;
  }, [
    checkoutPricing?.shipping_fee,
    discount,
    isSelfPickup,
    manualVoucherApplied?.discount,
    selectedRate,
    shippingCost,
    voucherApplied?.discount,
  ]);
  const checkoutBenefitSavings = checkoutBenefits.reduce(
    (sum, benefit) => sum + (benefit.amount ?? 0),
    0,
  );
  const checkoutBackCopy = useMemo(() => {
    if (checkoutBenefits.length === 0) {
      return {
        title: checkoutReturnTarget.title,
        message: checkoutReturnTarget.message,
      };
    }

    const onlyVoucher =
      checkoutBenefits.length === 1 &&
      (checkoutBenefits[0].key === "customer-voucher" ||
        checkoutBenefits[0].key === "manual-voucher");

    return {
      title: onlyVoucher ? "Voucher kamu masih aktif!" : "Kamu masih punya promo aktif!",
      message:
        checkoutBenefitSavings > 0
          ? `Kamu sedang hemat ${formatRupiah(checkoutBenefitSavings)} di checkout ini. Lanjutkan checkout agar benefit tidak terlewat.`
          : "Ada benefit aktif di checkout ini. Lanjutkan checkout agar benefit tidak terlewat.",
    };
  }, [checkoutBenefitSavings, checkoutBenefits, checkoutReturnTarget]);
  const totalItemCount = items.reduce((sum, item) => sum + item.quantity, 0);
  const visibleCheckoutItems = showAllCheckoutItems ? items : items.slice(0, 4);
  const hiddenCheckoutItemCount = Math.max(items.length - visibleCheckoutItems.length, 0);
  const selectedAddress = useMemo(
    () => savedAddresses.find((addr) => addr.id === selectedAddressId) ?? null,
    [savedAddresses, selectedAddressId]
  );
  const selectedShippingArea = useMemo<ShippingArea | null>(() => {
    if (!form.shippingAreaId) return null;
    return {
      area_id: form.shippingAreaId,
      label: form.shippingAreaLabel || `${form.shippingDistrictName || form.shippingCity}, ${form.shippingCity}. ${form.shippingPostalCode}`,
      province_name: form.shippingProvinceName,
      city_name: form.shippingCity,
      district_name: form.shippingDistrictName,
      postal_code: form.shippingPostalCode,
    };
  }, [
    form.shippingAreaId,
    form.shippingAreaLabel,
    form.shippingProvinceName,
    form.shippingCity,
    form.shippingDistrictName,
    form.shippingPostalCode,
  ]);
  const usingSavedAddress = addressMode === "saved" && Boolean(selectedAddress);
  const showManualAddressForm =
    !addressBookLoading && (addressMode === "manual" || savedAddresses.length === 0);
  const addressValid = Boolean(
    form.customerName.trim() &&
      form.customerPhone.trim() &&
      form.shippingAddress.trim() &&
      form.shippingPostalCode.trim() &&
      form.shippingAreaId.trim()
  );
  const addressAreaMissing = Boolean(form.shippingAddress.trim() && !form.shippingAreaId.trim());
  const canPlaceOrder = Boolean(
    items.length > 0 &&
      (isSelfPickup || addressValid) &&
      selectedRate &&
      payment &&
      total >= 0 &&
      !stockRefreshing &&
      !orderLoading &&
      // Voucher recalc gagal — discount belum di-verify server, jangan
      // allow place order sampai sync berhasil.
      !voucherSyncFailed
  );
  const primaryCtaLabel = orderLoading
    ? "Memproses..."
    : stockRefreshing
      ? "Cek stok..."
    : voucherSyncFailed
      ? "Cek koneksi & coba lagi"
    : !selectedRate
      ? "Pilih Pengiriman Dulu"
    : !isSelfPickup && !addressValid
      ? "Lengkapi Alamat"
      : !payment
          ? "Pilih Pembayaran Dulu"
          : "Buat Pesanan";

  // Checkout pricing/voucher selalu berasal dari API recalculate agar total,
  // voucher terpakai, dan daftar voucher tidak saling drift.
  function checkoutRecalculatePayload(
    customerVoucherCode: string | null,
    manualVoucherCode: string | null,
    autoApply: boolean,
  ) {
    return {
      items,
      shipping_fee: shippingCost,
      // Legacy field — backend treat sebagai customer voucher kalau
      // customerVoucherCode tidak ada. Aman untuk dikirim selalu.
      voucherCode: customerVoucherCode,
      customerVoucherCode,
      manualVoucherCode,
      autoApply,
      address: {
        areaId: form.shippingAreaId,
        postalCode: form.shippingPostalCode,
        latitude: form.shippingLatitude,
        longitude: form.shippingLongitude,
        city: form.shippingCity,
      },
      shippingMethod: {
        courierCode: isSelfPickup ? null : selectedRate?.courier_code ?? null,
        courierService: isSelfPickup ? null : selectedRate?.courier_service_code ?? null,
      },
      paymentProvider: paymentMethod,
    };
  }

  function applyCheckoutPricing(data: CheckoutRecalculateResponse) {
    // Successful server recalculation — clear failure flag.
    setVoucherSyncFailed(false);
    const eligible = Array.isArray(data.available_vouchers) ? data.available_vouchers : [];
    const ineligible = Array.isArray(data.unavailable_vouchers) ? data.unavailable_vouchers : [];
    const customerApplied = data.applied_customer_voucher ?? data.applied_voucher ?? null;
    const manualApplied = data.applied_manual_voucher ?? null;

    setCheckoutPricing({
      subtotal: data.subtotal,
      shipping_fee: data.shipping_fee,
      discount: data.discount,
      total: data.total,
    });
    setEligibleVouchers(eligible);
    setIneligibleVouchers(ineligible);

    if (customerApplied) {
      setVoucherApplied({
        code: customerApplied.code,
        discount: customerApplied.discount,
        description: customerApplied.description ?? `Hemat ${formatRupiah(customerApplied.discount)}`,
        autoApplied: customerApplied.autoApplied,
      });
      setVoucherInput(customerApplied.code);
      setForm((current) =>
        current.voucherCode === customerApplied.code
          ? current
          : { ...current, voucherCode: customerApplied.code },
      );
    } else {
      setVoucherApplied(null);
      setVoucherInput("");
      setForm((current) => (current.voucherCode ? { ...current, voucherCode: "" } : current));
    }

    if (manualApplied) {
      setManualVoucherApplied({
        code: manualApplied.code,
        discount: manualApplied.discount,
        description: manualApplied.description ?? `Hemat ${formatRupiah(manualApplied.discount)}`,
        autoApplied: false,
      });
      setForm((current) =>
        current.manualVoucherCode === manualApplied.code
          ? current
          : { ...current, manualVoucherCode: manualApplied.code },
      );
    } else {
      setManualVoucherApplied(null);
      setForm((current) =>
        current.manualVoucherCode ? { ...current, manualVoucherCode: "" } : current,
      );
    }

    setVoucherInvalidated(
      data.voucher_invalidated
        ? data.invalidated_message ?? "Voucher tidak bisa digunakan untuk pilihan ini"
        : null,
    );
  }

  async function recalculateCheckout(
    customerVoucherCode: string | null,
    manualVoucherCode: string | null,
    autoApply: boolean,
    signal?: AbortSignal,
  ) {
    const res = await fetch("/api/checkout/recalculate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(
        checkoutRecalculatePayload(customerVoucherCode, manualVoucherCode, autoApply),
      ),
      signal,
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.message ?? "Gagal menghitung ulang checkout.");
    applyCheckoutPricing(data as CheckoutRecalculateResponse);
    return data as CheckoutRecalculateResponse;
  }

  // Recalculate checkout dari satu API agar total, voucher terpakai, dan daftar voucher selalu sinkron.
  useEffect(() => {
    if (items.length === 0) {
      setCheckoutPricing(null);
      setVoucherApplied(null);
      setEligibleVouchers([]);
      setIneligibleVouchers([]);
      setVoucherInput("");
      setVoucherInvalidated(null);
      setVoucherSyncLoading(false);
      return;
    }

    const controller = new AbortController();
    setVoucherSyncLoading(true);
    recalculateCheckout(
      form.voucherCode || null,
      form.manualVoucherCode || null,
      !autoVoucherSuppressed,
      controller.signal,
    )
      .catch((err) => {
        if (err?.name !== "AbortError") {
          // Recalculation gagal — JANGAN apply stale discount client-side.
          // Voucher belum di-validate server (mis. mungkin sudah expired,
          // atau subtotal < min_order setelah user ubah cart). Clear
          // discount, flag failure → CTA disabled (lihat canPlaceOrder).
          setCheckoutPricing({
            subtotal: localSubtotal,
            shipping_fee: shippingCost,
            discount: 0,
            total: Math.max(localSubtotal + shippingCost, 0),
          });
          setVoucherSyncFailed(true);
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setVoucherSyncLoading(false);
      });

    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    items,
    localSubtotal,
    shippingCost,
    selectedRate?.courier_code,
    selectedRate?.courier_service_code,
    form.shippingPostalCode,
    form.shippingLatitude,
    form.shippingLongitude,
    form.shippingCity,
    form.voucherCode,
    form.manualVoucherCode,
    paymentMethod,
    autoVoucherSuppressed,
  ]);

  useEffect(() => {
    setAutoVoucherSuppressed(false);
  }, [
    items,
    localSubtotal,
    shippingCost,
    selectedRate?.courier_code,
    selectedRate?.courier_service_code,
    form.shippingPostalCode,
    form.shippingLatitude,
    form.shippingLongitude,
    form.shippingCity,
    paymentMethod,
  ]);

  const openBackToCartConfirmation = useCallback(() => {
    setBackConfirmOpen(true);
  }, []);

  const continueCheckout = useCallback(() => {
    setBackConfirmOpen(false);
  }, []);

  const confirmBackToCart = useCallback(() => {
    setBackConfirmOpen(false);
    returningToCartRef.current = true;
    const returnHref = checkoutReturnTarget.href;

    if (typeof window === "undefined" || window.history.length <= 1) {
      router.replace(returnHref);
      return;
    }

    let settled = false;
    const replaceCheckoutEntryWithReturnTarget = () => {
      if (settled) return;
      settled = true;
      window.removeEventListener("popstate", replaceCheckoutEntryWithReturnTarget);
      router.replace(returnHref);
    };

    window.addEventListener("popstate", replaceCheckoutEntryWithReturnTarget, { once: true });
    window.history.back();
    window.setTimeout(replaceCheckoutEntryWithReturnTarget, 350);
  }, [checkoutReturnTarget.href, router]);

  // Checkout selalu meminta konfirmasi khusus saat user mencoba back.
  // SwipeBackProvider dispatch event ini untuk gesture iOS, sementara
  // popstate di bawah menangani browser/Android back.
  useEffect(() => {
    const eventName = "checkout:back-to-cart";
    function handleCheckoutBackRequest() {
      openBackToCartConfirmation();
    }

    window.addEventListener(eventName, handleCheckoutBackRequest);
    document.body.dataset.swipeBackConfirm = "true";
    document.body.dataset.swipeBackConfirmEvent = eventName;
    document.body.dataset.swipeBackConfirmTitle = checkoutBackCopy.title;
    document.body.dataset.swipeBackConfirmMessage = checkoutBackCopy.message;

    return () => {
      window.removeEventListener(eventName, handleCheckoutBackRequest);
      delete document.body.dataset.swipeBackConfirm;
      delete document.body.dataset.swipeBackConfirmEvent;
      delete document.body.dataset.swipeBackConfirmTitle;
      delete document.body.dataset.swipeBackConfirmMessage;
    };
  }, [checkoutBackCopy.message, checkoutBackCopy.title, openBackToCartConfirmation]);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const guardState = { checkoutBackGuard: true };
    window.history.pushState(guardState, "", window.location.href);

    function handlePopState() {
      if (returningToCartRef.current) return;
      window.history.pushState(guardState, "", window.location.href);
      openBackToCartConfirmation();
    }

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, [openBackToCartConfirmation]);

  // Bersihkan pesan invalidated saat user pilih voucher baru
  function applyVoucherFromList(
    code: string,
    discount: number,
    description: string,
  ) {
    setVoucherApplied({ code, discount, description, autoApplied: false });
    setAutoVoucherSuppressed(false);
    setForm((f) => ({ ...f, voucherCode: code }));
    setVoucherInvalidated(null);
  }

  function removeVoucher() {
    setVoucherApplied(null);
    setVoucherInput("");
    setVoucherInvalidated(null);
    setAutoVoucherSuppressed(true);
    setForm((f) => ({ ...f, voucherCode: "" }));
  }

  function removeManualVoucher() {
    setManualVoucherApplied(null);
    setForm((f) => ({ ...f, manualVoucherCode: "" }));
  }

  // Input kode manual STRICT untuk voucher SELLER_MANUAL (rahasia dari
  // penjual). Voucher pembeli (CUSTOMER) HARUS dipilih lewat daftar voucher,
  // bukan via input manual — sesuai aturan: "Voucher manual hanya bisa
  // digunakan jika pembeli memasukkan kode voucher dari penjual secara
  // manual." Tidak ada auto-route ke customer slot.
  async function applyManualVoucherCode(
    code: string,
  ): Promise<{ ok: boolean; error?: string }> {
    const upperCode = code.trim().toUpperCase();
    try {
      const data = await recalculateCheckout(
        form.voucherCode || null,
        upperCode,
        !autoVoucherSuppressed,
      );

      if (data.applied_manual_voucher?.code === upperCode) {
        setVoucherInvalidated(null);
        return { ok: true };
      }

      return {
        ok: false,
        error:
          data.manual_voucher_error ??
          data.invalidated_message ??
          "Kode voucher tidak valid.",
      };
    } catch {
      return { ok: false, error: "Gagal memvalidasi kode voucher." };
    }
  }

  async function getRates() {
    if (items.length === 0) {
      setShippingError("Keranjang kosong.");
      return;
    }

    setShippingSheetOpen(true);

    if (!addressValid || !form.shippingAreaId) {
      setShippingError(
        "Kurir belum tersedia untuk alamat ini. Kamu tetap bisa memilih Ambil Sendiri di Toko tanpa ongkir."
      );
      setRates([]);
      setInstantShippingHint("");
      setRatesLoading(false);
      return;
    }

    setShippingError("");
    setInstantShippingHint("");
    setRates([]);
    setRatesLoading(true);

    try {
      const originRes = await fetch("/api/shipping/origin", {
        method: "GET",
        cache: "no-store",
      });
      const originData = await originRes.json().catch(() => ({}));

      if (!originRes.ok || originData?.configured === false) {
        setShippingError(toCustomerShippingErrorMessage(originData?.message));
        setSelectedRate(null);
        setPayment(null);
        setInstantShippingHint("");
        return;
      }

      // Format items per spec Biteship: per item dengan name, value, weight, quantity
      const biteshipItems = items.map((it) => ({
        name: it.name,
        price: it.price,
        weightGram: it.weightGram,
        quantity: it.quantity,
      }));

      const res = await fetch("/api/shipping/rates", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          destinationAreaId: form.shippingAreaId,
          destinationPostalCode: form.shippingPostalCode,
          destinationLatitude: form.shippingLatitude,
          destinationLongitude: form.shippingLongitude,
          items: biteshipItems,
        }),
      });
      const data = await res.json();

      if (!res.ok) {
        setShippingError(toCustomerShippingErrorMessage(data.message));
        setRates([]);
        setInstantShippingHint("");
      } else {
        const nextRates: RateOption[] = data.rates || [];
        setRates(nextRates);
        const instantHint =
          typeof data.instantUnavailableReason === "string"
            ? data.instantUnavailableReason
            : nextRates.some(isInstantCheckoutRate)
            ? ""
            : hasUsablePinpoint(form.shippingLatitude, form.shippingLongitude)
            ? "Gojek Instant dan Grab Instant belum tersedia untuk alamat ini."
            : "Lengkapi titik lokasi alamat agar Gojek Instant dan Grab Instant tersedia.";
        setInstantShippingHint(instantHint || "");
      }
    } catch {
      setShippingError("Gagal memuat ongkir, coba lagi.");
      setRates([]);
      setInstantShippingHint("");
    } finally {
      setRatesLoading(false);
    }
  }

  function clearCart() {
    if (checkoutItemKeys && checkoutItemKeys.size > 0) {
      const remaining = loadCart().filter((item) => !checkoutItemKeys.has(cartKey(item)));
      saveCart(remaining);
      sessionStorage.removeItem(CHECKOUT_SELECTION_KEY);
    } else {
      void clearCartEverywhere();
    }
    sessionStorage.removeItem(CHECKOUT_DRAFT_KEY);
    sessionStorage.removeItem(CHECKOUT_SELECTED_ADDRESS_KEY);
    sessionStorage.removeItem(CHECKOUT_ADDRESS_FORCE_APPLY_KEY);
    setItems([]);
  }

  async function handleOrder(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (items.length === 0) {
      setError("Keranjang kosong.");
      return;
    }

    const stockResult = await refreshCheckoutStock(items);
    if (!stockResult.ok) {
      setError(
        "Stok beberapa produk berubah. Jumlah keranjang sudah diperbarui, mohon cek ulang sebelum membuat pesanan.",
      );
      return;
    }

    if (!selectedRate) {
      setError("Pilih metode pengiriman terlebih dahulu.");
      return;
    }

    if (!isSelfPickup && !addressValid) {
      setError("Pilih atau lengkapi alamat pengiriman terlebih dahulu.");
      return;
    }

    if (!isSelfPickup && !form.shippingAreaId) {
      setError("Alamat pengiriman belum valid. Mohon pilih ulang kota/kecamatan dari daftar alamat.");
      return;
    }

    if (!payment) {
      setError("Pilih metode pembayaran terlebih dahulu.");
      return;
    }

    setOrderLoading(true);
    const res = await fetch("/api/orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...form,
        orderType: isSelfPickup ? SELF_PICKUP_METHOD : DELIVERY_METHOD,
        shippingMethod: isSelfPickup ? SELF_PICKUP_METHOD : DELIVERY_METHOD,
        shippingAddress: isSelfPickup ? SELF_PICKUP_STORE.address : form.shippingAddress,
        shippingCity: isSelfPickup ? "Medan Kota" : form.shippingCity,
        shippingPostalCode: isSelfPickup ? "" : form.shippingPostalCode,
        shippingAreaId: isSelfPickup ? SELF_PICKUP_METHOD : form.shippingAreaId,
        shippingAreaLabel: isSelfPickup ? SELF_PICKUP_STORE.name : form.shippingAreaLabel,
        paymentProvider: payment.provider,
        manualBank: payment.provider === "MANUAL" ? payment.bank : undefined,
        items,
        shippingCost,
        courierCode: isSelfPickup ? undefined : selectedRate?.courier_code,
        courierService: isSelfPickup ? undefined : selectedRate?.courier_service_code,
        shippingLatitude: isSelfPickup ? SELF_PICKUP_STORE.latitude : form.shippingLatitude,
        shippingLongitude: isSelfPickup ? SELF_PICKUP_STORE.longitude : form.shippingLongitude,
        shippingPinpointAddress: isSelfPickup ? null : form.shippingPinpointAddress,
      }),
    });

    const data = await res.json();
    setOrderLoading(false);

    if (!res.ok) {
      setError(data.message || "Gagal membuat order.");
      return;
    }

    const detailUrl =
      data.detailUrl ||
      `/pesanan/${encodeURIComponent(data.orderNumber)}${
        data.trackingToken ? `?token=${encodeURIComponent(data.trackingToken)}` : ""
      }`;
    const [detailPath, detailQuery] = detailUrl.split("?");
    const orderCreatedUrl = `${detailPath.replace(/\/$/, "")}/success${
      detailQuery ? `?${detailQuery}` : ""
    }`;

    // Simpan alamat ke buku alamat (best-effort, jangan ganggu flow)
    if (isLoggedIn && saveToAddressBook && form.shippingAddress && !isSelfPickup) {
      void fetch("/api/alamat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: addressLabel.trim() || "Rumah",
          recipient: form.customerName,
          phone: form.customerPhone,
          address: form.shippingAddress,
          city: form.shippingCity || null,
          postalCode: form.shippingPostalCode || "",
          areaId: form.shippingAreaId,
          areaLabel: form.shippingAreaLabel,
          provinceName: form.shippingProvinceName,
          cityName: form.shippingCity,
          districtName: form.shippingDistrictName,
          latitude: form.shippingLatitude,
          longitude: form.shippingLongitude,
          pinpointAddress: form.shippingPinpointAddress,
          isMain: savedAddresses.length === 0,
        }),
      }).catch(() => {});
    }

    if (paymentMethod === "MIDTRANS" && data.snapToken && window.snap) {
      window.snap.pay(data.snapToken, {
        onSuccess: () => {
          clearCart();
          router.push(orderCreatedUrl);
        },
        onPending: () => {
          clearCart();
          router.push(orderCreatedUrl);
        },
        onError: () => {
          setError("Pembayaran gagal. Silakan coba lagi.");
        },
        onClose: () => {
          setError("Pembayaran dibatalkan. Order tetap tersimpan dan bisa dibuka dari detail pesanan.");
          clearCart();
          router.push(orderCreatedUrl);
        },
      });
      return;
    }

    clearCart();
    router.push(orderCreatedUrl);
  }

  function field(
    label: string,
    key: keyof typeof form,
    opts?: { required?: boolean; type?: string; placeholder?: string; textarea?: boolean }
  ) {
    const cls =
      "mt-1 block w-full rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600";
    const shouldResetCheckout =
      key === "shippingAddress" ||
      key === "shippingCity" ||
      key === "shippingPostalCode" ||
      key === "shippingLatitude" ||
      key === "shippingLongitude" ||
      key === "shippingPinpointAddress" ||
      key === "shippingAreaId" ||
      key === "shippingAreaLabel" ||
      key === "shippingProvinceName" ||
      key === "shippingDistrictName";
    function updateField(value: string) {
      setForm({ ...form, [key]: value });
      if (shouldResetCheckout) {
        setSelectedRate(null);
        setPayment(null);
        setRates([]);
      }
    }

    return (
      <div>
        <label className="block text-sm font-medium text-zinc-700">
          {label}
          {opts?.required && <span className="ml-1 text-red-500">*</span>}
        </label>
        {opts?.textarea ? (
          <textarea
            rows={3}
            required={opts.required}
            placeholder={opts.placeholder}
            value={String(form[key] ?? "")}
            onChange={(e) => updateField(e.target.value)}
            className={cls}
          />
        ) : (
          <input
            type={opts?.type ?? "text"}
            required={opts?.required}
            placeholder={opts?.placeholder}
            value={String(form[key] ?? "")}
            onChange={(e) => updateField(e.target.value)}
            className={cls}
          />
        )}
      </div>
    );
  }

  const isProduction = process.env.NEXT_PUBLIC_MIDTRANS_IS_PRODUCTION === "true";
  const snapScriptUrl = isProduction
    ? "https://app.midtrans.com/snap/snap.js"
    : "https://app.sandbox.midtrans.com/snap/snap.js";

  return (
    <>
      {isMidtransEnabled && (
        <Script
          src={snapScriptUrl}
          data-client-key={process.env.NEXT_PUBLIC_MIDTRANS_CLIENT_KEY}
          strategy="lazyOnload"
        />
      )}

      <header className="sticky top-0 z-[1050] border-b border-slate-200/80 bg-white shadow-[0_8px_24px_rgba(15,23,42,0.06)] [padding-top:env(safe-area-inset-top)]">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-3 px-3 lg:px-4">
          <button
            type="button"
            onClick={openBackToCartConfirmation}
            aria-label={checkoutReturnTarget.ariaLabel}
            className="-ml-1 grid h-10 w-10 shrink-0 place-items-center rounded-full text-zinc-900 transition active:bg-zinc-100"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </button>
          <h1 className="min-w-0 flex-1 truncate text-base font-black text-zinc-950">
            Checkout
          </h1>
          <span aria-hidden className="h-10 w-10 shrink-0" />
        </div>
      </header>

      <div className="mx-auto max-w-6xl gap-8 px-3 py-3 pb-32 lg:grid lg:grid-cols-[1fr_360px] lg:px-4 lg:py-10 lg:pb-10">
        <div>
          <form id="checkout-form" onSubmit={handleOrder} className="space-y-3 lg:space-y-4">
            <section className={`overflow-hidden rounded-2xl border border-zinc-100 bg-white shadow-sm ${addressMode === "select" ? "hidden" : ""}`}>
              {addressBookLoading ? (
                <div className="px-4 py-3 text-sm font-semibold text-zinc-500">
                  Memuat alamat tersimpan...
                </div>
              ) : usingSavedAddress && selectedAddress ? (
                <button
                  type="button"
                  onClick={openCheckoutAddressList}
                  className="flex w-full items-start gap-3 p-3 text-left transition active:bg-zinc-50"
                >
                  <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-natalo-50 text-natalo-600">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4">
                      <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
                      <circle cx="12" cy="10" r="3" />
                    </svg>
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold text-zinc-500">Alamat Pengiriman</p>
                    <p className="mt-0.5 truncate text-sm font-black text-zinc-950">
                      <span className="text-natalo-700">{selectedAddress.label}</span>
                      {" • "}
                      {selectedAddress.recipientName}
                    </p>
                    <p className="mt-0.5 truncate text-xs text-zinc-500">
                      {selectedAddress.address}
                    </p>
                    <p className="mt-0.5 truncate text-xs font-semibold text-zinc-500">
                      {selectedAddress.areaLabel || `${selectedAddress.city} ${selectedAddress.postalCode}`}
                    </p>
                  </div>
                  <span className="shrink-0 self-center text-xs font-black text-natalo-600">
                    Ubah ›
                  </span>
                </button>
              ) : (
                <div className="px-4 py-3">
                  <p className="text-sm font-black text-zinc-950">Alamat Pengiriman</p>
                  <p className="mt-0.5 text-xs text-zinc-500">
                    Lengkapi alamat untuk lanjut ke pengiriman.
                  </p>
                </div>
              )}

              {!addressBookLoading && !usingSavedAddress && isLoggedIn && (
                <div className="border-t border-zinc-100 px-4 pb-3">
                  <button
                    type="button"
                    onClick={openCheckoutAddressList}
                    className="w-full rounded-2xl border border-natalo-200 bg-natalo-50 px-4 py-3 text-sm font-black text-natalo-700 transition hover:border-natalo-300 hover:bg-natalo-100"
                  >
                    Pilih alamat tersimpan
                  </button>
                  </div>
              )}

              {addressBookError && (
                <div className="border-t border-zinc-100 bg-amber-50 px-4 py-2 text-xs font-semibold text-amber-700">
                  {addressBookError}
                </div>
              )}
              {usingSavedAddress && addressAreaMissing && (
                <div className="border-t border-amber-100 bg-amber-50 px-4 py-3">
                  <p className="text-xs font-bold text-amber-800">
                    Alamat tersimpan belum punya Area ID Biteship. Mohon ubah alamat dan pilih kota/kecamatan dari daftar.
                  </p>
                  <button
                    type="button"
                    onClick={openCheckoutAddressList}
                    className="mt-2 rounded-full bg-amber-600 px-4 py-2 text-xs font-black text-white"
                  >
                    Ubah Alamat
                  </button>
                </div>
              )}
            </section>

            {/* Pilih alamat tersimpan */}
            {false && addressMode === "select" && savedAddresses.length > 0 && (
              <div>
                <div className="flex items-center justify-between">
                  <p className="text-sm font-bold text-zinc-900">Pilih Alamat</p>
                  {selectedAddress && (
                    <button
                      type="button"
                      onClick={() => setAddressMode("saved")}
                      className="text-xs font-bold text-zinc-500 hover:underline"
                    >
                      Batal
                    </button>
                  )}
                </div>
                <div className="mt-2 space-y-2">
                  {savedAddresses.map((addr) => (
                    <div
                      key={addr.id}
                      className={`relative rounded-2xl border text-sm transition ${
                        selectedAddressId === addr.id
                          ? "border-natalo-500 bg-natalo-50"
                          : "border-zinc-200 hover:border-zinc-400"
                      }`}
                    >
                      <button
                        type="button"
                        onClick={() => {
                          setSelectedAddressId(addr.id);
                          applyAddressToForm(addr);
                          setAddressMode("saved");
                        }}
                        className="block w-full p-4 pr-16 text-left"
                      >
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-zinc-900">{addr.label}</span>
                          {addr.isMain && (
                            <span className="rounded-full bg-natalo-100 px-2 py-0.5 text-xs font-bold text-natalo-700">
                              Utama
                            </span>
                          )}
                          {selectedAddressId === addr.id && (
                            <span className="text-xs font-bold text-natalo-600">Dipilih</span>
                          )}
                        </div>
                        <p className="mt-1 text-zinc-600">{addr.recipientName} · {addr.phone}</p>
                        <p className="mt-0.5 text-zinc-400 line-clamp-1">{addr.address}, {addr.city} {addr.postalCode}</p>
                        {addr.streetName && (
                          <p className="mt-2 text-xs font-bold text-natalo-700">{addr.streetName}</p>
                        )}
                        {addr.pinpointAddress && (
                          <p className="mt-2 rounded-xl bg-natalo-50 px-3 py-2 text-xs font-semibold text-natalo-800 line-clamp-2">
                            Pinpoint: {addr.pinpointAddress}
                          </p>
                        )}
                      </button>
                      <Link
                        href={`/akun/alamat/edit/${addr.id}`}
                        className="absolute right-3 top-3 rounded-full bg-white px-3 py-1 text-xs font-bold text-natalo-600 ring-1 ring-natalo-200 hover:bg-natalo-50"
                      >
                        Edit
                      </Link>
                    </div>
                  ))}
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setAddressMode("manual");
                    setSelectedAddressId("");
                    setSelectedRate(null);
                    setPayment(null);
                    setRates([]);
                  }}
                  className="mt-3 w-full rounded-2xl border border-dashed border-natalo-300 bg-white p-4 text-center text-sm font-black text-natalo-700 transition hover:bg-natalo-50"
                >
                  + Tambah Alamat Baru
                </button>
              </div>
            )}

            {showManualAddressForm && (
              <>
                {savedAddresses.length > 0 && (
                  <button
                    type="button"
                    onClick={openCheckoutAddressList}
                    className="text-xs font-black text-natalo-600 hover:underline"
                  >
                    Pakai alamat tersimpan
                  </button>
                )}

                {field("Nama lengkap", "customerName", { required: true, placeholder: "Nama penerima" })}
                {field("Nomor WhatsApp", "customerPhone", { required: true, type: "tel", placeholder: "08123..." })}
                {field("Email", "customerEmail", { type: "email", placeholder: "Opsional" })}
                {field("Alamat lengkap", "shippingAddress", {
                  required: true,
                  placeholder: "Jalan, RT/RW, Kelurahan, Kecamatan...",
                  textarea: true,
                })}

                <div className="space-y-3">
                  <BiteshipAreaCombobox
                    selectedArea={selectedShippingArea}
                    onSelect={selectShippingArea}
                    onClear={clearShippingArea}
                    label="Kota / Kecamatan"
                    error={addressAreaMissing ? "Mohon pilih kota/kecamatan dari daftar alamat." : undefined}
                    help="Pilih hasil dari Biteship agar kota/kecamatan dan kode pos cocok."
                  />
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div className="rounded-2xl border border-zinc-200 bg-zinc-50 px-4 py-3">
                      <p className="text-xs font-bold text-zinc-500">Kota / Kabupaten</p>
                      <p className="mt-1 text-sm font-black text-zinc-900">
                        {form.shippingCity || "Belum dipilih"}
                      </p>
                    </div>
                    <div className="rounded-2xl border border-zinc-200 bg-zinc-50 px-4 py-3">
                      <p className="text-xs font-bold text-zinc-500">Kode pos</p>
                      <p className="mt-1 text-sm font-black text-zinc-900">
                        {form.shippingPostalCode || "Belum dipilih"}
                      </p>
                    </div>
                  </div>
                </div>
              </>
            )}

            {/* Simpan ke buku alamat (login only) */}
            {isLoggedIn && showManualAddressForm && (
              <div className="rounded-2xl border border-zinc-200 bg-zinc-50 p-3">
                <label className="flex items-start gap-2 text-sm text-zinc-700">
                  <input
                    type="checkbox"
                    checked={saveToAddressBook}
                    onChange={(e) => setSaveToAddressBook(e.target.checked)}
                    className="mt-0.5 h-4 w-4 rounded border-zinc-300"
                  />
                  <span>
                    <span className="font-bold">Simpan alamat ini</span> supaya checkout berikutnya lebih cepat.
                  </span>
                </label>
                {saveToAddressBook && (
                  <input
                    type="text"
                    value={addressLabel}
                    onChange={(e) => setAddressLabel(e.target.value)}
                    placeholder="Label alamat (Rumah, Kantor, dll) - opsional"
                    className="mt-2 block w-full rounded-2xl border border-zinc-300 px-4 py-2.5 text-sm outline-none focus:border-zinc-600"
                  />
                )}
              </div>
            )}

            {/* Ringkasan produk — di atas pengiriman supaya user bisa cek dulu */}
            <section className="rounded-2xl border border-zinc-100 bg-white p-3 shadow-sm">
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-black text-zinc-950">Ringkasan Produk</p>
                <p className="text-xs text-zinc-500">
                  {totalItemCount} item
                </p>
              </div>

              <div className="mt-3 space-y-3">
                {items.length > 0 ? (
                  visibleCheckoutItems.map((item) => (
                    <div key={cartKey(item)} className="flex items-center gap-3">
                      <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-xl bg-zinc-100">
                        <Image
                          src={item.imageUrl || "/logo.png"}
                          alt={item.name}
                          fill
                          sizes="48px"
                          className={item.imageUrl ? "object-cover" : "object-contain p-2"}
                        />
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="line-clamp-2 text-sm font-bold text-zinc-950">{item.name}</p>
                        <p className="mt-0.5 text-xs font-semibold text-zinc-500">
                          Qty {item.quantity}
                        </p>
                      </div>
                      <p className="shrink-0 text-sm font-black text-zinc-950">
                        {formatRupiah(item.price * item.quantity)}
                      </p>
                    </div>
                  ))
                ) : (
                  <p className="rounded-2xl bg-zinc-50 px-4 py-3 text-sm font-semibold text-zinc-500">
                    Keranjang kosong.
                  </p>
                )}
              </div>

              {hiddenCheckoutItemCount > 0 && (
                <button
                  type="button"
                  onClick={() => setShowAllCheckoutItems(true)}
                  className="mt-3 w-full rounded-xl border border-zinc-100 py-2 text-center text-xs font-black text-natalo-600 transition hover:bg-natalo-50"
                >
                  Lihat semua item ({hiddenCheckoutItemCount} lagi) ›
                </button>
              )}
              {showAllCheckoutItems && items.length > 4 && (
                <button
                  type="button"
                  onClick={() => setShowAllCheckoutItems(false)}
                  className="mt-3 w-full rounded-xl border border-zinc-100 py-2 text-center text-xs font-black text-zinc-500 transition hover:bg-zinc-50"
                >
                  Sembunyikan
                </button>
              )}
            </section>

            {stockIssues.length > 0 && (
              <section className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3">
                <p className="text-sm font-black text-amber-900">Stok produk berubah</p>
                <div className="mt-1 space-y-1">
                  {stockIssues.slice(0, 3).map((issue) => (
                    <p key={issue.key} className="text-xs font-semibold text-amber-800">
                      {issue.message}
                    </p>
                  ))}
                </div>
                <p className="mt-2 text-xs font-semibold text-amber-700">
                  Cek ringkasan produk lalu klik buat pesanan lagi jika sudah sesuai.
                </p>
              </section>
            )}

            {/* Pengiriman: tombol ke bottom sheet — setelah ringkasan */}
            <div>
              <label className="block text-sm font-medium text-zinc-700">
                Metode Pengiriman
              </label>
              {selectedRate ? (
                <div className="mt-1 rounded-2xl border border-natalo-300 bg-natalo-50 p-3">
                  <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-bold text-zinc-950">
                      {isSelfPickup
                        ? "Ambil Sendiri di Toko"
                        : `${selectedRate.courier_name} ${selectedRate.courier_service_name}`}
                    </p>
                    <p className="mt-0.5 truncate text-xs text-zinc-500">
                      {formatShippingDuration(selectedRate.duration)} · {formatRupiah(selectedRate.price)}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={getRates}
                    className="shrink-0 text-xs font-bold text-natalo-700 hover:underline"
                  >
                    Ganti ›
                  </button>
                  </div>
                  {isSelfPickup && (
                    <div className="mt-3 rounded-2xl bg-white p-4 text-sm text-zinc-700">
                      <p className="text-xs font-black text-zinc-500">Detail Pengambilan</p>
                      <p className="mt-3 font-black text-zinc-950">Lokasi Toko</p>
                      <p className="mt-1 font-semibold">{SELF_PICKUP_STORE.name}</p>
                      <p>{SELF_PICKUP_STORE.addressLine}</p>
                      <p>{SELF_PICKUP_STORE.area}</p>
                      <p className="mt-3 font-black text-zinc-950">Jam Ambil</p>
                      <p>{SELF_PICKUP_STORE.hours}</p>
                      <a
                        href={buildSelfPickupMapsUrl()}
                        target="_blank"
                        rel="noreferrer"
                        className="mt-3 inline-flex w-full justify-center rounded-full border border-blue-200 px-4 py-2.5 text-xs font-black text-blue-700 hover:bg-blue-50"
                      >
                        Buka di Google Maps
                      </a>
                    </div>
                  )}
                </div>
              ) : (
                <button
                  type="button"
                  onClick={getRates}
                  disabled={ratesLoading}
                  className="mt-1 flex w-full items-center justify-between rounded-2xl border border-zinc-200 bg-white p-3 text-left transition hover:border-natalo-300 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <span className="text-sm font-medium text-zinc-700">
                    {ratesLoading ? "Memuat ongkir..." : "Pilih metode pengiriman"}
                  </span>
                  {!ratesLoading && (
                    <span className="text-zinc-400">›</span>
                  )}
                </button>
              )}
              {shippingError && (
                <p className="mt-2 text-xs text-red-500">{shippingError}</p>
              )}
            </div>

            {/* Voucher — smart picker dengan bottom sheet. Mendukung 2
                slot: 1 voucher pembeli (CUSTOMER) + 1 voucher manual
                penjual (SELLER_MANUAL). */}
            <CheckoutVoucherCard
              applied={voucherApplied}
              manualApplied={manualVoucherApplied}
              eligible={eligibleVouchers}
              ineligible={ineligibleVouchers}
              invalidatedMessage={voucherInvalidated}
              loading={voucherSyncLoading}
              onApply={applyVoucherFromList}
              onRemove={removeVoucher}
              onRemoveManual={removeManualVoucher}
              onApplyManualCode={applyManualVoucherCode}
            />

            {/* Catatan compact */}
            <div>
              <label className="block text-sm font-medium text-zinc-700">Catatan pesanan</label>
              <input
                type="text"
                placeholder="Opsional"
                value={form.notes}
                onChange={(e) => setForm({ ...form, notes: e.target.value })}
                className="mt-1 block w-full rounded-2xl border border-zinc-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-zinc-600"
              />
            </div>

            {/* Metode pembayaran */}
            <div>
              <p className="text-sm font-medium text-zinc-700">Metode pembayaran</p>
              {selectedRate ? (
              <div className="mt-2 space-y-2">
                <button
                  type="button"
                  onClick={() => setPayment({ provider: "MANUAL", bank: "BCA_NATASHA" })}
                  className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                    paymentMethod === "MANUAL" ? "border-zinc-950 bg-zinc-50" : "border-zinc-200"
                  }`}
                >
                  <p className="font-semibold">Transfer Manual</p>
                  <p className="text-zinc-500">BCA · No. rek & instruksi tampil setelah order dibuat</p>
                </button>

                {isMidtransEnabled && (
                  <button
                    type="button"
                    onClick={() => setPayment({ provider: "MIDTRANS" })}
                    className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                      paymentMethod === "MIDTRANS" ? "border-zinc-950 bg-zinc-50" : "border-zinc-200"
                    }`}
                  >
                    <p className="font-semibold">Midtrans</p>
                    <p className="text-zinc-500">Transfer bank, QRIS, GoPay, OVO, dan lainnya</p>
                  </button>
                )}
              </div>
              ) : (
                <div className="mt-2 rounded-2xl border border-dashed border-zinc-200 bg-zinc-50 px-4 py-3 text-sm font-semibold text-zinc-500">
                  Pilih pengiriman dulu untuk membuka metode pembayaran.
                </div>
              )}
            </div>
          </form>
        </div>

        <aside className="h-fit rounded-3xl bg-zinc-50 p-5">
          <p className="font-bold text-zinc-950">Rincian Pembayaran</p>

          <div className="mt-4 space-y-2 text-sm">
            <div className="flex justify-between text-zinc-600">
              <span>Subtotal produk</span>
              <span>{formatRupiah(subtotal)}</span>
            </div>
            <div className="flex justify-between text-zinc-600">
              <span>Ongkos kirim</span>
              {selectedRate ? (
                <span>{isSelfPickup ? "Rp0 (Gratis)" : formatRupiah(shippingCost)}</span>
              ) : (
                <span className="italic text-zinc-400">Belum dipilih</span>
              )}
            </div>
            {voucherApplied && (
              <div className="flex justify-between font-semibold text-green-600">
                <span>Diskon voucher</span>
                <span>-{formatRupiah(discount)}</span>
              </div>
            )}
            <div className="flex justify-between text-lg font-black text-zinc-950">
              <span>Total bayar</span>
              <span>{selectedRate ? formatRupiah(total) : formatRupiah(subtotal) + " + ongkir"}</span>
            </div>
          </div>

          {error && (
            <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
          )}

          {paymentMethod === "MANUAL" && (
            <p className="mt-4 text-center text-xs text-zinc-400">
              Instruksi transfer akan tampil setelah order dibuat.
            </p>
          )}
        </aside>
      </div>

      {/* Bottom sheet pilih pengiriman */}
      <MetodePengiriman
        open={shippingSheetOpen}
        onClose={() => setShippingSheetOpen(false)}
        rates={rates}
        loading={ratesLoading}
        error={shippingError || undefined}
        selected={selectedRate}
        instantUnavailableReason={instantShippingHint || undefined}
        onSelect={(r) => {
          setSelectedRate(r as RateOption);
          setShippingError("");
        }}
      />

      <BottomSheet
        open={backConfirmOpen}
        onClose={continueCheckout}
        footer={
          <div className="grid gap-2 sm:grid-cols-2">
            <button
              type="button"
              onClick={continueCheckout}
              className="flex h-12 items-center justify-center rounded-full bg-natalo-600 px-5 text-sm font-black text-white transition hover:bg-natalo-700 active:scale-[0.98]"
            >
              Lanjut Checkout
            </button>
            <button
              type="button"
              onClick={confirmBackToCart}
              className="flex h-12 items-center justify-center rounded-full border border-zinc-200 bg-white px-5 text-sm font-black text-zinc-700 transition hover:bg-zinc-50 active:scale-[0.98]"
            >
              {checkoutReturnTarget.buttonLabel}
            </button>
          </div>
        }
      >
        <div className="space-y-5">
          <div className="flex items-start gap-3">
            <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-natalo-50 text-natalo-600">
              <FiGift className="h-5 w-5" aria-hidden="true" />
            </span>
            <div className="min-w-0">
              <h2 className="text-lg font-black text-zinc-950">
                {checkoutBackCopy.title}
              </h2>
              <p className="mt-1 text-sm leading-6 text-zinc-500">
                {checkoutBackCopy.message}
              </p>
            </div>
          </div>

          {checkoutBenefits.length > 0 && (
            <div className="rounded-2xl border border-natalo-100 bg-natalo-50/70 p-4">
              <div className="space-y-3">
                {checkoutBenefits.map((benefit) => (
                  <div
                    key={benefit.key}
                    className="flex items-center justify-between gap-4 text-sm"
                  >
                    <span className="font-semibold text-zinc-600">{benefit.label}</span>
                    <span className="shrink-0 font-black text-natalo-700">
                      {benefit.value}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </BottomSheet>

      {/* Mobile sticky bottom CTA */}
      {items.length > 0 && (
        <div className="keyboard-hide-on-focus fixed inset-x-0 bottom-0 z-40 border-t border-zinc-200 bg-white px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.06)] md:hidden [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
          <div className="flex items-center gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-xs text-zinc-500">
                Total
              </p>
              <p className="truncate text-base font-black text-zinc-950">
                {selectedRate ? formatRupiah(total) : `${formatRupiah(subtotal)} + ongkir`}
              </p>
            </div>
            <button
              type="submit"
              form="checkout-form"
              disabled={!canPlaceOrder}
              className="flex h-12 shrink-0 items-center justify-center rounded-full bg-natalo-600 px-6 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300 disabled:text-zinc-500"
            >
              {primaryCtaLabel}
            </button>
          </div>
        </div>
      )}
    </>
  );
}
