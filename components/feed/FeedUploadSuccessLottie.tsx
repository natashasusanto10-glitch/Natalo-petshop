"use client";

export function FeedUploadSuccessLottie() {
  return (
    <div
      className="relative mx-auto h-[260px] w-full max-w-[320px]"
      aria-hidden="true"
    >
      <svg
        viewBox="0 0 320 280"
        role="img"
        className="h-full w-full overflow-visible"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <filter
            id="feed-success-soft-glow"
            x="-30%"
            y="-30%"
            width="160%"
            height="160%"
            colorInterpolationFilters="sRGB"
          >
            <feGaussianBlur stdDeviation="6" result="blur" />
            <feColorMatrix
              in="blur"
              type="matrix"
              values="0 0 0 0 0.12 0 0 0 0 0.37 0 0 0 0 0.75 0 0 0 0.55 0"
            />
            <feBlend in="SourceGraphic" in2="blur" mode="normal" />
          </filter>
          <radialGradient id="dog-fur" cx="0" cy="0" r="1" gradientTransform="matrix(70 82 -85 72 196 142)">
            <stop stopColor="#FFE0A0" />
            <stop offset="0.62" stopColor="#F7B856" />
            <stop offset="1" stopColor="#D88A33" />
          </radialGradient>
          <linearGradient id="cloud-grad" x1="72" y1="96" x2="218" y2="190">
            <stop stopColor="#081827" />
            <stop offset="1" stopColor="#102C55" />
          </linearGradient>
          <linearGradient id="blue-grad" x1="119" y1="132" x2="165" y2="181">
            <stop stopColor="#2587FF" />
            <stop offset="1" stopColor="#1E5FBF" />
          </linearGradient>
          <linearGradient id="check-grad" x1="88" y1="38" x2="132" y2="84">
            <stop stopColor="#95E26A" />
            <stop offset="1" stopColor="#46B543" />
          </linearGradient>
        </defs>

        <ellipse cx="183" cy="236" rx="88" ry="13" fill="#04101F" opacity="0.92" />

        <path
          d="M79 181h122c28 0 51-22 51-49 0-26-21-47-47-49-12-30-42-50-76-45-30 5-53 28-58 57-26 5-45 23-45 45 0 23 22 41 53 41Z"
          fill="url(#cloud-grad)"
          stroke="#1D4D90"
          strokeWidth="5"
          filter="url(#feed-success-soft-glow)"
        />
        <path
          d="M140 176v-47m0 0-24 24m24-24 24 24"
          stroke="url(#blue-grad)"
          strokeWidth="14"
          strokeLinecap="round"
          strokeLinejoin="round"
        />

        <circle cx="100" cy="64" r="32" fill="#173D24" opacity="0.8" />
        <circle cx="100" cy="64" r="24" fill="url(#check-grad)" />
        <path
          d="m87 63 10 10 18-22"
          stroke="white"
          strokeWidth="8"
          strokeLinecap="round"
          strokeLinejoin="round"
        />

        <g fill="#1E5FBF" opacity="0.92">
          <circle cx="45" cy="118" r="7" />
          <circle cx="60" cy="105" r="6" />
          <circle cx="73" cy="118" r="7" />
          <path d="M58 122c11 0 20 10 15 19-4 7-11 3-15 3s-11 4-15-3c-5-9 4-19 15-19Z" />
          <circle cx="260" cy="82" r="6" />
          <circle cx="274" cy="72" r="5" />
          <circle cx="286" cy="83" r="6" />
          <path d="M273 87c10 0 18 8 14 16-4 6-10 3-14 3s-10 3-14-3c-4-8 4-16 14-16Z" />
        </g>

        <g fill="#FDBA3B">
          <path d="M36 82c8-2 12-6 14-14 2 8 6 12 14 14-8 2-12 6-14 14-2-8-6-12-14-14Z" />
          <path d="M274 134c7-2 11-6 13-13 2 7 6 11 13 13-7 2-11 6-13 13-2-7-6-11-13-13Z" />
          <path d="M43 190c7-2 11-6 13-13 2 7 6 11 13 13-7 2-11 6-13 13-2-7-6-11-13-13Z" />
        </g>

        <g filter="url(#feed-success-soft-glow)">
          <path
            d="M248 183c20 2 32 19 28 38-18-3-31-16-32-33"
            fill="#E89D3F"
            stroke="#A65C20"
            strokeWidth="4"
            strokeLinecap="round"
          />
          <ellipse cx="191" cy="189" rx="51" ry="58" fill="url(#dog-fur)" stroke="#A65C20" strokeWidth="4" />
          <path d="M155 139c-25-2-39 21-36 44 22 0 38-13 44-33" fill="#D88A33" stroke="#A65C20" strokeWidth="4" />
          <path d="M226 139c25-2 39 21 36 44-22 0-38-13-44-33" fill="#D88A33" stroke="#A65C20" strokeWidth="4" />
          <circle cx="191" cy="126" r="47" fill="url(#dog-fur)" stroke="#A65C20" strokeWidth="4" />
          <path d="M170 88c10-10 30-9 42 0-8-4-32-4-42 0Z" fill="#FFE3A8" opacity="0.9" />
          <circle cx="174" cy="123" r="6" fill="#151515" />
          <circle cx="210" cy="123" r="6" fill="#151515" />
          <circle cx="176" cy="121" r="2" fill="white" />
          <circle cx="212" cy="121" r="2" fill="white" />
          <ellipse cx="192" cy="139" rx="11" ry="8" fill="#171717" />
          <path d="M192 147c-4 12-18 15-27 5" stroke="#7A3A1C" strokeWidth="4" strokeLinecap="round" />
          <path d="M192 147c4 12 18 15 27 5" stroke="#7A3A1C" strokeWidth="4" strokeLinecap="round" />
          <path d="M185 157c5 17 23 17 25 0-7 3-16 3-25 0Z" fill="#F46D6D" />
          <ellipse cx="157" cy="143" rx="9" ry="6" fill="#FF9E8D" opacity="0.6" />
          <ellipse cx="225" cy="143" rx="9" ry="6" fill="#FF9E8D" opacity="0.6" />
          <path d="M158 233c-8-18 0-37 18-38 16 5 15 27 9 38" fill="#F4AE4B" stroke="#A65C20" strokeWidth="4" />
          <path d="M202 233c-8-18 0-37 18-38 16 5 15 27 9 38" fill="#F4AE4B" stroke="#A65C20" strokeWidth="4" />
          <circle cx="231" cy="178" r="20" fill="#FFE0A0" stroke="#A65C20" strokeWidth="4" />
          <circle cx="224" cy="174" r="4" fill="#D2483B" />
          <circle cx="233" cy="169" r="4" fill="#D2483B" />
          <circle cx="240" cy="177" r="4" fill="#D2483B" />
          <path d="M231 181c8 1 12 9 8 14-4 5-9 0-12 0-3 0-7 4-11-1-4-6 4-13 15-13Z" fill="#D2483B" />
        </g>
      </svg>
    </div>
  );
}
