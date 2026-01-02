// Navigation tree expand/collapse functionality

const navigationTree = document.querySelector("nav.navigation-tree");

if (navigationTree) {
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
        // Make chevron clickable
        chevron.addEventListener("click", (e) => {
          e.preventDefault();
          e.stopPropagation();

          // Toggle the item state
          const isOpen = item.classList.contains("is-open");

          if (isOpen) {
            // Collapse
            item.classList.remove("is-open");
            item.setAttribute("aria-expanded", "false");
            childList.classList.add("nav-collapsed");
          } else {
            // Expand
            item.classList.add("is-open");
            item.setAttribute("aria-expanded", "true");
            childList.classList.remove("nav-collapsed");
          }
        });
      }
    });
}
