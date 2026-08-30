# Vendored three.js

`three.min.js` is the official minified UMD build of
[three.js](https://threejs.org) r128, the last release that ships a
self-contained non-module build with the geometry APIs this visualizer needs.

`ltsviz.write3DHtml` inlines this file into every generated 3D report so the
HTML is fully standalone and works offline. If the file is missing, generated
reports fall back to the jsDelivr CDN copy and still render when online.

To update: replace `three.min.js` with a newer r12x UMD build and re-run the
package tests (`tests/LTSVizTest.m`). r13x+ removed the UMD build; staying on
r128 is intentional.
