"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type Status = "draft" | "active" | "inactive" | "discontinued";
type SortKey = "updated_at" | "product_code" | "name" | "status";
type SortDir = "asc" | "desc";

type ProductRow = {
  id: number;
  product_code: string;
  name: string;
  short_name: string | null;
  status: Status;
  brand_id: number | null;
  category_id: number | null;
  updated_at: string;
};

type LookupRow = { id: number; name: string; code: string };

const STATUS_LABEL: Record<Status, string> = {
  draft: "草稿",
  active: "上架",
  inactive: "下架",
  discontinued: "停產",
};

const PAGE_SIZE = 50;

export default function ProductListPage() {
  const [rows, setRows] = useState<ProductRow[] | null>(null);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // filters
  const [queryDraft, setQueryDraft] = useState("");
  const [query, setQuery] = useState("");
  const [categoryId, setCategoryId] = useState<string>("");
  const [brandId, setBrandId] = useState<string>("");
  const [status, setStatus] = useState<string>("");

  // sort + page
  const [sortBy, setSortBy] = useState<SortKey>("updated_at");
  const [sortDir, setSortDir] = useState<SortDir>("desc");
  const [page, setPage] = useState(1);

  // lookups
  const [brands, setBrands] = useState<LookupRow[]>([]);
  const [categories, setCategories] = useState<LookupRow[]>([]);

  // debounce search
  useEffect(() => {
    const t = setTimeout(() => {
      setQuery(queryDraft);
      setPage(1);
    }, 250);
    return () => clearTimeout(t);
  }, [queryDraft]);

  // reset page when filter changes
  useEffect(() => {
    setPage(1);
  }, [categoryId, brandId, status, sortBy, sortDir]);

  // fetch lookups once
  useEffect(() => {
    (async () => {
      const sb = getSupabase();
      const [b, c] = await Promise.all([
        sb.from("brands").select("id, name, code").order("name"),
        sb.from("categories").select("id, name, code").order("level").order("sort_order"),
      ]);
      if (b.data) setBrands(b.data as LookupRow[]);
      if (c.data) setCategories(c.data as LookupRow[]);
    })();
  }, []);

  // fetch rows
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    (async () => {
      try {
        let q = getSupabase()
          .from("products")
          .select("id, product_code, name, short_name, status, brand_id, category_id, updated_at", {
            count: "exact",
          })
          .order(sortBy, { ascending: sortDir === "asc" })
          .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);

        if (query.trim()) {
          const safe = query.replace(/[%,()]/g, " ").trim();
          q = q.or(
            `name.ilike.%${safe}%,product_code.ilike.%${safe}%,short_name.ilike.%${safe}%`
          );
        }
        if (categoryId) q = q.eq("category_id", Number(categoryId));
        if (brandId) q = q.eq("brand_id", Number(brandId));
        if (status) q = q.eq("status", status);

        const { data, count, error } = await q;
        if (cancelled) return;
        if (error) {
          setError(error.message);
          return;
        }
        setError(null);
        setRows((data ?? []) as ProductRow[]);
        setTotal(count ?? 0);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [query, categoryId, brandId, status, sortBy, sortDir, page]);

  const brandMap = useMemo(() => new Map(brands.map((b) => [b.id, b])), [brands]);
  const categoryMap = useMemo(() => new Map(categories.map((c) => [c.id, c])), [categories]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const fromIdx = total === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
  const toIdx = Math.min(page * PAGE_SIZE, total);

  function toggleSort(key: SortKey) {
    if (sortBy === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortBy(key);
      setSortDir(key === "updated_at" ? "desc" : "asc");
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-4 p-6">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">商品</h1>
          <p className="text-sm text-zinc-500">
            {loading
              ? "載入中…"
              : total === 0
                ? "共 0 筆"
                : `共 ${total} 筆（顯示 ${fromIdx}-${toIdx}）`}
          </p>
        </div>
        <Link
          href="/products/new"
          className="rounded-md bg-zinc-900 px-3 py-2 text-sm font-medium text-white hover:bg-zinc-800 dark:bg-zinc-50 dark:text-zinc-900 dark:hover:bg-zinc-200"
        >
          新增商品
        </Link>
      </header>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <input
          type="search"
          placeholder="搜尋 編號 / 名稱 / 簡稱"
          value={queryDraft}
          onChange={(e) => setQueryDraft(e.target.value)}
          className="rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm focus:border-zinc-500 focus:outline-none dark:border-zinc-700 dark:bg-zinc-800"
        />
        <select
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
          className="rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-800"
        >
          <option value="">全部分類</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name} ({c.code})
            </option>
          ))}
        </select>
        <select
          value={brandId}
          onChange={(e) => setBrandId(e.target.value)}
          className="rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-800"
        >
          <option value="">全部品牌</option>
          {brands.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name} ({b.code})
            </option>
          ))}
        </select>
        <select
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          className="rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-800"
        >
          <option value="">全部狀態</option>
          <option value="draft">草稿</option>
          <option value="active">上架</option>
          <option value="inactive">下架</option>
          <option value="discontinued">停產</option>
        </select>
      </div>

      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
          <p className="font-medium">讀取失敗</p>
          <p className="mt-1 font-mono text-xs">{error}</p>
        </div>
      )}

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="min-w-full divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <ThSort label="商品編號" col="product_code" sortBy={sortBy} sortDir={sortDir} onToggle={toggleSort} />
              <ThSort label="名稱" col="name" sortBy={sortBy} sortDir={sortDir} onToggle={toggleSort} />
              <Th>品牌 / 分類</Th>
              <ThSort label="狀態" col="status" sortBy={sortBy} sortDir={sortDir} onToggle={toggleSort} />
              <ThSort
                label="更新時間"
                col="updated_at"
                sortBy={sortBy}
                sortDir={sortDir}
                onToggle={toggleSort}
                align="right"
              />
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
            {rows === null ? (
              <SkeletonRows />
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={5} className="p-6 text-center text-sm text-zinc-500">
                  {total === 0 && !query && !categoryId && !brandId && !status
                    ? "還沒有商品，按「新增商品」開始建立。"
                    : "沒有符合條件的商品。"}
                </td>
              </tr>
            ) : (
              rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-50 dark:hover:bg-zinc-900">
                  <Td className="font-mono">
                    <Link href={`/products/edit?id=${r.id}`} className="hover:underline">
                      {r.product_code}
                    </Link>
                  </Td>
                  <Td>
                    <div>{r.name}</div>
                    {r.short_name && <div className="text-xs text-zinc-500">{r.short_name}</div>}
                  </Td>
                  <Td className="text-xs text-zinc-600 dark:text-zinc-400">
                    {r.brand_id ? brandMap.get(r.brand_id)?.name ?? "—" : "—"}
                    {r.category_id ? ` / ${categoryMap.get(r.category_id)?.name ?? "—"}` : ""}
                  </Td>
                  <Td>
                    <StatusBadge status={r.status} />
                  </Td>
                  <Td className="text-right text-zinc-500">
                    {new Date(r.updated_at).toLocaleString("zh-TW")}
                  </Td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-end gap-2 text-sm">
          <button
            onClick={() => setPage(1)}
            disabled={page === 1}
            className="rounded-md border border-zinc-300 px-2 py-1 disabled:opacity-40 dark:border-zinc-700"
          >
            « 第一頁
          </button>
          <button
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page === 1}
            className="rounded-md border border-zinc-300 px-2 py-1 disabled:opacity-40 dark:border-zinc-700"
          >
            ‹ 上頁
          </button>
          <span className="px-2 text-zinc-500">
            {page} / {totalPages}
          </span>
          <button
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page === totalPages}
            className="rounded-md border border-zinc-300 px-2 py-1 disabled:opacity-40 dark:border-zinc-700"
          >
            下頁 ›
          </button>
          <button
            onClick={() => setPage(totalPages)}
            disabled={page === totalPages}
            className="rounded-md border border-zinc-300 px-2 py-1 disabled:opacity-40 dark:border-zinc-700"
          >
            最末頁 »
          </button>
        </div>
      )}
    </div>
  );
}

