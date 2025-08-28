const DEBUG = true;
document.addEventListener("DOMContentLoaded", function () {
  // Small delay to ensure multi-column layout has settled
  setTimeout(() => {
    document.querySelectorAll(".timeline.node-label").forEach((card) => {
      // Extract event ID from card (e.g., "card-E0123" -> "E0123")
      const eventId = card.id.replace("event-div-", "");
      if (DEBUG) {
        console.log(`eventId is ${eventId}`);
      }
      const line = document.getElementById(`line-${eventId}`);

      if (line && card) {
        if (DEBUG) {
          console.log(`both line and card for ${eventId} found.`);
        }
        const cardRect = card.getBoundingClientRect();
        const foreignObj = card.closest("foreignObject");
        let foreignRect: number | DOMRect = -99999999999;
        if (foreignObj) {
          foreignRect = foreignObj.getBoundingClientRect();
        }
        if (DEBUG) {
          console.log("ForeignObject position:", foreignRect);
        }
        const svg = document.querySelector("svg");

        if (svg) {
          const svgRect = svg.getBoundingClientRect();
          const viewBox = svg.viewBox.baseVal;

          const scaleX = viewBox.width / svgRect.width;
          const scaleY = viewBox.height / svgRect.height;

          const cardCenterX = cardRect.left + cardRect.width / 2;
          const cardCenterY = cardRect.top + cardRect.height / 2;

          // Convert to SVG coordinates manually
          const cardX = (cardCenterX - svgRect.left) * scaleX;
          const cardY = (cardCenterY - svgRect.top) * scaleY;

          console.log(`Manual calculation: x=${cardX}, y=${cardY}`);
          console.log(`Scale factors: scaleX=${scaleX}, scaleY=${scaleY}`);
          console.log(`ViewBox: ${viewBox.width} x ${viewBox.height}`);
          console.log(`SVG rect: ${svgRect.width} x ${svgRect.height}`);
        }
      } else if (DEBUG) {
        if (!line) {
          console.error(`cannot find line for ${eventId}`);
        }
        if (!card) {
          console.error(`cannot find card for ${eventId}`);
        }
      }
    });
  }, 100); // 100ms delay for layout settling
});
