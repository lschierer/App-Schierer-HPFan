// Thin shim over the shared CSS build in the framework package.
//
// The pipeline, the plugin order, and the reasoning behind all of it live in
// ../../PAGI-WebServer/scripts/build-css.ts - one copy for every site that extends the
// framework, rather than the three byte-identical copies that used to drift apart.
// Only the stylesheet directory differs between sites, so only that is passed here.
//
// The output directory still comes from argv, so `pnpm build:css` is unchanged, and
// stylelint.config.js is still resolved from this project.
//
// legacyTokens is off: this site is on Spectrum Web Components gen2 and its stylesheets
// import the --swc-* tokens from @adobe/spectrum-wc, so the Spectrum 1 --spectrum-* layer
// the shared build can generate is not wanted here.

import { buildCSS } from "../../PAGI-WebServer/scripts/build-css";

await buildCSS({ stylesDir: "styles", legacyTokens: false });
