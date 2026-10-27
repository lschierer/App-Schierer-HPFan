// Registers the Spectrum Web Components (gen2) custom elements the site's markup uses.
//
// Only elements that appear in server-rendered HTML belong here. Typography and links are
// plain CSS classes in gen2 (styles/swc/text.css), so they need nothing from this file.
//
// Loaded from <head> on every page by layouts/default.tt, as a
// module so it runs after parsing without blocking it. Until it runs an undefined
// <swc-divider> would be a zero-height box, which styles/swc/text.css reserves space for.

import "@adobe/spectrum-wc/components/action-button/swc-action-button.js";
import "@adobe/spectrum-wc/components/card/swc-card.js";
import "@adobe/spectrum-wc/components/divider/swc-divider.js";
import "@adobe/spectrum-wc/components/icon/swc-icon.js";
// swc-close-button is imported by site-drawer, its only user.

// The site's own elements, built on gen2's SpectrumElement where gen2 has no equivalent.
import "./components/site-callout.js";
import "./components/site-drawer.js";
import "./components/site-split-view.js";
import "./components/site-tree.js";
