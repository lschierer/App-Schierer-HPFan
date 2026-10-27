import { css, html, type CSSResultGroup, type TemplateResult } from "lit";
import { property } from "lit/decorators.js";

import {
  SpectrumElement,
  defineElement,
} from "@adobe/spectrum-wc-core/element/index.js";

/**
 * Behaviour for a server-rendered disclosure tree (the sidebar navigation, the family tree).
 *
 * The tree itself stays plain nested lists in the light DOM, styled by styles/navigation.css.
 * That is deliberate: the sidebar tree is about 1,300 nodes on every page, and a custom
 * element per node would cost a shadow root each. One element around the whole tree, doing
 * its work by event delegation, costs one.
 *
 * WHAT IT DOES
 *  - A click on a `.site-tree-toggle` button flips its `aria-expanded` and shows or hides
 *    the list it `aria-controls`. Expanding also reveals any descendants the server marked
 *    `hidden` (the server hides everything outside the currently relevant branch).
 *  - With `mobile-socket`, moves itself into that element below `mobile-breakpoint` and
 *    back above it. The tree is far too large to render twice, so the one copy changes
 *    parents, taking its open/closed state with it.
 *
 * WHAT IT DOES NOT DO: tree keyboard navigation. This is disclosure navigation, not an ARIA
 * tree, so every link and button is an ordinary tab stop and Enter/Space on a toggle is all
 * the keyboard support the pattern calls for.
 *
 * @element site-tree
 * @slot - The tree markup.
 */
export class SiteTree extends SpectrumElement {
  public static override get styles(): CSSResultGroup {
    return css`
      :host {
        display: block;
      }
    `;
  }

  /** `id` of the element to move into on small viewports. Unset: never moves. */
  @property({ type: String, attribute: "mobile-socket" })
  public mobileSocket?: string;

  /** Viewport width, in px, below which the tree moves into the socket. */
  @property({ type: Number, attribute: "mobile-breakpoint" })
  public mobileBreakpoint = 768;

  /** Where the tree lives above the breakpoint, recorded the first time it is connected. */
  private home?: { parent: Node; before: Node | null };

  private query?: MediaQueryList;

  public override connectedCallback(): void {
    super.connectedCallback();
    this.addEventListener("click", this.handleClick);

    // Moving the element re-runs this callback; the first parent is the real home.
    this.home ??= { parent: this.parentNode as Node, before: this.nextSibling };

    if (this.mobileSocket && !this.query) {
      // `width < N` rather than `max-width: N-1`: they differ at the fractional widths a
      // zoomed viewport reports, and the stylesheets use this form.
      this.query = window.matchMedia(`(width < ${this.mobileBreakpoint}px)`);
      this.query.addEventListener("change", this.relocate);
    }
    this.relocate();
  }

  public override disconnectedCallback(): void {
    this.removeEventListener("click", this.handleClick);
    super.disconnectedCallback();
  }

  /** Expand or collapse one branch. */
  public setExpanded(toggle: Element, expanded: boolean): void {
    toggle.setAttribute("aria-expanded", String(expanded));

    const id = toggle.getAttribute("aria-controls");
    const list = id ? this.querySelector<HTMLElement>(`#${CSS.escape(id)}`) : null;
    if (!list) {
      return;
    }
    list.hidden = !expanded;

    if (expanded) {
      for (const item of list.querySelectorAll<HTMLElement>("li[hidden]")) {
        item.hidden = false;
      }
    }
  }

  private handleClick = (event: Event): void => {
    const target = event.target as Element | null;
    const toggle = target?.closest<HTMLElement>(
      "button.site-tree-toggle[aria-expanded]",
    );
    if (!toggle || !this.contains(toggle)) {
      return;
    }
    event.preventDefault();
    this.setExpanded(toggle, toggle.getAttribute("aria-expanded") !== "true");
  };

  private relocate = (): void => {
    if (!this.query || !this.mobileSocket || !this.home) {
      return;
    }
    const socket = document.getElementById(this.mobileSocket);
    if (!socket) {
      return;
    }

    if (this.query.matches) {
      if (this.parentNode !== socket) {
        socket.append(this);
      }
    } else if (this.parentNode === socket) {
      const { parent, before } = this.home;
      parent.insertBefore(this, before?.parentNode === parent ? before : null);
    }
  };

  protected override render(): TemplateResult {
    return html`
      <slot></slot>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "site-tree": SiteTree;
  }
}

defineElement("site-tree", SiteTree);
