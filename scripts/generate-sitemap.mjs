import { promises as fs } from "node:fs";
import path from "node:path";

const SITE_URL = process.env.SITE_URL || "https://example.com";
const DIST_DIR = path.resolve("dist");

function xmlEscape(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

async function listHtmlFiles(dir) {
  const out = [];
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...(await listHtmlFiles(p)));
    else if (e.isFile() && e.name.endsWith(".html")) out.push(p);
  }
  return out;
}

(async () => {
  const files = await listHtmlFiles(DIST_DIR);
  const urls = files
    .filter((f) => !f.endsWith("/404.html"))
    .map((f) => {
      const rel = path.relative(DIST_DIR, f).replace(/\\/g, "/");
      const urlPath = rel === "index.html" ? "/" : `/${rel.replace(/index\.html$/, "")}`;
      return `${SITE_URL}${urlPath}`;
    });

  const body = urls.map((u) => `<url><loc>${xmlEscape(u)}</loc></url>`).join("");

  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">` +
    body +
    `</urlset>`;

  await fs.writeFile(path.join(DIST_DIR, "sitemap.xml"), xml, "utf8");
})();
