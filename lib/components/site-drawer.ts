import { html, type CSSResultGroup, type TemplateResult } from "lit";
import { property, query } from "lit/decorators.js";

import {
  SpectrumElement,
  defineElement,
} from "@adobe/spectrum-wc-core/element/index.js";

import "@adobe/spectrum-wc/components/close-button/swc-close-button.js";

import styles from "./site-drawer.css";

/**
 * A slide-in navigation panel for small screens, opened by a button the page supplies.
 *
 * Gen2 has no drawer or side sheet, so this stands in. It is a native modal `<dialog>`
 * (`showModal()`), which is the right foundation rather than a convenient one: the browser
 * supplies the focus trap, makes everything behind the panel inert (so a screen reader's
 * virtual cursor cannot wander off into the page), handles Escape, and returns focus to the
 * opener on close. The previous drawer was a `<div>` that did none of those: Tab walked out
 * of it into the page behind.
 *
 * MARKUP. The opener is a light-DOM child in `slot="toggle"`, so it stays where the page's
 * layout wants it (the header) and works as a plain element before this script runs:
 *
 *   <site-drawer label="Site navigation" close-label="Close navigation">
 *     <swc-action-button slot="toggle" accessible-label="Navigation menu">…</swc-action-button>
 *     …the panel's content…
 *   </site-drawer>
 *
 * The opener's `aria-expanded` is kept in step. `aria-controls` is deliberately absent: the
 * controlled element is inside this shadow root, where an IDREF from the light DOM cannot
 * reach it.
 *
 * Closes on: Escape, the close button, a click on the backdrop, following any link inside
 * (a link followed from a page restored out of the back/forward cache would otherwise find
 * the panel still open), and the viewport growing past `breakpoint`, where the header's own
 * navigation takes over and a modal that nothing can see would leave the page inert.
 *
 * @element site-drawer
 * @slot toggle - The button that opens the drawer.
 * @slot - The panel's content.
 * @fires site-drawer-open - After the drawer opens.
 * @fires site-drawer-close - After the drawer closes, however it was closed.
 */
export class SiteDrawer extends SpectrumElement {
  public static override get styles(): CSSResultGroup {
    return [styles];
  }

  /** Accessible name of the panel. */
  @property({ type: String })
  public label = "Navigation";

  /** Accessible name of the close button. */
  @property({ type: String, attribute: "close-label" })
  public closeLabel = "Close navigation";

  /** Viewport width, px, at and above which the drawer closes itself. */
  @property({ type: Number })
  public breakpoint = 768;

  /** Whether the drawer is showing. Reflected so CSS and tests can see it. */
  @property({ type: Boolean, reflect: true })
  public open = false;

  @query("dialog")
  private dialog?: HTMLDialogElement;

  private wide = false;

  private widthQuery?: MediaQueryList;

  public override connectedCallback(): void {
    super.connectedCallback();
    this.addEventListener("click", this.handleHostClick);

    this.widthQuery = window.matchMedia(`(width >= ${this.breakpoint}px)`);
    this.widthQuery.addEventListener("change", this.handleWidthChange);
    this.wide = this.widthQuery.matches;
  }

  public override disconnectedCallback(): void {
    this.removeEventListener("click", this.handleHostClick);
    this.widthQuery?.removeEventListener("change", this.handleWidthChange);
    super.disconnectedCallback();
  }

  /** Open the drawer. */
  public show(): void {
    this.open = true;
  }

  /** Close the drawer. */
  public hide(): void {
    this.open = false;
  }

  private get toggleElement(): HTMLElement | null {
    return this.querySelector<HTMLElement>(':scope > [slot="toggle"]');
  }

  private handleWidthChange = (event: MediaQueryListEvent): void => {
    this.wide = event.matches;
    if (event.matches) {
      this.hide();
    }
  };

  // One listener on the host for the opener, which is a light-DOM child. Events from inside
  // this shadow root arrive retargeted to the host, and `closest` on the host finds nothing,
  // so the dialog's own clicks are not mistaken for the opener's.
  private handleHostClick = (event: Event): void => {
    const target = event.target as Element | null;
    if (target?.closest('[slot="toggle"]') && !this.wide) {
      this.show();
    }
  };

  // A click on the <dialog> element itself is a click on the backdrop: the dialog is
  // stretched over the whole viewport and the panel is a child of it, so a click that
  // lands on the panel or anything inside has a different target.
  private handleDialogClick = (event: MouseEvent): void => {
    if (event.target === this.dialog) {
      this.hide();
      return;
    }
    if (event.composedPath().some((node) => node instanceof HTMLAnchorElement)) {
      this.hide();
    }
  };

  private handleCloseClick = (): void => {
    this.hide();
  };

  // Escape. The browser would close the dialog itself; going through `open` keeps the
  // property, the attribute and the opener's aria-expanded in agreement.
  private handleCancel = (event: Event): void => {
    event.preventDefault();
    this.hide();
  };

  protected override updated(changed: Map<PropertyKey, unknown>): void {
    super.updated(changed);
    if (!changed.has("open")) {
      return;
    }

    const dialog = this.dialog;
    const toggle = this.toggleElement;
    toggle?.setAttribute("aria-expanded", String(this.open));

    if (this.open && dialog && !dialog.open) {
      dialog.showModal();
      // The close button is the first focusable thing in the panel; say so explicitly rather
      // than rely on the browser's choice.
      this.renderRoot.querySelector<HTMLElement>("swc-close-button")?.focus();
      this.dispatchEvent(
        new CustomEvent("site-drawer-open", { bubbles: true, composed: true }),
      );
    } else if (!this.open && dialog?.open) {
      dialog.close();
      toggle?.focus();
      this.dispatchEvent(
        new CustomEvent("site-drawer-close", { bubbles: true, composed: true }),
      );
    }
  }

  protected override firstUpdated(): void {
    // The opener starts out saying "collapsed", whatever the server rendered.
    this.toggleElement?.setAttribute("aria-expanded", String(this.open));
  }

  protected override render(): TemplateResult {
    return html`
      <slot name="toggle"></slot>
      <dialog
        aria-label=${this.label}
        @click=${this.handleDialogClick}
        @cancel=${this.handleCancel}
      >
        <div class="panel">
          <div class="bar">
            <swc-close-button
              accessible-label=${this.closeLabel}
              @click=${this.handleCloseClick}
            ></swc-close-button>
          </div>
          <slot></slot>
        </div>
      </dialog>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "site-drawer": SiteDrawer;
  }
}

defineElement("site-drawer", SiteDrawer);
