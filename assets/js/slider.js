
const getBettingParams = () => {
  const slider = document.getElementById('bet-range');
  const minBet = parseInt(slider.dataset.minBet);
  const maxBet = parseInt(slider.dataset.maxBet);
  const callValue = parseInt(slider.dataset.callValue);
  const betSoFar = parseInt(slider.dataset.betSoFar);
  const potSize = parseInt(slider.dataset.potSize);
  const maxAllIn = slider.dataset.maxAllIn === "true";

  return { minBet, maxBet, callValue, betSoFar, potSize, maxAllIn };
};

const computePotRelativeBet = (minBet, maxBet, afterCallPotSize, raisingBase, percentage) => {
  const bet = raisingBase + Math.round(afterCallPotSize * percentage)

  if (bet < minBet) {
    return minBet;
  } else if (bet > maxBet) {
    return maxBet;
  }

  return bet;
};

const computeBetForSliderPercentage = (minBet, maxBet, percentage) => {
  return minBet + Math.round(percentage * (maxBet - minBet));
}

const updateWithSlider = (rangeElement, betSizeElement) => {
  const rangePercent = parseFloat(rangeElement.value) / parseFloat(rangeElement.max);

  const { minBet, maxBet, maxAllIn } = getBettingParams();

  const betSize = computeBetForSliderPercentage(minBet, maxBet, rangePercent);

  betSizeElement.value = betSize.toString();

  return maxAllIn && betSize == maxBet;
};

const updateWithSize = (rangeElement, betSizeElement) => {
  sanitizePriceInput(betSizeElement);
  let targetBet = parseInt(betSizeElement.value || "0");

  const { minBet, maxBet, maxAllIn } = getBettingParams();

  if (targetBet > maxBet) {
    betSizeElement.value = maxBet.toString();
  }

  // We may temporarily drop below the min bet 
  // (suppose you edit and delete everything to type a new number)
  const rangeValue = Math.max(0, (targetBet - minBet) / (maxBet - minBet) * parseInt(rangeElement.max));

  rangeElement.value = rangeValue.toFixed(0);

  return maxAllIn && maxBet == targetBet;
};

const sanitizePriceInput = (betSizeElement) => {
  let value = betSizeElement.value;

  // Remove non numeric chars
  value = value.replace(/[^\d]/g, '');

  if (value !== betSizeElement.value) {
    betSizeElement.value = value;
  }
}

const updateBetButton = (betSizeElement, isAllIn) => {
  const betButton = document.getElementById('bet-button');
  const actionType = betButton.getAttribute('phx-value-action-type');

  if (isAllIn) {
    betButton.setAttribute('phx-value-action-type', 'all_in')
    betButton.innerText = `All In ${betSizeElement.value}`
  } else if (actionType == "raise") {
    betButton.innerText = `Raise to ${betSizeElement.value}`
  } else {
    betButton.innerText = `Bet ${betSizeElement.value}`
  }

  betButton.setAttribute('phx-value-size', betSizeElement.value);
}

const getElements = () => ({
  range: document.getElementById('bet-range'),
  size: document.getElementById('bet-size'),
})

window.onBetSizeClick = (btn) => {
  const betPortion = parseFloat(btn.dataset.betPortion);

  const { minBet, maxBet, potSize, betSoFar, callValue, maxAllIn } = getBettingParams();
  const betSize = computePotRelativeBet(minBet, maxBet, potSize + callValue, betSoFar + callValue, betPortion);

  const { size, range } = getElements();

  size.value = betSize.toString();
  updateWithSize(range, size);
  updateBetButton(size, betSize == maxBet && maxAllIn);
};

window.onRangeInput = () => {
  const { size, range } = getElements();

  updateWithSlider(range, size);
  const isAllIn = updateWithSize(range, size);
  updateBetButton(size, isAllIn);
}

window.onBetTextInput = () => {
  const { size, range } = getElements();

  const isAllIn = updateWithSize(range, size);
  updateBetButton(size, isAllIn);
}

window.onBetTextBlur = () => {
  const { size, range } = getElements();

  const isAllIn = updateWithSlider(range, size);
  updateBetButton(size, isAllIn);
}
