"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type Row = {
  id: number;
  po_no: string;
  supplier_id: number;
  supplier_name: string | null;
  status: string;
  total: number;
  expected_date: string | null;
  sent_at: string | null;
  updated_at: string;
};

const STATUS_LABEL: Record<string, string> = {
  draft: "草稿",
  sent: "已發送",
  partially_received: "部分到貨",
  fully_received: "全部到貨",
  closed: "已結案",
  cancelled: "已取消",
};

export default function PurchaseOrdersListPage() {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        let q = getSupabase()
          .from("purchase_orders")
          .select(
            "id, po_no, supplier_id, status, total, expected_date, sent_at, updated_at, suppliers(name)",
          )
          .order("updated_at", { ascending: false })
          .limit(200);
        if (statusFilter) q = q.eq("status", statusFilter);
        const { data, error: err } = await q;
        if (cancelled) return;
        if (err) {
          setError(err.message);
          return;
        }
        type Raw = {
          id: number;
          po_no: string;
          supplier_id: number;
          status: string;
          total: number;
          expected_date: string | null;
          sent_at: string | null;
          updated_at: string;
          suppliers: { name: string } | { name: string }[] | null;
        };
        const mapped: Row[] = (data as Raw[] | null ?? []).map((r) => {
          const sup = Array.isArray(r.suppliers) ? r.suppliers[0] : r.suppliers;
          return {
            id: r.id,
            po_no: r.po_no,
            supplier_id: r.supplier_id,
            supplier_name: sup?.name ?? null,
            status: r.status,
            total: Number(r.total),
            expected_date: r.expected_date,
            sent_at: r.sent_at,
            updated_at: r.updated_at,
          };
        });
        setError(null);
        setRows(mapped);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [statusFilter]);

  return (
    <div className="flex flex-1 flex-col gap-4 p-6">
      <header>
        <h1 className="text-xl font-semibold">採購訂單（PO）</h1>
        <p className="text-sm text-zinc-500">
          {rows === null ? "載入中…" : `共 ${rows.length} 筆`}
        </p>
        <p className="mt-2 text-xs text-zinc-500">
          PO 由「採購單」拆出（每張 PO 一個供應商）。詳情頁 / 發送 modal 在下個 session 補。
        </p>
      </header>

      <div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-800"
        >
          <option value="">全部狀態</option>
          {Object.entries(STATUS_LABEL).map(([v, l]) => (
            <option key={v} value={v}>
              {l}
            </option>
          ))}
        </select>
      </div>

      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
          {error}
        </div>
      )}

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="min-w-full divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <Th>單號</Th>
              <Th>供應商</Th>
              <Th>狀態</Th>
              <Th className="text-right">金額</Th>
              <Th>預計到貨</Th>
              <Th>發送時間</Th>
              <Th className="text-right">更新</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
            {rows === null ? (
              <tr>
                <td colSpan={7} className="p-3 text-center text-zinc-500">
                  載入中…
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={7} className="p-6 text-center text-zinc-500">
                  尚無採購訂單
                </td>
              </tr>
            ) : (
              rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-50 dark:hover:bg-zinc-900">
                  <Td className="font-mono">{r.po_no}</Td>
                  <Td>{r.supplier_name ?? "—"}</Td>
                  <Td>
                    <span className="inline-block rounded bg-zinc-100 px-2 py-0.5 text-xs dark:bg-zinc-800">
                      {STATUS_LABEL[r.status] ?? r.status}
                    </span>
                  </Td>
                  <Td className="text-right font-mono">${r.total.toFixed(0)}</Td>
                  <Td className="text-xs">{r.expected_date ?? "—"}</Td>
                  <Td className="text-xs text-zinc-500">
                    {r.sent_at ? new Date(r.sent_at).toLocaleString("zh-TW") : "—"}
                  </Td>
                  <Td className="text-right text-xs text-zinc-500">
                    {new Date(r.updated_at).toLocaleString("zh-TW")}
                  </Td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Th({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <th
      className={`px-4 py-2 text-left text-xs font-medium uppercase tracking-wide text-zinc-500 ${className}`}
    >
      {children}
    </th>
  );
}
function Td({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <td className={`px-4 py-3 ${className}`}>{children}</td>;
}
