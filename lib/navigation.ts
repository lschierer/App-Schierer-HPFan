// Navigation tree expand/collapse functionality, plus relocating the tree into the
// mobile drawer.

// querySelectorAll rather than the singular querySelector this used to use: the tree can
// live in either of two places (see relocateTree below), and a lookup that assumed one
// fixed home is what left the drawer's chevrons inert.
document.querySelectorAll(".navigation-tree").forEach((navigationTree) => {
  navigationTree
    .querySelectorAll(".spectrum-TreeView-item")
    .forEach((item) => {
      const chevron = item.querySelector<HTMLElement>(
        ":scope > .spectrum-TreeView-itemLink > .spectrum-TreeView-itemIndicator"
      );
      const childList = item.querySelector<HTMLElement>(
        ":scope > .spectrum-TreeView"
      );

      if (chevron && childList) {
        // The chevron is a <button> now, so it is focusable and Enter/Space reach this
        // handler for free - no keydown branch needed. aria-expanded is set on both the
        // button (what it does) and the <li role="treeitem"> (what the tree role
        // requires), so both are written here to keep them from drifting.
        const setExpanded = (expanded: boolean) => {
          item.classList.toggle("is-open", expanded);
          item.setAttribute("aria-expanded", String(expanded));
          chevron.setAttribute("aria-expanded", String(expanded));
          childList.classList.toggle("nav-collapsed", !expanded);

          if (expanded) {
            // Children are rendered server-side with nav-hidden when they fall outside
            // the initially-visible set; revealing the branch has to clear that too.
            childList
              .querySelectorAll(".spectrum-TreeView-item.nav-hidden")
              .forEach((childItem) => {
                childItem.classList.remove("nav-hidden");
              });
          }
        };

        chevron.addEventListener("click", (e) => {
          e.preventDefault();
          e.stopPropagation();
          setExpanded(childList.classList.contains("nav-collapsed"));
        });
      }
    });
});

// Move the tree between the desktop sidebar and the mobile drawer.
//
// WHY MOVE INSTEAD OF RENDER TWICE. This site's tree is 1310 items, about 875KB of
// markup. Emitting it into the drawer as well took content pages from 910KB to 1.8MB and
// the splash page - which has no sidebar, so previously carried no tree at all - from
// 46KB to 920KB. Moving the one node costs nothing, keeps ids unduplicated, and the
// chevron handlers bound above travel with the element.
const mobileTreeSocket = document.getElementById("mobile-nav-tree");
const mobileTreeSection = document.getElementById("mobile-nav-tree-section");
const sidebarTreeHome = document.querySelector("#nav .spectrum-Site-sideBar");

if (mobileTreeSocket && mobileTreeSection) {
  // Matched against the same 768px boundary as global_header.css and global.css, where
  // the sidebar is hidden and the hamburger appears.
  const isMobile = window.matchMedia("(width < 768px)");

  const relocateTree = () => {
    const tree = document.querySelector(".navigation-tree");

    if (isMobile.matches) {
      // No tree on this page (a page without a sidebar) means the drawer shows only the
      // section links, and the separator stays hidden.
      if (tree && tree.parentElement !== mobileTreeSocket) {
        mobileTreeSocket.append(tree);
      }
      mobileTreeSection.hidden = mobileTreeSocket.childElementCount === 0;
    } else {
      if (tree && sidebarTreeHome && tree.parentElement === mobileTreeSocket) {
        sidebarTreeHome.append(tree);
      }
      mobileTreeSection.hidden = true;
    }
  };

  relocateTree();
  isMobile.addEventListener("change", relocateTree);
}
