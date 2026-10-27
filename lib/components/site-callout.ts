import { html, type CSSResultGroup, type TemplateResult } from "lit";
import { property } from "lit/decorators.js";

import {
  SpectrumElement,
  defineElement,
} from "@adobe/spectrum-wc-core/element/index.js";

import styles from "./site-callout.css";

export const CALLOUT_VARIANTS = [
  "note",
  "tip",
  "important",
  "warning",
  "caution",
  "info",
] as const;

export type CalloutVariant = (typeof CALLOUT_VARIANTS)[number];

/**
 * An inline aside with a coloured background: the GitHub-style `> [!NOTE]` callouts in the
 * Markdown, and the author's notes on the appendix pages.
 *
 * WHY NOT AlertBannerBase. @adobe/spectrum-wc-core ships a base class for Spectrum's alert
 * banner, and it is the wrong parent for this. An alert banner is a pressing, dismissible,
 * system-level message with three variants (neutral, info, negative) and a close event. A
 * callout is neither dismissible nor urgent, has five variants of its own, and must NOT be
 * announced as an alert. Inheriting the banner would mean fighting its `open`,
 * `dismissible`, `close()` and Escape handling and suppressing its variant validation for
 * four of our six variants. SpectrumElement, the layer below, is what gen2's own components
 * extend, and gives the same versioning and dev-warning behaviour with none of that.
 *
 * ACCESSIBILITY. `role="note"` (ancillary content), deliberately not `alert` or `status`:
 * those are live regions that interrupt a screen reader, which a static aside should not.
 *
 * @element site-callout
 * @slot - The callout's content.
 */
export class SiteCallout extends SpectrumElement {
  public static override get styles(): CSSResultGroup {
    return [styles];
  }

  /**
   * Which kind of callout. Selects the background colour; unknown values fall back to the
   * `note` appearance.
   */
  @property({ type: String, reflect: true })
  public variant: CalloutVariant = "note";

  public override connectedCallback(): void {
    super.connectedCallback();
    if (!this.hasAttribute("role")) {
      this.setAttribute("role", "note");
    }
  }

  protected override render(): TemplateResult {
    return html`
      <slot></slot>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "site-callout": SiteCallout;
  }
}

defineElement("site-callout", SiteCallout);
