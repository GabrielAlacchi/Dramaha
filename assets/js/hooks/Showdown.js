
// Positions to slide pots to relative to the table
const targetRelativePos = {
  "1": { x: 0.5, y: 0.24, xRef: 'center', yRef: 'bottom' },
  "2": { x: 0.15, y: 0.4, xRef: 'left', yRef: 'bottom' },
  "3": { x: 0.15, y: 0.25, xRef: 'left', yRef: 'top' },
  "4": { x: 0.5, y: 0.15, xRef: 'center', yRef: 'top' },
  "5": { x: 0, y: 0.25, xRef: 'right', yRef: 'top' },
  "6": { x: 0.05, y: 0.4, xRef: 'right', yRef: 'bottom' }
}

const emptyTransform = (potSplit) => {
  potSplit.style.transform = "translate(0, 0)";
  potSplit.style.display = "none";
}

const xShift = (targetX, ref, potEntry, tableWidth) => {
  const left = potEntry.offsetLeft;

  if (ref == 'left') {
    return Math.round(targetX * tableWidth) - left;
  } else if (ref == 'right') {
    const right = tableWidth - (left + potEntry.offsetWidth);
    return right - Math.round(targetX * tableWidth);
  } else {
    return Math.round(targetX * tableWidth - (left + potEntry.offsetWidth / 2));
  }
}

const yShift = (targetY, ref, potEntry, tableHeight) => {
  const top = potEntry.offsetTop;

  if (ref == 'top') {
    return Math.round(targetY * tableHeight) - top;
  } else {
    const bottom = tableHeight - (top + potEntry.offsetHeight);
    return bottom - Math.round(targetY * tableHeight);
  }
}

const maybeTransition = (potSplit) => {
  if (potSplit.style.transform === "") {
    // Compute the translation to get to the data target spot.
    const targetPos = targetRelativePos[potSplit.dataset.targetSeat];

    if (targetPos === undefined) {
      emptyTransform(potSplit);
      return;
    }

    // The pot split is positioned absolute w.r.t to the pot entry
    // that way multiple splits can be in the same spot at the beginning of the animation
    const potEntry = potSplit.offsetParent;

    // Compute the transform w.r.t the potEntry's position relative to the table
    const { offsetWidth: tableWidth, offsetHeight: tableHeight } = potEntry.offsetParent;
    const translateX = xShift(targetPos.x, targetPos.xRef, potEntry, tableWidth);
    const translateY = yShift(targetPos.y, targetPos.yRef, potEntry, tableHeight);

    potSplit.style.transform = `translate(${translateX}px, ${translateY}px)`

    setTimeout(() => potSplit.style.display = "none", 3200);
  }
}

export const Showdown = {
  mounted() {
    for (const potSplit of this.el.children) {
      maybeTransition(potSplit);
    }
  }
}
