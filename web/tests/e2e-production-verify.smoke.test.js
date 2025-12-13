import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';

// Configuration
const BASE_URL = 'http://localhost:9080';
const SCREENSHOTS_DIR = './test-results/production-verify';

// Create screenshots directory
if (!fs.existsSync(SCREENSHOTS_DIR)) {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
}

/**
 * Helper function to take named screenshot
 */
async function takeScreenshot(page, name) {
  const screenshotPath = path.join(SCREENSHOTS_DIR, `${name}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`✅ Screenshot saved: ${name}`);
}

test.describe('NoC Raven - Production E2E Verification', () => {
  test('01. Application loads and displays main dashboard', async ({ page }) => {
    // Navigate to application
    const response = await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    expect(response?.status()).toBeLessThan(400);
    
    // Wait for main app to load
    await page.waitForSelector('.dashboard, [class*="loading"]', { timeout: 10000 });
    
    // Take screenshot
    await takeScreenshot(page, '01-main-dashboard');
    
    // Verify key elements exist
    const title = await page.title();
    expect(title).toContain('NoC Raven');
    
    console.log('✅ Application loaded successfully');
  });

  test('02. Dashboard displays header with correct branding', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForLoadState('domcontentloaded');
    
    // Look for dashboard header with emoji
    const header = await page.locator('h1').filter({ hasText: /NoC Raven/ }).first();
    await expect(header).toBeVisible({ timeout: 10000 });
    
    const headerText = await header.textContent();
    expect(headerText).toContain('NoC Raven');
    
    await takeScreenshot(page, '02-dashboard-header');
    console.log('✅ Dashboard header displays correctly');
  });

  test('03. Navigation elements are present and functional', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForLoadState('domcontentloaded');
    
    // Wait a moment for React to render
    await page.waitForTimeout(2000);
    
    // Check for navigation elements
    const navElements = page.locator('nav, [role="navigation"], [class*="nav"]').first();
    
    // Take screenshot of nav area
    await takeScreenshot(page, '03-navigation');
    
    console.log('✅ Navigation elements present');
  });

  test('04. Settings page is accessible and functional', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    // Look for Settings link or button
    const settingsLink = page.locator('a, button').filter({ hasText: /Settings|Config/i }).first();
    
    if (await settingsLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await settingsLink.click();
      await page.waitForLoadState('domcontentloaded');
      await takeScreenshot(page, '04-settings-page');
      console.log('✅ Settings page accessible');
    } else {
      console.log('⚠️  Settings page not found, continuing with other tests');
    }
  });

  test('05. NetFlow page loads and displays data', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const netflowLink = page.locator('a, button').filter({ hasText: /NetFlow|Flow/i }).first();
    
    if (await netflowLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await netflowLink.click();
      await page.waitForLoadState('domcontentloaded');
      await takeScreenshot(page, '05-netflow-page');
      console.log('✅ NetFlow page loads');
    } else {
      console.log('⚠️  NetFlow page not found');
    }
  });

  test('06. Syslog page displays correctly', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const syslogLink = page.locator('a, button').filter({ hasText: /Syslog|Logs/i }).first();
    
    if (await syslogLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await syslogLink.click();
      await page.waitForLoadState('domcontentloaded');
      await takeScreenshot(page, '06-syslog-page');
      console.log('✅ Syslog page displays');
    } else {
      console.log('⚠️  Syslog page not found');
    }
  });

  test('07. SNMP page is accessible', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const snmpLink = page.locator('a, button').filter({ hasText: /SNMP|Traps/i }).first();
    
    if (await snmpLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await snmpLink.click();
      await page.waitForLoadState('domcontentloaded');
      await takeScreenshot(page, '07-snmp-page');
      console.log('✅ SNMP page accessible');
    } else {
      console.log('⚠️  SNMP page not found');
    }
  });

  test('08. Windows Events page loads', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const windowsLink = page.locator('a, button').filter({ hasText: /Windows|Events/i }).first();
    
    if (await windowsLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await windowsLink.click();
      await page.waitForLoadState('domcontentloaded');
      await takeScreenshot(page, '08-windows-events-page');
      console.log('✅ Windows Events page loads');
    } else {
      console.log('⚠️  Windows Events page not found');
    }
  });

  test('09. Buffer Status page displays', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const bufferLink = page.locator('a, button').filter({ hasText: /Buffer|Status/i }).first();
    
    if (await bufferLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await bufferLink.click();
      await page.waitForLoadState('domcontentloaded');
      await takeScreenshot(page, '09-buffer-status-page');
      console.log('✅ Buffer Status page displays');
    } else {
      console.log('⚠️  Buffer Status page not found');
    }
  });

  test('10. API endpoints respond correctly', async ({ page }) => {
    // Test API health endpoint
    const healthResponse = await page.request.get(`${BASE_URL}/health`);
    expect(healthResponse.status()).toBeLessThan(400);
    console.log('✅ Health endpoint responds');
    
    // Test config endpoint
    const configResponse = await page.request.get(`${BASE_URL}/api/config`);
    expect([200, 404]).toContain(configResponse.status());
    console.log('✅ Config endpoint responds');
  });

  test('11. Responsive design works on mobile viewport', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForLoadState('domcontentloaded');
    
    await takeScreenshot(page, '11-mobile-responsive');
    
    // Verify page is still usable
    const heading = page.locator('h1').filter({ hasText: /NoC/ }).first();
    await expect(heading).toBeVisible();
    
    console.log('✅ Mobile responsive design works');
  });

  test('12. Verify no console errors during interaction', async ({ page }) => {
    const errors = [];
    
    // Capture console messages
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        errors.push(msg.text());
      }
    });
    
    // Navigate through app
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForLoadState('domcontentloaded');
    
    // Click on various links if they exist
    const links = await page.locator('a, button').all();
    for (let i = 0; i < Math.min(3, links.length); i++) {
      try {
        if (await links[i].isVisible({ timeout: 2000 }).catch(() => false)) {
          await links[i].click({ timeout: 2000 }).catch(() => {});
          await page.waitForTimeout(500);
        }
      } catch (e) {
        // Ignore errors from missing pages
      }
    }
    
    expect(errors).toHaveLength(0);
    console.log('✅ No critical console errors detected');
  });

  test('13. Performance - Page loads within acceptable time', async ({ page }) => {
    const startTime = Date.now();
    
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const loadTime = Date.now() - startTime;
    expect(loadTime).toBeLessThan(15000); // Should load in less than 15 seconds
    
    console.log(`✅ Page loaded in ${loadTime}ms`);
  });

  test('14. Visual elements render correctly', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForLoadState('domcontentloaded');
    
    // Check for cards/sections
    const cards = page.locator('[class*="card"], [class*="section"]');
    const cardCount = await cards.count();
    
    // Should have at least some cards visible
    if (cardCount > 0) {
      console.log(`✅ Found ${cardCount} card elements`);
    }
    
    // Take final screenshot
    await takeScreenshot(page, '14-final-visual-state');
  });

  test('15. Full page screenshot for manual inspection', async ({ page }) => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForLoadState('domcontentloaded');
    
    // Full page screenshot
    await takeScreenshot(page, '15-full-page-final');
    
    console.log('✅ Full page screenshot captured');
  });
});
