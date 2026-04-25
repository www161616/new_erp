"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type Row = {
  id: number;
  pr_no: string;
  source_type: string;
  source_close_date: string | null;
  status: string;
  review_status: string;
  total_amount: number;
  notes: string | null;
  updated_at: string;
};

const STATUS_LABEL: Record<string, string> = {
  draft: "草稿",
  submitted: "已送審",
  partially_ordered: "部分轉單",
  fully_ordered: "全部轉單",
  cancelled: "已取消",
};

const REVIEW_LABEL: Record<string, string> = {
  approved: "已通過",
  pending_review: "待審核",
  rejected: "已退回",
};

export default function PurchaseRequestsListPage() {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>("");
  const [reviewFilter, setReviewFilter] = useState<string>("");
  const [reloadTick, setReloadTick] = useState(0);
  const [busyId, setBusyId] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        let q = getSupabase()
          .from("purchase_requests")
          .select(
            "id, pr_no, source_type, source_close_date, status, review_status, total_amount, notes, updated_at",
          )
          .order("updated_at", { ascending: false })
          .limit(200);
        if (statusFilter) q = q.eq("status", statusFilter);
        if (reviewFilter) q = q.eq("review_status", reviewFilter);
        const { data, error: err } = await q;
        if (cancelled) return;
        if (err) {
          setError(err.message);
          return;
        }
        setError(null);
        setRows((data ?? []) as Row[]);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [statusFilter, reviewFilter, reloadTick]);

  async function approve(id: number) {
    if (!confirm("確定通過審核？")) return;
    setBusyId(id);
    try {
      const supabase = getSupabase();
      const { data: userData } = await supabase.auth.getUser();
      const { error: rpcErr } = await supabase.rpc("rpc_approve_purchase_request", {
        p_pr_id: id,
        p_note: null,
        p_operator: userData.user?.id,
      });
      if (rpcErr) throw new Error(rpcErr.message);
      setReloadTick((t) => t + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
    }
  }

  async function reject(id: number) {
    const reason = prompt("退回原因（必填）");
    if (!reason) return;
    setBusyId(id);
    try {
      const supabase = getSupabase();
      const { data: userData } = await supabase.auth.getUser();
      const { error: rpcErr } = await supabase.rpc("rpc_reject_purchase_request", {
        p_pr_id: id,
        p_reason: reason,
        p_operator: userData.user?.id,
      });
      if (rpcErr) throw new Error(rpcErr.message);
      setReloadTick((t) => t + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-4 p-6">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">採購單（PR）</h1>
          <p className="text-sm text-zinc-500">
            {rows === null ? "載入中…" : `共 ${rows.length} 筆`}
          </p>
        </div>
        <a
          href="/purchase/requests/new"
          className="rounded-md bg-zinc-900 px-3 py-2 text-sm font-medium text-white hover:bg-zinc-800 dark:bg-zinc-50 dark:text-zinc-900 dark:hover:bg-zinc-200"
        >
          新增採購單
        </a>
      </header>

      <div className="grid gap-3 sm:grid-cols-2">
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
        <select
          value={reviewFilter}
          onChange={(e) => setReviewFilter(e.target.value)}
          className="rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-800"
        >
          <option value="">全部審核狀態</option>
          {Object.entries(REVIEW_LABEL).map(([v, l]) => (
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
              <Th>來源</Th>
              <Th>結單日</Th>
              <Th>狀態</Th>
              <Th>審核</Th>
              <Th className="text-right">總金額</Th>
              <Th className="text-right">更新</Th>
              <Th></Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
            {rows === null ? (
              <tr>
                <td colSpan={8} className="p-3 text-center text-zinc-500">
                  載入中…
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={8} className="p-6 text-center text-zinc-500">
                  還沒有採購單，按「新增採購單」開始。
                </td>
              </tr>
            ) : (
              rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-50 dark:hover:bg-zinc-900">
                  <Td className="font-mono">
                    <a
                      href={`/purchase/requests/edit?id=${r.id}`}
                      className="hover:underline"
                    >
                      {r.pr_no}
                    </a>
                  </Td>
                  <Td className="text-xs text-zinc-500">
                    {r.source_type === "close_date" ? "結單日帶入" : "手動"}
                  </Td>
                  <Td className="text-xs">{r.source_close_date ?? "—"}</Td>
                  <Td>
                    <Badge label={STATUS_LABEL[r.status] ?? r.status} kind="status" status={r.status} />
                  </Td>
                  <Td>
                    <Badge
                      label={REVIEW_LABEL[r.review_status] ?? r.review_status}
                      kind="review"
                      status={r.review_status}
                    />
                  </Td>
                  <Td className="text-right font-mono">${Number(r.total_amount).toFixed(0)}</Td>
                  <Td className="text-right text-xs text-zinc-500">
                    {new Date(r.updated_at).toLocaleString("zh-TW")}
                  </Td>
                  <Td>
                    <div className="flex gap-2">
                      {r.review_status === "pending_review" && (
                        <>
                          <button
                            disabled={busyId === r.id}
                            onClick={() => approve(r.id)}
                            className="text-xs text-emerald-600 hover:underline disabled:opacity-50 dark:text-emerald-400"
                          >
                            通過
                          </button>
                          <button
                            disabled={busyId === r.id}
                            onClick={() => reject(r.id)}
                            className="text-xs text-red-600 hover:underline disabled:opacity-50 dark:text-red-400"
                          >
                            退回
                          </button>
                        </>
                      )}
                    </div>
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

function Th({ children, className = "" }: { children?: React.ReactNode; className?: string }) {
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
function Badge({
  label,
  status,
  kind,
}: {
  label: string;
  status: string;
  kind: "status" | "review";
}) {
  const cls =
    kind === "review"
      ? status === "pending_review"
        ? "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
        : status === "rejected"
          ? "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-300"
          : "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
      : status === "draft"
        ? "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
        : status === "submitted"
          ? "bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-300"
          : status === "fully_ordered"
            ? "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
            : "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300";
  return <span className={`inline-block rounded px-2 py-0.5 text-xs ${cls}`}>{label}</span>;
}
