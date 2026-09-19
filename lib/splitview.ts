// Makes the SplitView splitter actually split.
//
// The markup in layouts/default.tt and "Fan Fiction"/req4help/layout.tt has carried
// `<div tabindex="0" class="spectrum-SplitView-splitter">` all along, but nothing ever
// referenced it: focusable, styled, inert. Meanwhile the sidebar was pinned to
// max(250px, 20vw), and because the tree indents 16px per level a depth-5 label had only
// about 100px to render in - long enough for "Dumbledore's Philosophy",
// "Dumbledore's Treatment of Harry" and "Dumbledore's Vision for Society" to truncate to
// the same "Dumbledore'..." stub. Spectrum's tree-view guidance is explicit that the
// answer to a hierarchy deeper than the space available is an adjustable container, which
// is exactly what this element was put there to be.
//
// The width lives in a --nav-width custom property on <html>, read by div#nav in
// global.css, and is persisted so a chosen width survives navigation.

const STORAGE_KEY = 'pagi:nav-width';

// Below this the tree moves into the mobile drawer and the sidebar is not shown; matches
// the breakpoint in global.css and global_header.css.
const MOBILE_MAX = 767;

const MIN_WIDTH = 180;

/** Leave at least this much for the content pane, whatever the window size. */
const MIN_CONTENT_WIDTH = 320;

const splitter = document.querySelector<HTMLElement>(
  '.spectrum-SplitView--horizontal > .spectrum-SplitView-splitter',
);
const pane = document.getElementById('nav');

if (splitter && pane) {
  const maxWidth = () =>
    Math.max(MIN_WIDTH, window.innerWidth - MIN_CONTENT_WIDTH);

  const clamp = (width: number) =>
    Math.min(Math.max(width, MIN_WIDTH), maxWidth());

  const apply = (width: number, persist: boolean) => {
    const next = clamp(width);
    document.documentElement.style.setProperty('--nav-width', `${next}px`);
    splitter.setAttribute('aria-valuenow', String(Math.round(next)));
    if (persist) {
      try {
        localStorage.setItem(STORAGE_KEY, String(Math.round(next)));
      } catch {
        // Private browsing or a full quota: resizing still works for this page, it just
        // will not be remembered. Not worth surfacing.
      }
    }
  };

  // @spectrum-css/splitview gates its hover and active treatments on `.is-draggable`, and
  // draws the visible grab handle from a `.spectrum-SplitView-gripper` child. The
  // templates supplied neither, which is why a 2px-wide line was the only thing on screen
  // and finding it was guesswork. Both are added here rather than in the two layouts
  // because they advertise behaviour that only exists when this script has run.
  splitter.classList.add('is-draggable');
  if (!splitter.querySelector('.spectrum-SplitView-gripper')) {
    const gripper = document.createElement('div');
    gripper.className = 'spectrum-SplitView-gripper';
    splitter.append(gripper);
  }

  // role=separator with a value is what tells assistive technology this is a resize
  // control and where it currently sits. Set here rather than in the templates so the two
  // layouts do not have to agree, and because valuenow is only meaningful at runtime.
  splitter.setAttribute('role', 'separator');
  splitter.setAttribute('aria-orientation', 'vertical');
  splitter.setAttribute('aria-label', 'Resize navigation sidebar');
  splitter.setAttribute('aria-valuemin', String(MIN_WIDTH));

  const isMobile = () => window.innerWidth <= MOBILE_MAX;

  const syncBounds = () => {
    splitter.setAttribute('aria-valuemax', String(Math.round(maxWidth())));
    // A window that shrank can leave a stored width wider than now allowed.
    const current = pane.getBoundingClientRect().width;
    if (!isMobile() && current > maxWidth()) apply(maxWidth(), false);
  };

  const stored = Number(localStorage.getItem(STORAGE_KEY) ?? NaN);
  if (Number.isFinite(stored) && stored > 0) {
    apply(stored, false);
  } else {
    splitter.setAttribute(
      'aria-valuenow',
      String(Math.round(pane.getBoundingClientRect().width)),
    );
  }
  syncBounds();

  // Pointer events rather than mouse events, so a trackpad, a touchscreen and a pen all
  // work from one code path. setPointerCapture keeps the drag alive when the pointer
  // outruns the 2px-wide splitter, which it always does.
  splitter.addEventListener('pointerdown', (event: PointerEvent) => {
    if (isMobile()) return;
    event.preventDefault();

    const startX = event.clientX;
    const startWidth = pane.getBoundingClientRect().width;
    splitter.setPointerCapture(event.pointerId);

    const onMove = (move: PointerEvent) => {
      // Right-to-left flips which direction widens the sidebar.
      const rtl =
        getComputedStyle(document.documentElement).direction === 'rtl';
      const delta = move.clientX - startX;
      apply(startWidth + (rtl ? -delta : delta), false);
    };

    const onUp = () => {
      splitter.removeEventListener('pointermove', onMove);
      splitter.removeEventListener('pointerup', onUp);
      splitter.removeEventListener('pointercancel', onUp);
      // Persist once, at the end, rather than on every pointermove.
      apply(pane.getBoundingClientRect().width, true);
    };

    splitter.addEventListener('pointermove', onMove);
    splitter.addEventListener('pointerup', onUp);
    splitter.addEventListener('pointercancel', onUp);
  });

  // The element was already focusable, so a keyboard user could reach it and find nothing
  // to do. These are the bindings the separator role implies.
  splitter.addEventListener('keydown', (event: KeyboardEvent) => {
    if (isMobile()) return;

    const width = pane.getBoundingClientRect().width;
    const step = event.shiftKey ? 50 : 10;
    let next: number | undefined;

    switch (event.key) {
      case 'ArrowLeft':
        next = width - step;
        break;
      case 'ArrowRight':
        next = width + step;
        break;
      case 'Home':
        next = MIN_WIDTH;
        break;
      case 'End':
        next = maxWidth();
        break;
      default:
        return;
    }

    event.preventDefault();
    apply(next, true);
  });

  window.addEventListener('resize', syncBounds);
}
