"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

type CloseDateOption = { close_date: string; campaign_count: number };

export default function NewPurchaseRequestPage() {
  const router = useRouter();
  const [options, setOptions] = useState<CloseDateOption[] | null>(null);
  const [closeDate, setCloseDate] = useState<string>("");
  const [purchaseDate, setPurchaseDate] = useState<string>(
    new Date().toLocaleDateString("sv-SE"), // YYYY-MM-DD
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      // 抓最近 60 天內的 closed campaign，依日期分組
      const since = new Date();
      since.setDate(since.getDate() - 60);
      const { data, error: err } = await getSupabase()
        .from("group_buy_campaigns")
        .select("end_at")
        .eq("status", "closed")
        .gte("end_at", since.toISOString())
        .order("end_at", { ascending: false });

      if (cancelled) return;
      if (err) {
        setError(err.message);
        return;
      }

      const byDate = new Map<string, number>();
      for (const r of data ?? []) {
        if (!r.end_at) continue;
        const d = new Date(r.end_at).toLocaleDateString("sv-SE");
        byDate.set(d, (byDate.get(d) ?? 0) + 1);
      }
      const opts: CloseDateOption[] = Array.from(byDate.entries())
        .map(([close_date, campaign_count]) => ({ close_date, campaign_count }))
        .sort((a, b) => b.close_date.localeCompare(a.close_date));
      setOptions(opts);
      if (opts.length && !closeDate) setCloseDate(opts[0].close_date);
    })();
    return () => {
      cancelled = true;
    };
  }, [closeDate]);

  async function handleImport() {
    if (!closeDate) {
      setError("請先選結單日");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const { data: userData } = await supabase.auth.getUser();
      const opUid = userData.user?.id;
      if (!opUid) throw new Error("未登入");

      const { data: prId, error: rpcErr } = await supabase.rpc(
        "rpc_create_pr_from_close_date",
        { p_close_date: closeDate, p_operator: opUid },
      );
      if (rpcErr) throw new Error(rpcErr.message);

      router.push(`/purchase/requests/edit?id=${prId}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-4 p-6">
      <header>
        <h1 className="text-xl font-semibold">新增採購單</h1>
        <p className="text-sm text-zinc-500">選結單日後一鍵帶入當日所有 closed campaign 的商品</p>
      </header>

      <div className="rounded-md border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-900">
        <div className="grid gap-4 sm:grid-cols-3">
          <label className="block">
            <span className="block pb-1 text-xs text-zinc-500">採購日期</span>
            <input
              type="date"
              value={purchaseDate}
              onChange={(e) => setPurchaseDate(e.target.value)}
              className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-800"
            />
          </label>

          <label className="block">
            <span className="block pb-1 text-xs text-zinc-500">結單日</span>
            <select
              value={closeDate}
              onChange={(e) => setCloseDate(e.target.value)}
              disabled={!options || options.length === 0}
              className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm disabled:opacity-50 dark:border-zinc-700 dark:bg-zinc-800"
            >
              {options === null && <option>載入中…</option>}
              {options && options.length === 0 && <option>近 60 天無已結單活動</option>}
              {options?.map((o) => (
                <option key={o.close_date} value={o.close_date}>
                  {o.close_date}（{o.campaign_count} 團）
                </option>
              ))}
            </select>
          </label>

          <div className="flex items-end">
            <button
              onClick={handleImport}
              disabled={busy || !closeDate}
              className="w-full rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50"
            >
              {busy ? "建立中…" : "帶入該日商品"}
            </button>
          </div>
        </div>

        {error && (
          <div className="mt-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
            {error}
          </div>
        )}

        <div className="mt-4 text-xs text-zinc-500">
          系統會把該結單日所有 closed campaign 的需求依 SKU 加總、依 sku_suppliers.is_preferred 自動帶入建議供應商。
        </div>
      </div>
    </div>
  );
}
