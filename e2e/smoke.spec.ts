import { test, expect, type Page, type Response } from '@playwright/test';
import { E2E_BOOK } from '../scripts/seed-e2e';

/**
 * Book Vault web smoke (Phase 6).
 *
 * Drives the shared web UI end-to-end against the local stack (Docker Postgres +
 * `npm run dev`, both wired up by playwright.config.ts / global-setup.ts) and
 * validates the backend two ways:
 *   1. A response guard that fails the test on ANY 5xx the browser observes —
 *      the reliable stand-in for "scan the server log for errors".
 *   2. A direct GET /api/library assertion (reusing the browser's session
 *      cookie) confirming the add actually persisted server-side, not just in
 *      the UI.
 *
 * Flow: login → search the seeded book → open detail → play (assert player
 * appears + toggles) → add to library → confirm it shows on /library and in the
 * library API.
 *
 * Fixtures come from scripts/seed-e2e.ts (a media-free, series-free book), so
 * "Add to Library" is a single click with no series dialog, and the play page
 * renders the real player (audioUrl is set) without needing audio bytes.
 */

const USERNAME = process.env.TEST_USER_USERNAME || 'testuser';
const PASSWORD = process.env.TEST_USER_PASSWORD || 'password123';

/** Fail loudly if the backend returns a 5xx anywhere during the run. */
function guardServerErrors(page: Page): { serverErrors: string[] } {
  const serverErrors: string[] = [];
  page.on('response', (res: Response) => {
    if (res.status() >= 500) {
      serverErrors.push(`${res.status()} ${res.request().method()} ${res.url()}`);
    }
  });
  return { serverErrors };
}

async function login(page: Page): Promise<void> {
  // Logging in reliably in CI has two distinct races, so we retry the WHOLE
  // submit until we actually land authenticated on '/':
  //
  //   1. Pre-hydration native submit. The login page is a client component whose
  //      onSubmit={handleSubmit} calls signIn(). Click before React hydrates and
  //      the browser does a native form GET (no auth) — URL keeps ?username=...
  //   2. Cookie not yet honored. Even once signIn's credentials callback fires
  //      and handleSubmit does window.location.href='/', the session cookie may
  //      not be readable by middleware on the very next request yet, so '/'
  //      bounces back to /auth/login?callbackUrl=%2F. (This is the CI flake.)
  //
  // Waiting for the callback isn't enough (covers only #1); we must confirm the
  // final landing on '/'. If we bounce back to the login page, reload and retry.
  for (let attempt = 1; attempt <= 4; attempt++) {
    await page.goto('/auth/login', { waitUntil: 'networkidle' });

    await page.locator('#username').fill(USERNAME);
    await page.locator('#password').fill(PASSWORD);

    // The credentials callback only fires if handleSubmit ran, i.e. React is
    // hydrated. On a freshly-compiled dev route (CI, cold server) the first
    // click can beat hydration → native form GET, no callback. Watch for the
    // callback; if it doesn't come, this attempt was a native submit → retry.
    const callback = page
      .waitForResponse((r) => r.url().includes('/api/auth/callback/credentials'), {
        timeout: 10_000,
      })
      .catch(() => null);
    await page.getByRole('button', { name: 'Sign in' }).click();
    if (!(await callback)) {
      if (attempt === 4) throw new Error('Login never triggered signIn (client never hydrated?)');
      continue; // pre-hydration native submit — reload and retry.
    }

    // signIn succeeded → handleSubmit does window.location.href='/'. But the
    // session cookie may not be honored by middleware on the very next request,
    // bouncing '/' back to /auth/login. If so, reload and retry the whole login.
    try {
      await page.waitForURL((url) => url.pathname === '/', { timeout: 15_000 });
    } catch {
      if (attempt === 4) {
        throw new Error('Login authenticated but never landed on / (session not honored)');
      }
      continue;
    }

    await expect(page.getByText(USERNAME).first()).toBeVisible();
    return;
  }
}

test('web smoke: login → search → detail → play → add to library', async ({ page }) => {
  const { serverErrors } = guardServerErrors(page);

  // 1. Login.
  await login(page);

  // 2. Search for the seeded fixture book from the home page.
  await page.getByPlaceholder('Search books, authors, narrators, series...').fill(E2E_BOOK.title);
  await page.getByRole('button', { name: 'Search' }).click();
  await page.waitForURL('**/search**');
  await expect(page.getByRole('heading', { name: /Search results for/ })).toBeVisible();

  // The fixture title is distinctive, so exactly one result card should match.
  const resultCard = page.locator('a[href^="/books/"]').filter({ hasText: E2E_BOOK.title });
  await expect(resultCard).toHaveCount(1);

  // 3. Open the book detail page.
  await resultCard.click();
  await page.waitForURL('**/books/**');
  await expect(page.getByRole('heading', { level: 1, name: E2E_BOOK.title })).toBeVisible();

  // Capture the book id from the URL for the API assertion later.
  const bookId = page.url().match(/\/books\/([^/?#]+)/)?.[1];
  expect(bookId, 'should have a book id in the URL').toBeTruthy();

  // 4. Play: navigate to the play page and confirm the player renders + toggles.
  await page.getByRole('link', { name: 'Play Book' }).click();
  await page.waitForURL('**/play');
  // PlaybackClient shows a spinner until GET /api/progress resolves; wait it out.
  // exact:true — otherwise "Play" substring-matches "Set playback speed to ...".
  const playButton = page.getByRole('button', { name: 'Play', exact: true });
  await expect(playButton).toBeVisible();
  await expect(page.locator('audio')).toBeAttached();
  // The aria-label flips Play → Pause on click (React state), proving the
  // control is wired even though no audio decodes in this fixture.
  await playButton.click();
  await expect(page.getByRole('button', { name: 'Pause', exact: true })).toBeVisible();

  // 5. Add to library from the detail page (no series → single click).
  await page.goto(`/books/${bookId}`);
  const addButton = page.getByRole('button', { name: 'Add to Library' });
  await expect(addButton).toBeVisible();
  await addButton.click();
  await expect(page.getByRole('button', { name: 'In Library' })).toBeVisible();

  // 6. Confirm it appears on the library page.
  await page.goto('/library');
  await expect(page.getByRole('heading', { level: 1, name: 'My Library' })).toBeVisible();
  await expect(page.getByRole('heading', { name: E2E_BOOK.title })).toBeVisible();

  // 7. Backend validation: the add persisted server-side (reuses session cookie).
  const libraryResponse = await page.request.get('/api/library');
  expect(libraryResponse.ok()).toBeTruthy();
  const library = await libraryResponse.json();
  // GET /api/library returns { books: [...], total }; each book has a top-level id.
  const bookIds: string[] = (library.books ?? []).map((b: { id: string }) => b.id);
  expect(bookIds, 'seeded book should be in the library API response').toContain(bookId);

  // No 5xx anywhere during the flow.
  expect(serverErrors, `server returned 5xx:\n${serverErrors.join('\n')}`).toHaveLength(0);
});
