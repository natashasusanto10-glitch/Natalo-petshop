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
      <span
        aria-hidden="true"
        className="pointer-events-none absolute left-[20%] top-[14%] text-[18px] text-[#FF8FA3] opacity-0 drop-shadow-sm [animation:wishlist-heart-float_1.9s_ease-in-out_infinite]"
      >
        ♥
      </span>
      <span
        aria-hidden="true"
        className="pointer-events-none absolute right-[19%] top-[12%] text-[22px] text-[#FF8FA3] opacity-0 drop-shadow-sm [animation:wishlist-heart-float_2.15s_ease-in-out_0.45s_infinite]"
      >
        ♥
      </span>
      <span
        aria-hidden="true"
        className="pointer-events-none absolute right-[8%] top-[34%] text-[13px] text-[#FF8FA3] opacity-0 drop-shadow-sm [animation:wishlist-heart-float_1.8s_ease-in-out_0.9s_infinite]"
      >
        ♥
      </span>
      <style jsx>{`
        @keyframes wishlist-heart-float {
          0% {
            opacity: 0;
            transform: translate3d(0, 8px, 0) scale(0.86);
          }
          22% {
            opacity: 0.95;
            transform: translate3d(0, 0, 0) scale(1);
          }
          58% {
            opacity: 0.9;
            transform: translate3d(0, -8px, 0) scale(1.03);
          }
          100% {
            opacity: 0;
            transform: translate3d(0, -16px, 0) scale(0.92);
          }
        }
      `}</style>
    </div>
  );
}
