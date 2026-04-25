"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

type PRHeader = {
  id: number;
  pr_no: string;
  source_type: string;
  source_close_date: string | null;
  status: string;
  review_status: string;
  total_amount: number;
  notes: string | null;
};

type Supplier = { id: number; name: string };

type PriceLookup = { sku_id: number; retail: number | null; franchise: number | null };

type ItemRow = {
  id: number;
  sku_id: number;
  sku_code: string;
  product_name: string;
  variant_name: string | null;
  unit_uom: string | null;
  qty_requested: number;
  unit_cost: number;
  line_subtotal: number;
  suggested_supplier_id: number | null;
  source_campaign_id: number | null;
  retail_price: number | null;
  franchise_price: number | null;
  dirty: boolean;
};

const REVIEW_LABEL: Record<string, string> = {
  approved: "已通過",
  pending_review: "待審核",
  rejected: "已退回",
};

const STATUS_LABEL: Record<string, string> = {
  draft: "草稿",
  submitted: "已送審",
  partially_ordered: "部分轉單",
  fully_ordered: "全部轉單",
  cancelled: "已取消",
};

export default function EditPurchaseRequestPage() {
  const router = useRouter();
  const params = useSearchParams();
  const idStr = params.get("id");
  const id = idStr ? Number(idStr) : null;

  const [header, setHeader] = useState<PRHeader | null>(null);
  const [items, setItems] = useState<ItemRow[]>([]);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"save" | "submit" | "split" | null>(null);
  const [destLocationId, setDestLocationId] = useState<number | null>(null);

  useEffect(() => {
    if (!id) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const supabase = getSupabase();

        const [
          { data: prData, error: prErr },
          { data: itemRows, error: itemErr },
          { data: supRows },
          { data: locRow },
        ] = await Promise.all([
          supabase
            .from("purchase_requests")
            .select(
              "id, pr_no, source_type, source_close_date, status, review_status, total_amount, notes, source_location_id",
            )
            .eq("id", id)
            .maybeSingle(),
          supabase
            .from("purchase_request_items")
            .select(
              "id, sku_id, qty_requested, unit_cost, line_subtotal, suggested_supplier_id, source_campaign_id",
            )
            .eq("pr_id", id)
            .order("id"),
          supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
          supabase.from("locations").select("id").order("id").limit(1).maybeSingle(),
        ]);

        if (cancelled) return;
        if (prErr || !prData) throw new Error(prErr?.message ?? "找不到採購單");
        if (itemErr) throw new Error(itemErr.message);

        setHeader(prData as PRHeader);
        setSuppliers((supRows ?? []) as Supplier[]);
        setDestLocationId(prData.source_location_id ?? locRow?.id ?? null);

        const skuIds = (itemRows ?? []).map((r) => r.sku_id);
        if (skuIds.length === 0) {
          setItems([]);
          return;
        }

        // 一次撈 SKU + product 資訊
        const { data: skuRows } = await supabase
          .from("skus")
          .select(
            "id, sku_code, variant_name, products!inner(name, unit_uom)",
          )
          .in("id", skuIds);

        // 一次撈價格（retail + franchise）
        const { data: priceRows } = await supabase
          .from("prices")
          .select("sku_id, scope, price")
          .in("sku_id", skuIds)
          .in("scope", ["retail", "franchise"])
          .eq("is_active", true);

        const priceMap = new Map<number, PriceLookup>();
        for (const id of skuIds) priceMap.set(id, { sku_id: id, retail: null, franchise: null });
        for (const p of priceRows ?? []) {
          const e = priceMap.get(p.sku_id);
          if (!e) continue;
          if (p.scope === "retail") e.retail = Number(p.price);
          if (p.scope === "franchise") e.franchise = Number(p.price);
        }

        const skuMap = new Map(
          (skuRows ?? []).map((s) => {
            const prod = Array.isArray(s.products) ? s.products[0] : s.products;
            return [
              s.id,
              {
                sku_code: s.sku_code as string,
                variant_name: s.variant_name as string | null,
                product_name: prod?.name as string | null,
                unit_uom: prod?.unit_uom as string | null,
              },
            ];
          }),
        );

        const merged: ItemRow[] = (itemRows ?? []).map((r) => {
          const m = skuMap.get(r.sku_id);
          const p = priceMap.get(r.sku_id);
          return {
            id: r.id,
            sku_id: r.sku_id,
            sku_code: m?.sku_code ?? "?",
            product_name: m?.product_name ?? "?",
            variant_name: m?.variant_name ?? null,
            unit_uom: m?.unit_uom ?? null,
            qty_requested: Number(r.qty_requested),
            unit_cost: Number(r.unit_cost),
            line_subtotal: Number(r.line_subtotal ?? 0),
            suggested_supplier_id: r.suggested_supplier_id,
            source_campaign_id: r.source_campaign_id,
            retail_price: p?.retail ?? null,
            franchise_price: p?.franchise ?? null,
            dirty: false,
          };
        });

        setItems(merged);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  const editable = header?.status === "draft";
  const canSplit =
    header?.status === "submitted" && header?.review_status === "approved";

  const totals = useMemo(() => {
    const subtotal = items.reduce((s, r) => s + r.qty_requested * r.unit_cost, 0);
    return { subtotal, withTax: subtotal * 1.05 };
  }, [items]);

  const unassignedCount = items.filter((r) => !r.suggested_supplier_id).length;

  function patchItem(idx: number, patch: Partial<ItemRow>) {
    setItems((cur) =>
      cur.map((r, i) => {
        if (i !== idx) return r;
        const next = { ...r, ...patch, dirty: true };
        next.line_subtotal = next.qty_requested * next.unit_cost;
        return next;
      }),
    );
  }

  function removeItem(idx: number) {
    setItems((cur) => cur.filter((_, i) => i !== idx));
  }

  async function saveDraft() {
    if (!id) return;
    setBusy("save");
    setError(null);
    try {
      const supabase = getSupabase();
      const dirtyRows = items.filter((r) => r.dirty);
      for (const r of dirtyRows) {
        const { error: err } = await supabase
          .from("purchase_request_items")
          .update({
            qty_requested: r.qty_requested,
            unit_cost: r.unit_cost,
            suggested_supplier_id: r.suggested_supplier_id,
          })
          .eq("id", r.id);
        if (err) throw new Error(err.message);
      }
      // notes
      if (header) {
        const { error: hErr } = await supabase
          .from("purchase_requests")
          .update({ notes: header.notes })
          .eq("id", id);
        if (hErr) throw new Error(hErr.message);
      }
      setItems((cur) => cur.map((r) => ({ ...r, dirty: false })));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  }

  async function submitForReview() {
    if (!id) return;
    if (unassignedCount > 0) {
      if (!confirm(`仍有 ${unassignedCount} 行未指派供應商，送審後可審核但拆 PO 時會被擋。確定送審？`)) return;
    } else if (!confirm("確定送出審核？")) {
      return;
    }
    await saveDraft();
    setBusy("submit");
    setError(null);
    try {
      const supabase = getSupabase();
      const { data: userData } = await supabase.auth.getUser();
      const { error: rpcErr } = await supabase.rpc("rpc_submit_pr", {
        p_pr_id: id,
        p_operator: userData.user?.id,
      });
      if (rpcErr) throw new Error(rpcErr.message);
      // refresh header
      const { data } = await supabase
        .from("purchase_requests")
        .select("status, review_status, total_amount")
        .eq("id", id)
        .maybeSingle();
      if (data && header) {
        setHeader({ ...header, ...(data as Partial<PRHeader>) });
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  }

  async function splitToPos() {
    if (!id || !destLocationId) return;
    if (unassignedCount > 0) {
      setError(`有 ${unassignedCount} 行未指派供應商，無法拆 PO`);
      return;
    }
    if (!confirm("確定拆成採購訂單（PO）發給供應商？")) return;
    setBusy("split");
    setError(null);
    try {
      const supabase = getSupabase();
      const { data: userData } = await supabase.auth.getUser();
      const { data: poIds, error: rpcErr } = await supabase.rpc("rpc_split_pr_to_pos", {
        p_pr_id: id,
        p_dest_location_id: destLocationId,
        p_operator: userData.user?.id,
      });
      if (rpcErr) throw new Error(rpcErr.message);
      alert(`已產生 ${(poIds as number[]).length} 張採購訂單`);
      router.push("/purchase/orders");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  }

  if (!id) {
    return (
      <div className="p-6 text-sm text-zinc-500">
        缺少 id 參數。請從 <a href="/purchase/requests" className="text-blue-600 underline">採購單列表</a> 進入。
      </div>
    );
  }

  if (loading) return <div className="p-6 text-sm text-zinc-500">載入中…</div>;
  if (!header) return <div className="p-6 text-sm text-red-600">{error ?? "找不到採購單"}</div>;

  return (
    <div className="flex flex-1 flex-col gap-4 p-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">
            採購單 {header.pr_no}
            <span className="ml-3 inline-block rounded bg-zinc-100 px-2 py-0.5 text-xs font-normal dark:bg-zinc-800">
              {STATUS_LABEL[header.status] ?? header.status}
            </span>
            <span
              className={`ml-2 inline-block rounded px-2 py-0.5 text-xs font-normal ${
                header.review_status === "pending_review"
                  ? "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
                  : header.review_status === "rejected"
                    ? "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-300"
                    : "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
              }`}
            >
              {REVIEW_LABEL[header.review_status] ?? header.review_status}
            </span>
          </h1>
          <p className="text-sm text-zinc-500">
            結單日：{header.source_close_date ?? "—"}　·　共 {items.length} 項
            {unassignedCount > 0 && (
              <span className="ml-2 text-red-600 dark:text-red-400">⚠ {unassignedCount} 行未指派供應商</span>
            )}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <a
            href={`/purchase/requests/print?id=${id}`}
            target="_blank"
            rel="noopener"
            className="rounded-md border border-zinc-300 px-3 py-2 text-sm hover:bg-zinc-100 dark:border-zinc-700 dark:hover:bg-zinc-800"
          >
            列印
          </a>
          {editable && (
            <>
              <button
                onClick={saveDraft}
                disabled={busy !== null}
                className="rounded-md border border-zinc-300 px-3 py-2 text-sm hover:bg-zinc-100 disabled:opacity-50 dark:border-zinc-700 dark:hover:bg-zinc-800"
              >
                {busy === "save" ? "存檔中…" : "存為草稿"}
              </button>
              <button
                onClick={submitForReview}
                disabled={busy !== null}
                className="rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
              >
                {busy === "submit" ? "送審中…" : "送出審核"}
              </button>
            </>
          )}
          {canSplit && (
            <button
              onClick={splitToPos}
              disabled={busy !== null || unassignedCount > 0}
              className="rounded-md bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-500 disabled:opacity-50"
              title={unassignedCount > 0 ? "有未指派供應商" : ""}
            >
              {busy === "split" ? "拆 PO 中…" : "拆成採購訂單"}
            </button>
          )}
        </div>
      </header>

      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
          {error}
        </div>
      )}

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="min-w-full divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <Th>#</Th>
              <Th>品名</Th>
              <Th>供應商</Th>
              <Th>單位</Th>
              <Th className="text-right">數量</Th>
              <Th className="text-right">成本</Th>
              <Th className="text-right">售價</Th>
              <Th className="text-right">分店價</Th>
              <Th className="text-right">小計</Th>
              <Th></Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
            {items.length === 0 ? (
              <tr>
                <td colSpan={10} className="p-6 text-center text-zinc-500">
                  無品項
                </td>
              </tr>
            ) : (
              items.map((r, idx) => (
                <tr key={r.id} className="hover:bg-zinc-50 dark:hover:bg-zinc-900">
                  <Td className="text-zinc-500">{idx + 1}</Td>
                  <Td>
                    <div>{r.product_name}{r.variant_name ? `-${r.variant_name}` : ""}</div>
                    <div className="font-mono text-xs text-zinc-500">{r.sku_code}</div>
                  </Td>
                  <Td>
                    {editable ? (
                      <select
                        value={r.suggested_supplier_id ?? ""}
                        onChange={(e) =>
                          patchItem(idx, {
                            suggested_supplier_id: e.target.value ? Number(e.target.value) : null,
                          })
                        }
                        className={`rounded-md border px-2 py-1 text-sm ${
                          !r.suggested_supplier_id
                            ? "border-red-300 bg-red-50 dark:border-red-800 dark:bg-red-950"
                            : "border-zinc-300 dark:border-zinc-700"
                        } bg-white dark:bg-zinc-800`}
                      >
                        <option value="">— 未指派 —</option>
                        {suppliers.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.name}
                          </option>
                        ))}
                      </select>
                    ) : (
                      suppliers.find((s) => s.id === r.suggested_supplier_id)?.name ?? "—"
                    )}
                  </Td>
                  <Td className="text-zinc-500">{r.unit_uom ?? "—"}</Td>
                  <Td className="text-right">
                    {editable ? (
                      <input
                        type="number"
                        step="0.001"
                        value={r.qty_requested}
                        onChange={(e) => patchItem(idx, { qty_requested: Number(e.target.value) })}
                        className="w-24 rounded-md border border-zinc-300 bg-white px-2 py-1 text-right text-sm dark:border-zinc-700 dark:bg-zinc-800"
                      />
                    ) : (
                      r.qty_requested
                    )}
                  </Td>
                  <Td className="text-right">
                    {editable ? (
                      <input
                        type="number"
                        step="0.0001"
                        value={r.unit_cost}
                        onChange={(e) => patchItem(idx, { unit_cost: Number(e.target.value) })}
                        className="w-24 rounded-md border border-zinc-300 bg-white px-2 py-1 text-right text-sm dark:border-zinc-700 dark:bg-zinc-800"
                      />
                    ) : (
                      r.unit_cost.toFixed(4)
                    )}
                  </Td>
                  <Td className="text-right text-zinc-500">
                    {r.retail_price !== null ? `$${r.retail_price.toFixed(0)}` : "—"}
                  </Td>
                  <Td className="text-right text-zinc-500">
                    {r.franchise_price !== null ? `$${r.franchise_price.toFixed(0)}` : "—"}
                  </Td>
                  <Td className="text-right font-mono">
                    ${(r.qty_requested * r.unit_cost).toFixed(0)}
                  </Td>
                  <Td>
                    {editable && (
                      <button
                        onClick={() => removeItem(idx)}
                        className="text-xs text-red-600 hover:underline dark:text-red-400"
                      >
                        ✕
                      </button>
                    )}
                  </Td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <label className="block max-w-xl flex-1">
          <span className="block pb-1 text-xs text-zinc-500">備註</span>
          <textarea
            value={header.notes ?? ""}
            onChange={(e) => setHeader({ ...header, notes: e.target.value })}
            disabled={!editable}
            rows={2}
            className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm disabled:opacity-50 dark:border-zinc-700 dark:bg-zinc-800"
          />
        </label>
        <div className="text-right text-sm">
          <div className="text-zinc-500">未稅小計：${totals.subtotal.toFixed(1)}</div>
          <div className="text-2xl font-semibold text-blue-600 dark:text-blue-400">
            ${totals.withTax.toFixed(1)}
          </div>
        </div>
      </div>
    </div>
  );
}

function Th({ children, className = "" }: { children?: React.ReactNode; className?: string }) {
  return (
    <th
      className={`px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-zinc-500 ${className}`}
    >
      {children}
    </th>
  );
}
function Td({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <td className={`px-3 py-2 ${className}`}>{children}</td>;
}