function Th({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <th className={`px-4 py-2 text-left text-xs font-medium uppercase tracking-wide text-zinc-500 ${className}`}>
      {children}
    </th>
  );
}

function ThSort({
  label,
  col,
  sortBy,
  sortDir,
  onToggle,
  align = "left",
}: {
  label: string;
  col: SortKey;
  sortBy: SortKey;
  sortDir: SortDir;
  onToggle: (c: SortKey) => void;
  align?: "left" | "right";
}) {
  const active = sortBy === col;
  const arrow = active ? (sortDir === "asc" ? "↑" : "↓") : "";
  return (
    <th
      onClick={() => onToggle(col)}
      className={`cursor-pointer px-4 py-2 text-xs font-medium uppercase tracking-wide text-zinc-500 select-none hover:text-zinc-900 dark:hover:text-zinc-100 ${align === "right" ? "text-right" : "text-left"}`}
    >
      {label} <span className="text-zinc-400">{arrow}</span>
    </th>
  );
}

function Td({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <td className={`px-4 py-3 ${className}`}>{children}</td>;
}

function StatusBadge({ status }: { status: Status }) {
  const styles: Record<Status, string> = {
    draft: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300",
    active: "bg-green-100 text-green-800 dark:bg-green-950 dark:text-green-300",
    inactive: "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300",
    discontinued: "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-300",
  };
  return (
    <span className={`inline-block rounded px-2 py-0.5 text-xs ${styles[status]}`}>
      {STATUS_LABEL[status]}
    </span>
  );
}

function SkeletonRows() {
  return (
    <>
      {Array.from({ length: 5 }).map((_, i) => (
        <tr key={i}>
          <td colSpan={5} className="p-3">
            <div className="h-4 animate-pulse rounded bg-zinc-100 dark:bg-zinc-800" />
          </td>
        </tr>
      ))}
    </>
  );
}
