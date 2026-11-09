{{flutter_js}}
{{flutter_build_config}}

// No service worker: older versions used one, and it kept serving stale files
// (e.g. an old icon font with blank icons) long after updates. index.html and
// flutter_service_worker.js (tool/build_web.ps1) remove any still installed.
//
// Browsers can also hold an old copy of a font in their normal cache and
// reuse it without asking the server. Once per new version, fetch these
// files fresh (which overwrites the cached copies) before the app starts.
(async function () {
  var version = '__BUILD_ID__'; // stamped by tool/build_web.ps1
  var files = [
    'assets/FontManifest.json',
    'assets/AssetManifest.bin.json',
    'assets/AssetManifest.bin',
    'assets/fonts/MaterialIcons-Regular.otf',
    'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  ];
  try {
    if (localStorage.getItem('lm-assets-version') !== version) {
      await Promise.all(files.map(function (f) {
        return fetch(f, { cache: 'reload' }).catch(function () {});
      }));
      localStorage.setItem('lm-assets-version', version);
    }
  } catch (e) { /* storage blocked: just start */ }
  _flutter.loader.load();
})();
