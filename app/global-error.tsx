"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  console.error("[GlobalError]", error);

  return (
    <html lang="id">
      <body>
        <div
          style={{
            alignItems: "center",
            background: "#f9f9f7",
            color: "#111111",
            display: "flex",
            fontFamily: "system-ui, -apple-system, sans-serif",
            justifyContent: "center",
            minHeight: "100vh",
            padding: "20px",
          }}
        >
          <div style={{ maxWidth: 400, textAlign: "center", width: "100%" }}>
            <div aria-hidden="true" style={{ fontSize: 48, marginBottom: 16 }}>
              🐾
            </div>
            <h1
              style={{
                fontSize: 20,
                fontWeight: 500,
                margin: "0 0 8px",
              }}
            >
              Website sedang bermasalah
            </h1>
            <p
              style={{
                color: "#777777",
                fontSize: 14,
                lineHeight: 1.6,
                margin: "0 0 20px",
              }}
            >
              Maaf atas ketidaknyamanannya. Silakan coba lagi dalam beberapa
              saat.
            </p>
            <button
              onClick={() => reset()}
              style={{
                background: "#1E5FBF",
                border: "none",
                borderRadius: 8,
                color: "white",
                cursor: "pointer",
                fontSize: 14,
                fontWeight: 500,
                padding: "10px 24px",
              }}
              type="button"
            >
              Coba Lagi
            </button>
            {error.digest && (
              <p
                style={{
                  color: "#aaaaaa",
                  fontFamily: "monospace",
                  fontSize: 12,
                  marginTop: 20,
                }}
              >
                Error ID: {error.digest}
              </p>
            )}
          </div>
        </div>
      </body>
    </html>
  );
}
