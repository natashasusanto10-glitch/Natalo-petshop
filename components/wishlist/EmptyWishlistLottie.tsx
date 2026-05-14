"use client";

import Image from "next/image";

const WISHLIST_IMAGE_SRC = "/assets/images/empty_wishlist_pets_fullcolor.png";

export function EmptyWishlistLottie() {
  return (
    <div className="relative mx-auto mb-5 aspect-[5/3] w-full max-w-[310px] overflow-visible">
      <Image
        src={WISHLIST_IMAGE_SRC}
        alt=""
        width={956}
        height={574}
        priority={false}
        className="h-full w-full object-contain"
        aria-hidden="true"
      />
    </div>
  );
}
