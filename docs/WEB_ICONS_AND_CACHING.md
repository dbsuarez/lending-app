# Web icons and caching: rules for anyone changing this app

Read this before you touch the web build, `web/`, `firebase.json`, icons, or
debug "blank icon" / "old version still showing" reports.

## What happened (November 2026)

Users saw **blank icons** on the web app: the columns button, Mark Personal,
Change Due Date, Refinance, the Personal Loans menu item. Fixes were declared
twice before the real causes were found. Three separate problems were
stacked:

1. **Icon tree-shaking damaged glyphs.** `flutter build web` trims
   `MaterialIcons-Regular.otf` to the icons the code uses (about 20 KB). In this
   Flutter version (3.38.5) the trimmed font had **empty glyphs** for some
   icons (`view_column`, `view_column_outlined`, `dashboard_outlined`,
   `calculate_outlined`, `savings`, `eco`, `assignment_turned_in_outlined`)
   even though the font's character map listed them. Which icons break depends
   on the set of icons used, so it changes from build to build.
2. **An old service worker kept serving stale files.** Earlier builds
   registered Flutter's service worker. It cached `index.html`, the icon font
   and more, and kept serving them after `--pwa-strategy=none` was adopted. Its
   replacement was an empty file, which waits and never takes over while a tab
   is open.
3. **The browser's normal HTTP cache reused an old font.** Even with the
   service worker gone and `Cache-Control: public,no-cache` on the server, the
   browser returned the old 20,524-byte font without asking the server. A
   request with `cache: 'no-store'` got the correct 1,645,184-byte font.

Every server-side check passed (deployed font correct, all icons present)
while the user still saw blanks. **The server was right; the user's browser
was not.**

## Rules

1. **Never turn icon tree-shaking back on.** Both build scripts pass
   `--no-tree-shake-icons` (`tool/build_web.ps1`, `tool/build_apk.ps1`). The
   full font costs about 1.6 MB once per version; blank icons cost far more.
2. **No service worker.** `web/flutter_bootstrap.js` calls
   `_flutter.loader.load()` without service-worker settings. Do not add one.
3. **Keep the kill switch.** `web/sw_kill_switch.js` is published as
   `build/web/flutter_service_worker.js` by `tool/build_web.ps1`. It takes over
   at once, deletes all caches, unregisters itself and reloads open pages.
   Browsers that visited an old version still need it; don't delete it.
4. **Keep the cleanup in `web/index.html`.** It unregisters any service worker,
   deletes caches and reloads once.
5. **Keep the once-per-version asset refresh.** `web/flutter_bootstrap.js`
   re-fetches the fonts and the font/asset manifests with `cache: 'reload'`
   (which overwrites the HTTP cache) whenever the build id changes. The build
   id is stamped into `__BUILD_ID__` by `tool/build_web.ps1`. If you add a
   custom font or a critical asset, add it to that list.
6. **Keep the update prompt.** The build writes `build/web/app_build.json`
   (`{"build_id": ...}`, never cached; see `firebase.json`).
   `lib/core/update/update_checker.dart` checks it 10 s after load, every
   5 minutes, and when the tab regains focus, and shows "A new version of the
   app is available" with Update / Later.
7. **`firebase.json` cache headers:** `assets/`, `canvaskit/`, `icons/` →
   `public,no-cache`. `index.html`, `main.dart.js`, `flutter_bootstrap.js`,
   `flutter_service_worker.js`, `version.json`, `app_build.json` →
   `no-cache,no-store,must-revalidate`.
8. **Avoid icons known to break if trimming ever returns:** use `view_week` /
   `view_week_outlined` for "columns", not `view_column`.

## How to debug a "blank icon" or "old version" report

Do not stop at checking the server. Reproduce what the user's browser gets.

1. **Is the deployed font complete?** It should be about 1.6 MB:
   `Invoke-WebRequest https://lending-manager-ph.web.app/assets/fonts/MaterialIcons-Regular.otf -OutFile x.otf`
2. **Does every used icon draw from that font?** List the code points of every
   `Icons.x` under `lib/` (from Flutter's `icons.dart`). Draw each one on a
   canvas with the font in a browser (Playwright), and flag glyphs with almost
   no ink. Checking the font's character map is **not** enough: trimmed fonts
   listed glyphs that drew nothing.
3. **What does the page actually receive?** Open the live site in Playwright.
   Its profile keeps old state, like a real user's browser. Check:
   - `navigator.serviceWorker.controller`, `getRegistrations()`, `caches.keys()`
   - the size of the icon font in page responses (`response.body().length`),
     and `fetch(url)` against `fetch(url, {cache: 'no-store'})`
4. **Confirm the fix visually** in that same browser before reporting it fixed.
5. **Tell the user right away** how to clear it themselves while the fix
   ships:
   - **Chrome or Edge:** icon left of the address → Site settings → Delete
     data → reopen.
   - **Android Chrome:** Settings → Site settings → All sites → the site →
     Delete & reset.

## Files

| File | Purpose |
|---|---|
| `tool/build_web.ps1` | full icon font; publishes the kill switch, stamps the build id, writes `app_build.json`, scans for credentials |
| `web/flutter_bootstrap.js` | no service worker; once-per-version fresh fetch of fonts and manifests |
| `web/index.html` | removes old service workers and caches, reloads once |
| `web/sw_kill_switch.js` | becomes `flutter_service_worker.js` |
| `lib/core/update/update_checker.dart` | "new version available" prompt |
| `firebase.json` | cache headers |
