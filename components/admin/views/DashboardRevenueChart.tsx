"use client";

import { useEffect, useId, useRef, useState } from "react";
import { formatRupiah } from "@/lib/format";
import type { DashboardRevenue } from "@/lib/admin/dashboard-revenue";
import { adminMotionAllowed } from "@/components/admin/ui/Motion";

export function DashboardRevenueChart({
  revenue,
}: {
  revenue: DashboardRevenue;
}) {
  const [period, setPeriod] = useState("week");
  const contentRef = useRef<HTMLDivElement>(null);
  const gradientId = useId();
  const titleId = useId();
  const isToday = period === "today";
  const points = isToday ? revenue.hourly : revenue.daily;
  const total = isToday ? revenue.todayTotal : revenue.weekTotal;
  const previous = isToday ? revenue.yesterdayTotal : revenue.previousWeekTotal;
  const difference =
    previous > 0 ? ((total - previous) / previous) * 100 : null;
  const maximum = Math.max(1, ...points.map((point) => point.total));
  const coordinates = points.map((point, index) => ({
    x: points.length === 1 ? 460 : (index * 460) / (points.length - 1),
    y: 145 - (point.total / maximum) * 125,
  }));
  const line = coordinates
    .map((point, index) => `${index === 0 ? "M" : "L"}${point.x},${point.y}`)
    .join(" ");
  const last = coordinates.at(-1);
  useEffect(() => {
    if (!adminMotionAllowed()) return;
    const animation = contentRef.current?.animate(
      [{ opacity: 0.35 }, { opacity: 1 }],
      { duration: 180, easing: "ease-out" }
    );
    return () => animation?.cancel();
  }, [period]);
  return (
    <section className="admin-section dashboard-revenue">
      <header className="dashboard-panel-head">
        <h2>Pendapatan</h2>
        <select
          aria-label="Periode pendapatan"
          value={period}
          onChange={(event) => setPeriod(event.target.value)}
        >
          <option value="week">7 hari terakhir</option>
          <option value="today">Hari ini</option>
        </select>
      </header>
      <div className="dashboard-chart-body" ref={contentRef}>
        <p className="dashboard-chart-total">{formatRupiah(total)}</p>
        <p className="dashboard-chart-comparison">
          {difference !== null ? (
            <>
              <span className={difference < 0 ? "is-down" : "is-up"}>
                {difference > 0 ? "↑" : difference < 0 ? "↓" : "—"}{" "}
                {new Intl.NumberFormat("id-ID", {
                  maximumFractionDigits: 1,
                }).format(Math.abs(difference))}
                %
              </span>{" "}
              dibanding {isToday ? "total kemarin" : "7 hari sebelumnya"}
            </>
          ) : previous === 0 && total === 0 ? (
            "Belum ada pendapatan pada kedua periode."
          ) : (
            "Periode sebelumnya belum memiliki pendapatan."
          )}
        </p>
        <div className="dashboard-chart-scale">
          <span>
            {formatRupiah(maximum === 1 && total === 0 ? 0 : maximum)}
          </span>
          <span>{isToday ? "Akumulasi hari ini" : "Per hari"}</span>
        </div>
        <svg viewBox="-4 0 468 156" role="img" aria-labelledby={titleId}>
          <title id={titleId}>
            {isToday
              ? "Akumulasi pendapatan hari ini"
              : "Pendapatan per hari selama tujuh hari terakhir"}
            . Total {formatRupiah(total)}. Rincian tersedia di bawah grafik.
          </title>
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <stop stopColor="#1760da" stopOpacity=".12" />
              <stop offset="1" stopColor="#1760da" stopOpacity=".01" />
            </linearGradient>
          </defs>
          <path
            d="M0 20H460M0 62H460M0 104H460M0 145H460"
            stroke="#edf1f6"
            fill="none"
          />
          {last && (
            <>
              <path
                d={`${line} L${last.x},145 L0,145 Z`}
                fill={`url(#${gradientId})`}
              />
              <path
                d={line}
                stroke="#1760da"
                strokeWidth="2.5"
                strokeLinejoin="round"
                strokeLinecap="round"
                fill="none"
              />
              <circle
                cx={last.x}
                cy={last.y}
                r="4"
                fill="#1760da"
                stroke="white"
                strokeWidth="2"
              />
            </>
          )}
        </svg>
        <div className="dashboard-chart-labels">
          {points
            .map((point, index) => ({ ...point, index }))
            .filter(
              (point) =>
                points.length <= 7 ||
                Array.from({ length: 6 }, (_, tick) =>
                  Math.round((tick * (points.length - 1)) / 5)
                ).includes(point.index)
            )
            .map((point) => (
              <span
                key={point.label}
                style={{
                  left: `${
                    points.length === 1
                      ? 100
                      : (point.index * 100) / (points.length - 1)
                  }%`,
                  transform: `translateX(${
                    point.index === points.length - 1
                      ? "-100%"
                      : point.index === 0
                      ? "0"
                      : "-50%"
                  })`,
                }}
              >
                {point.label}
              </span>
            ))}
        </div>
        <p className="dashboard-chart-caption">
          Pesanan lunas · tanggal pesanan (WIB) · termasuk ongkir.
        </p>
        <details className="dashboard-chart-details">
          <summary>Lihat rincian pendapatan</summary>
          <table>
            <caption className="sr-only">
              {isToday ? "Akumulasi per jam" : "Pendapatan per hari"}
            </caption>
            <thead>
              <tr>
                <th scope="col">{isToday ? "Jam (WIB)" : "Tanggal"}</th>
                <th scope="col">{isToday ? "Akumulasi" : "Pendapatan"}</th>
              </tr>
            </thead>
            <tbody>
              {points.map((point) => (
                <tr key={point.label}>
                  <td>{point.label}</td>
                  <td>{formatRupiah(point.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </details>
      </div>
    </section>
  );
}
