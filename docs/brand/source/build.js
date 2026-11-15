// Renders the Pindu OS artwork from scene.html and ../icon.png.
//
//   node build.js                 the files kept in docs/brand/
//   node build.js --extras <dir>  article covers, link-preview image and avatar, into <dir>
//
// Needs Node.js with Playwright (Chromium) and the Inter and Inter Display fonts installed.
// See ../README.md.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const SUB = 'Boot straight into your games';
const LINE = 'An image-based Linux for the couch, built on Fedora bootc';

// w and h are CSS pixels; the file is w*scale by h*scale. `cls` selects a layout in scene.html.
const brand = [
  { out: 'readme-banner.webp', w: 1280, h: 400, scale: 2, cls: 'banner rounded', sub: SUB, line: LINE, transparent: true },
  { out: 'social-preview.png', w: 1280, h: 640, scale: 1, cls: 'social', sub: SUB, line: LINE },
  { out: 'lockup-for-dark.png', w: 900, h: 320, scale: 1, cls: 'lockup', nobg: 1, nostage: 1, transparent: true },
  { out: 'lockup-for-light.png', w: 900, h: 320, scale: 1, cls: 'lockup light', nobg: 1, nostage: 1, transparent: true },
];
const extras = [
  { out: 'og-image.png', w: 1200, h: 630, scale: 1, cls: 'social og', sub: SUB, line: LINE },
  { out: 'avatar.png', w: 1024, h: 1024, scale: 1, cls: 'avatar', notext: 1, nostage: 1 },
  { out: 'article-cover.png', w: 1920, h: 1080, scale: 1, cls: 'cover', sub: SUB, nostage: 1 },
  { out: 'article-cover-icon-only.png', w: 1920, h: 1080, scale: 1, cls: 'cover blank', notext: 1, nostage: 1 },
  { out: 'article-cover-screen.png', w: 1920, h: 1080, scale: 1, cls: 'cover left', notext: 1 },
  { out: 'article-cover-title-space.png', w: 1920, h: 1080, scale: 1, cls: 'cover left', notext: 1, nostage: 1 },
];

// Chromium screenshots are PNG; it re-encodes one as WebP, alpha included, on a canvas.
async function toWebp(browser, png) {
  const page = await browser.newPage();
  const dataUrl = await page.evaluate(async (src) => {
    const img = new Image();
    img.src = src;
    await img.decode();
    const canvas = document.createElement('canvas');
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    canvas.getContext('2d').drawImage(img, 0, 0);
    return canvas.toDataURL('image/webp', 0.92);
  }, 'data:image/png;base64,' + png.toString('base64'));
  await page.close();
  return Buffer.from(dataUrl.split(',')[1], 'base64');
}

(async () => {
  const extrasAt = process.argv.indexOf('--extras');
  const jobs = extrasAt === -1 ? brand : extras;
  const outDir = extrasAt === -1 ? path.join(__dirname, '..') : process.argv[extrasAt + 1];
  if (!outDir) throw new Error('--extras needs a directory');
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch();
  for (const job of jobs) {
    const page = await browser.newPage({
      viewport: { width: job.w, height: job.h },
      deviceScaleFactor: job.scale,
    });
    const query = new URLSearchParams({ w: job.w, h: job.h, cls: job.cls });
    for (const key of ['sub', 'line', 'notext', 'nostage', 'nobg']) {
      if (job[key]) query.set(key, job[key]);
    }
    await page.goto('file://' + path.join(__dirname, 'scene.html') + '?' + query);
    await page.evaluate(() => document.fonts.ready);
    let image = await page.screenshot({ omitBackground: Boolean(job.transparent) });
    await page.close();
    if (job.out.endsWith('.webp')) image = await toWebp(browser, image);
    fs.writeFileSync(path.join(outDir, job.out), image);
    console.log(job.out);
  }
  await browser.close();
})();
