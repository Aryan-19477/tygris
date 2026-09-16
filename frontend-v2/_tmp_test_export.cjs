const puppeteer = require("puppeteer-core");
const path = require("path");

const DOWNLOAD_DIR = "C:\\Users\\asus\\AppData\\Local\\Temp\\tygris-downloads";

(async () => {
  const fs = require("fs");
  if (!fs.existsSync(DOWNLOAD_DIR)) fs.mkdirSync(DOWNLOAD_DIR, { recursive: true });

  const browser = await puppeteer.connect({ browserURL: "http://localhost:9222" });
  const page = await browser.newPage();

  const consoleMsgs = [];
  page.on("console", (msg) => consoleMsgs.push(`[console.${msg.type()}] ${msg.text()}`));
  page.on("pageerror", (err) => consoleMsgs.push(`[pageerror] ${err.message}`));
  page.on("requestfailed", (req) => consoleMsgs.push(`[requestfailed] ${req.url()} ${req.failure()?.errorText}`));

  const client = await page.target().createCDPSession();
  await client.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: DOWNLOAD_DIR });
  let downloadEvent = null;
  client.on("Page.downloadWillBegin", (e) => { downloadEvent = { stage: "begin", ...e }; });
  client.on("Page.downloadProgress", (e) => { if (e.state === "completed" || e.state === "canceled") downloadEvent = { ...downloadEvent, stage: e.state }; });

  await page.setViewport({ width: 1400, height: 1000 });
  await page.goto("http://localhost:3002/", { waitUntil: "networkidle2", timeout: 30000 });

  // Go to Tiger Catalogue
  await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll("button, a"));
    const target = btns.find((b) => b.textContent?.trim() === "Tiger Catalogue");
    if (target) target.click();
  });
  await new Promise((r) => setTimeout(r, 2000));

  // Click first tiger card
  const openedTiger = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll("button"));
    const card = btns.find((b) => /^T\d+/.test(b.textContent?.trim() || "") && b.querySelector("img, div"));
    if (card) { card.click(); return card.textContent?.trim().slice(0, 30); }
    return null;
  });
  consoleMsgs.push(`[test] opened tiger card: ${openedTiger}`);
  await new Promise((r) => setTimeout(r, 2500));

  // Click "Add Tiger"
  const addTigerClicked = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll("button"));
    const btn = btns.find((b) => b.textContent?.trim().includes("Add Tiger"));
    if (btn) { btn.click(); return true; }
    return false;
  });
  consoleMsgs.push(`[test] Add Tiger clicked: ${addTigerClicked}`);
  await new Promise((r) => setTimeout(r, 1500));

  // Pick first available tiger from the dropdown list
  const pickedTiger = await page.evaluate(() => {
    const buttons = Array.from(document.querySelectorAll("button"));
    const candidate = buttons.find((b) => /^T\d+_[MF]$/.test(b.textContent?.trim() || ""));
    if (candidate) { candidate.click(); return candidate.textContent?.trim(); }
    return null;
  });
  consoleMsgs.push(`[test] picked comparison tiger: ${pickedTiger}`);
  await new Promise((r) => setTimeout(r, 3000));

  // Diagnostic: inspect the actual label DOM element to see which code path rendered it
  const labelDiag = await page.evaluate(() => {
    const candidates = Array.from(document.querySelectorAll("*")).filter(
      (el) => el.children.length === 0 && /^T\d+_[MF]$/.test(el.textContent?.trim() || "")
    );
    return candidates.map((el) => ({
      tag: el.tagName,
      className: el.className,
      style: el.getAttribute("style"),
      text: el.textContent?.trim(),
      rect: el.getBoundingClientRect().toJSON(),
    }));
  });
  consoleMsgs.push(`[test] label diagnostics: ${JSON.stringify(labelDiag, null, 2)}`);

  // Also grab the polygon (SVG path) bounding boxes for comparison
  const svgDiag = await page.evaluate(() => {
    const svg = document.querySelector(".leaflet-overlay-pane svg");
    if (!svg) return null;
    const paths = Array.from(svg.querySelectorAll("path"));
    return {
      svgTransform: svg.getAttribute("style"),
      svgViewBox: svg.getAttribute("viewBox"),
      pathBBoxes: paths.map((p) => p.getBBox()),
    };
  });
  consoleMsgs.push(`[test] svg diagnostics: ${JSON.stringify(svgDiag, null, 2)}`);

  // Screenshot the map before export, for visual inspection
  const mapHandle = await page.evaluateHandle(() => {
    const btns = Array.from(document.querySelectorAll("button"));
    const exportBtn = btns.find((b) => b.textContent?.trim().includes("Export"));
    return exportBtn ? exportBtn.closest(".relative.h-90") : null;
  });
  const mapEl = mapHandle.asElement();
  if (mapEl) {
    await mapEl.screenshot({ path: path.join(DOWNLOAD_DIR, "before-export.png") });
    consoleMsgs.push("[test] captured before-export.png");
  } else {
    consoleMsgs.push("[test] could not locate map container for screenshot");
  }

  // Click Export
  const exportClicked = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll("button"));
    const btn = btns.find((b) => b.textContent?.trim().includes("Export"));
    if (btn) { btn.click(); return true; }
    return false;
  });
  consoleMsgs.push(`[test] Export clicked: ${exportClicked}`);

  await new Promise((r) => setTimeout(r, 4000));

  // Check for an error toast in the DOM
  const errorToast = await page.evaluate(() => {
    const el = Array.from(document.querySelectorAll("div")).find((d) => d.textContent?.includes("Export failed"));
    return el ? el.textContent : null;
  });
  consoleMsgs.push(`[test] error toast present: ${errorToast}`);
  consoleMsgs.push(`[test] download event: ${JSON.stringify(downloadEvent)}`);

  const files = fs.readdirSync(DOWNLOAD_DIR);
  consoleMsgs.push(`[test] download dir contents: ${JSON.stringify(files)}`);

  console.log(consoleMsgs.join("\n"));

  await page.close();
  await browser.disconnect();
})().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exit(1);
});
