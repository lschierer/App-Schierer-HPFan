import { html, type CSSResultGroup, type TemplateResult } from "lit";
import { property } from "lit/decorators.js";

import {
  SpectrumElement,
  defineElement,
} from "@adobe/spectrum-wc-core/element/index.js";

import styles from "./site-split-view.css";

/**
 * Two panes side by side with a draggable, keyboard-operable divider between them. The start
 * pane is the one that resizes; the end pane takes the rest.
 *
 * Gen2 has no split view yet (it is on the migration list but not started), so this stands
 * in. It follows the accessibility analysis written for the eventual `swc-split-view`
 * (CONTRIBUTOR-DOCS/03_project-planning/03_components/split-view): the divider is a focusable
 * `role="separator"` that behaves as a range widget, with a name, an orientation and
 * `aria-valuenow`/`min`/`max`, and every drag has a keyboard equivalent.
 *
 * MARKUP. The three parts are server-rendered light-DOM children, so the page lays out the
 * same before this script runs as after:
 *
 *   <site-split-view storage-key="pagi:nav-width" label="Resize navigation sidebar">
 *     <div slot="start" id="nav">…</div>
 *     <div slot="splitter" aria-hidden="true"></div>
 *     <div slot="end" id="main">…</div>
 *   </site-split-view>
 *
 * The splitter is decoration until this element upgrades it into a control, which is why it
 * starts `aria-hidden`: without JavaScript there is nothing for it to do.
 *
 * The width is published as `--site-split-start` on this element, which the start pane reads
 * (styles/global.css). Below `breakpoint` the stylesheet takes the pane and splitter out of
 * the layout and this element ignores input.
 *
 * KEYS (as before): Left/Right move by `step`, with Shift by `big-step`; Home goes to the
 * minimum, End to the maximum. Arrow directions follow the writing direction.
 *
 * @element site-split-view
 * @slot start - The pane that resizes.
 * @slot splitter - The divider.
 * @slot end - The pane that fills the remainder.
 */
export class SiteSplitView extends SpectrumElement {
  public static override get styles(): CSSResultGroup {
    return [styles];
  }

  /** `localStorage` key under which the chosen width persists. Unset: not persisted. */
  @property({ type: String, attribute: "storage-key" })
  public storageKey?: string;

  /** Accessible name of the divider. */
  @property({ type: String })
  public label = "Resize panes";

  /** Smallest width of the start pane, px. */
  @property({ type: Number, attribute: "min-start" })
  public minStart = 180;

  /** Width always left for the end pane, px, whatever the window size. */
  @property({ type: Number, attribute: "min-end" })
  public minEnd = 320;

  @property({ type: Number })
  public step = 10;

  @property({ type: Number, attribute: "big-step" })
  public bigStep = 50;

  /** Viewport width, px, below which the panes are not side by side and input is ignored. */
  @property({ type: Number })
  public breakpoint = 768;

  private get splitter(): HTMLElement | null {
    return this.querySelector<HTMLElement>(':scope > [slot="splitter"]');
  }

  private get startPane(): HTMLElement | null {
    return this.querySelector<HTMLElement>(':scope > [slot="start"]');
  }

  private get narrow(): boolean {
    return window.innerWidth < this.breakpoint;
  }

  private get maxWidth(): number {
    return Math.max(this.minStart, window.innerWidth - this.minEnd);
  }

  private clamp(width: number): number {
    return Math.min(Math.max(width, this.minStart), this.maxWidth);
  }

  public override connectedCallback(): void {
    super.connectedCallback();
    window.addEventListener("resize", this.syncBounds);
  }

  public override disconnectedCallback(): void {
    window.removeEventListener("resize", this.syncBounds);
    super.disconnectedCallback();
  }

