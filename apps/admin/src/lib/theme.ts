export type Theme = "light" | "dark" | "system";

export const THEME_KEY = "new_erp-theme";

// Inline <script> injected into <head> — runs before React hydrates to avoid
// flash of wrong theme. Reads localStorage, falls back to system preference.
export const themeInitScript = `
(function() {
  try {
    var t = localStorage.getItem("${THEME_KEY}") || "system";
    var dark = t === "dark" || (t === "system" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches);
    if (dark) document.documentElement.classList.add("dark");
  } catch (e) {}
})();
`.trim();
