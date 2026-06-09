# Playwright E2E Testing — Liders CRM Platform

## פקודה: `/playwright-crm`

בדיקות E2E אוטומטיות לכל flows של Admin Dashboard.

---

## התקנה

```bash
npm install -D @playwright/test
npx playwright install chromium
```

### `playwright.config.ts`
```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  use: {
    baseURL: 'http://localhost:8080',
    locale: 'he-IL',
    timezoneId: 'Asia/Jerusalem',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'mobile', use: { viewport: { width: 390, height: 844 } } },
  ],
});
```

---

## Test Suites

### 1. Auth Flow
```typescript
// tests/e2e/auth.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Auth Flow', () => {
  test('כניסה עם פרטים נכונים', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#auth-screen')).toBeVisible();

    await page.fill('#email-input', 'Liders.crm@gmail.com');
    await page.fill('#password-input', 'LidersCRM_2026!');
    await page.click('#login-btn');

    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('.topbar-logo')).toContainText('Liders');
  });

  test('כניסה עם פרטים שגויים מציגה שגיאה', async ({ page }) => {
    await page.goto('/');
    await page.fill('#email-input', 'wrong@email.com');
    await page.fill('#password-input', 'wrongpassword');
    await page.click('#login-btn');
    await expect(page.locator('#auth-error')).toBeVisible();
  });

  test('יציאה מנתקת את המשתמש', async ({ page }) => {
    // login first...
    await page.click('.btn-logout');
    await expect(page.locator('#auth-screen')).toBeVisible();
  });
});
```

### 2. Accounts Management
```typescript
// tests/e2e/accounts.spec.ts
test.describe('Accounts', () => {
  test.beforeEach(async ({ page }) => {
    // login before each test
    await page.goto('/');
    await page.fill('#password-input', 'LidersCRM_2026!');
    await page.click('#login-btn');
    await page.click('.nav-tab:nth-child(2)'); // לקוחות פלטפורמה
  });

  test('טבלת לקוחות מוצגת', async ({ page }) => {
    await expect(page.locator('#accounts-tbody tr')).not.toHaveCount(0);
  });

  test('הוספת לקוח חדש', async ({ page }) => {
    await page.click('button:has-text("+ הוסף לקוח")');
    await expect(page.locator('#account-modal.open')).toBeVisible();

    await page.fill('#acc-business-name', 'עסק בדיקה');
    await page.fill('#acc-owner-name', 'בעל בדיקה');
    await page.click('#account-save-btn');

    await expect(page.locator('#toast.success')).toBeVisible();
  });

  test('חיפוש מסנן תוצאות', async ({ page }) => {
    await page.fill('#accounts-search', 'xxxnotexist');
    const rows = page.locator('#accounts-tbody tr');
    await expect(rows).toHaveCount(1); // empty state row
  });
});
```

### 3. Invoices
```typescript
// tests/e2e/invoices.spec.ts
test.describe('Invoices', () => {
  test('סימון חשבונית כשולם', async ({ page }) => {
    // navigate to invoices tab
    await page.click('.nav-tab:nth-child(3)');
    const markPaidBtn = page.locator('button[title="סמן כשולם"]').first();
    if (await markPaidBtn.isVisible()) {
      await markPaidBtn.click();
      await expect(page.locator('#toast.success')).toBeVisible();
    }
  });
});
```

### 4. Mobile Responsiveness
```typescript
test.describe('Mobile', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('dashboard נטען במובייל', async ({ page }) => {
    await page.goto('/');
    const dir = await page.$eval('html', el => el.getAttribute('dir'));
    expect(dir).toBe('rtl');
  });
});
```

---

## CI Integration

```yaml
# .github/workflows/e2e.yml
name: E2E Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      - run: npx playwright test
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: playwright-report/
```

---

## פקודות שימושיות

```bash
npx playwright test                    # כל הבדיקות
npx playwright test --ui               # UI mode
npx playwright test auth.spec.ts       # קובץ ספציפי
npx playwright test --headed           # עם browser נראה
npx playwright codegen http://localhost:8080  # הקלטת בדיקות חדשות
```