  protected override firstUpdated(): void {
    const splitter = this.splitter;
    const pane = this.startPane;
    if (!splitter || !pane) {
      return;
    }

    // Turn the decoration into a control.
    splitter.classList.add("is-draggable");
    splitter.removeAttribute("aria-hidden");
    splitter.setAttribute("role", "separator");
    splitter.setAttribute("aria-orientation", "vertical");
    splitter.setAttribute("aria-label", this.label);
    splitter.setAttribute("aria-valuemin", String(this.minStart));
    splitter.setAttribute("tabindex", "0");
    if (pane.id) {
      splitter.setAttribute("aria-controls", pane.id);
    }

    splitter.addEventListener("pointerdown", this.handlePointerDown);
    splitter.addEventListener("keydown", this.handleKeydown);

    const stored = this.readStored();
    if (stored !== undefined) {
      this.apply(stored, false);
    } else {
      splitter.setAttribute("aria-valuenow", String(this.paneWidth()));
    }
    this.syncBounds();
  }

  private paneWidth(): number {
    return Math.round(this.startPane?.getBoundingClientRect().width ?? 0);
  }

  private readStored(): number | undefined {
    if (!this.storageKey) {
      return undefined;
    }
    try {
      const value = Number(localStorage.getItem(this.storageKey) ?? NaN);
      return Number.isFinite(value) && value > 0 ? value : undefined;
    } catch {
      // Storage blocked: the width still works for this page, it just is not remembered.
      return undefined;
    }
  }

  private write(width: number): void {
    if (!this.storageKey) {
      return;
    }
    try {
      localStorage.setItem(this.storageKey, String(Math.round(width)));
    } catch {
      // Private browsing or a full quota. Not worth surfacing.
    }
  }

  private apply(width: number, persist: boolean): void {
    const next = this.clamp(width);
    this.style.setProperty("--site-split-start", `${next}px`);
    this.splitter?.setAttribute("aria-valuenow", String(Math.round(next)));
    if (persist) {
      this.write(next);
    }
  }

  private syncBounds = (): void => {
    this.splitter?.setAttribute("aria-valuemax", String(Math.round(this.maxWidth)));
    // A window that shrank can leave the stored width wider than is now allowed.
    if (!this.narrow && this.paneWidth() > this.maxWidth) {
      this.apply(this.maxWidth, false);
    }
  };

  private get rtl(): boolean {
    return getComputedStyle(this).direction === "rtl";
  }

  // Pointer events rather than mouse events, so a trackpad, a touchscreen and a pen all
  // work from one code path. Capture keeps the drag alive when the pointer outruns the
  // 2px-wide splitter, which it always does.
  private handlePointerDown = (event: PointerEvent): void => {
    const splitter = this.splitter;
    if (!splitter || this.narrow) {
      return;
    }
    event.preventDefault();

    const startX = event.clientX;
    const startWidth = this.paneWidth();
    splitter.setPointerCapture(event.pointerId);

    const onMove = (move: PointerEvent): void => {
      // Right-to-left flips which direction widens the start pane.
      const delta = move.clientX - startX;
      this.apply(startWidth + (this.rtl ? -delta : delta), false);
    };
    const onUp = (): void => {
      splitter.removeEventListener("pointermove", onMove);
      splitter.removeEventListener("pointerup", onUp);
      splitter.removeEventListener("pointercancel", onUp);
      // Persist once, at the end, not on every pointermove.
      this.apply(this.paneWidth(), true);
    };
    splitter.addEventListener("pointermove", onMove);
    splitter.addEventListener("pointerup", onUp);
    splitter.addEventListener("pointercancel", onUp);
  };

  private handleKeydown = (event: KeyboardEvent): void => {
    if (this.narrow) {
      return;
    }
    const width = this.paneWidth();
    const step = event.shiftKey ? this.bigStep : this.step;
    // ArrowRight moves the divider to the right. In a right-to-left layout the start pane
    // is on the right, so that makes it narrower.
    const direction = this.rtl ? -1 : 1;
    let next: number;

    switch (event.key) {
      case "ArrowLeft":
        next = width - step * direction;
        break;
      case "ArrowRight":
        next = width + step * direction;
        break;
      case "Home":
        next = this.minStart;
        break;
      case "End":
        next = this.maxWidth;
        break;
      default:
        return;
    }
    event.preventDefault();
    this.apply(next, true);
  };

  protected override render(): TemplateResult {
    return html`
      <slot name="start"></slot>
      <slot name="splitter"></slot>
      <slot name="end"></slot>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "site-split-view": SiteSplitView;
  }
}

defineElement("site-split-view", SiteSplitView);
