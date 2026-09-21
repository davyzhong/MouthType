/**
 * MouthType README 渲染截图脚本（readme-craft v2.2 T18）
 *
 * GUI 桌面应用无 Web 入口，统一采用"截 GitHub README 渲染快照"兜底方案：
 *   1. 打开 GitHub 仓库 README 渲染页
 *   2. 等 README 区域加载完
 *   3. 截 README 区域 + 桌面 / 移动视口
 *   4. 保存到 assets/screenshots/
 *
 * v3.1 升级路线：未来用 Playwright 的 macOS launchPersistentContext +
 * nativeScreenshot 抓 macOS 应用界面（仅适用于 macOS runner）。
 *
 * 使用方法：
 *   1. npm install
 *   2. npx playwright install chromium
 *   3. node scripts/screenshot.js
 *
 * 或通过 GitHub Action 自动跑：.github/workflows/screenshot.yml
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'assets', 'screenshots');

// GitHub 仓库 URL（README 渲染快照源）
const REPO_URL = 'https://github.com/davyzhong/MouthType';

// 截图配置：每张图 = { name, viewport, selector, actions }
const SCREENSHOTS = [
  {
    name: 'readme-desktop.png',
    viewport: { width: 1280, height: 800 },
    selector: 'article',
    description: 'README 桌面渲染快照（1280×800）',
    actions: async (page) => {
      await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
      await page.waitForTimeout(1500);
    },
  },
  {
    name: 'readme-mobile.png',
    viewport: { width: 390, height: 844 },
    selector: 'article',
    description: 'README 移动端渲染快照（390×844）',
    actions: async (page) => {
      await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
      await page.waitForTimeout(1500);
    },
  },
];

async function main() {
  console.log(`📸 MouthType README 渲染截图（readme-craft v2.2 T18）`);
  console.log(`📂 项目根：${PROJECT_ROOT}`);
  console.log(`🌐 加载：${REPO_URL}`);
  console.log(`📁 输出：${OUTPUT_DIR}\n`);

  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    console.log(`✅ 创建目录 ${OUTPUT_DIR}`);
  }

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  });

  let success = 0;
  let failed = 0;

  for (const config of SCREENSHOTS) {
    const page = await context.newPage();
    try {
      console.log(`▶ ${config.name}  (${config.viewport.width}x${config.viewport.height})`);
      console.log(`  ${config.description}`);

      await page.setViewportSize(config.viewport);
      await page.goto(REPO_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await config.actions(page);

      const target = page.locator(config.selector).first();
      let outputPath = path.join(OUTPUT_DIR, config.name);
      if (await target.count() > 0) {
        await target.screenshot({ path: outputPath });
      } else {
        await page.screenshot({ path: outputPath, fullPage: false });
      }

      const size = fs.statSync(outputPath).size;
      console.log(`  ✓ 写入 ${outputPath} (${(size / 1024).toFixed(1)} KB)\n`);
      success++;
    } catch (err) {
      console.error(`  ✗ 失败：${err.message}\n`);
      failed++;
    } finally {
      await page.close();
    }
  }

  await browser.close();

  console.log(`\n📊 总结：成功 ${success} / 失败 ${failed} / 总共 ${SCREENSHOTS.length}`);
  console.log(`💡 v3.1 升级计划：macOS runner + launchPersistentContext + nativeScreenshot`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});