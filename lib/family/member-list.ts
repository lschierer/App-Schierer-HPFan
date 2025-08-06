//<iconify-icon icon="tdesign:caret-right

const familylist = document.querySelector("div.family-tree");
if (familylist) {
  familylist.querySelectorAll(".spectrum-TreeView-item").forEach((item) => {
    const childList = item.querySelector(":scope > .spectrum-TreeView");
    const icon = item.querySelector("iconify-icon");

    if (icon) {
      icon.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();

        // Toggle the item state
        item.classList.toggle("is-collapsed");
        item.classList.toggle("is-open");
      });

      if (childList) {
        icon.removeAttribute("style");
      } else {
        icon.setAttribute("style", "display: none");
      }
    }
  });
}
