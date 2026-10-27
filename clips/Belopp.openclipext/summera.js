// Summera: the sum of every amount in the selection.
// Primary click (and the inline preview) gives the sum in the copy format; a secondary click
// (right-click or ⇧-click) shows every amount it read, so the sum can be checked.
var belopp = require("./lib/belopp.js");

module.exports = function action(selection) {
  var amounts = belopp.parseAmounts(selection);
  if (amounts.length === 0) {
    if (openclip.input.isSecondaryClick) return "Hittade inga belopp i markeringen.";
    throw new Error("Hittade inga belopp i markeringen");
  }

  var sum = 0;
  var min = Infinity;
  var max = -Infinity;
  amounts.forEach(function (a) {
    sum += a.value;
    if (a.value < min) min = a.value;
    if (a.value > max) max = a.value;
  });

  if (!openclip.input.isSecondaryClick) return belopp.formatAmount(sum, belopp.copyStyle(openclip));

  var text = belopp.formatAmount;
  var lines = [
    "Summa: " + text(sum),
    "Antal: " + amounts.length,
    "Medel: " + text(sum / amounts.length),
    "Min: " + text(min) + "   Max: " + text(max),
    "",
    "Lästa belopp:",
  ];
  // The text as written follows when it differs from how it is shown ("1,000.00" → 1 000,00);
  // the sign is left out of that comparison because the source never carries it.
  amounts.forEach(function (a) {
    var shown = text(Math.abs(a.value));
    var differs = a.source.replace(/\s/g, "") !== shown.replace(/\s/g, "");
    lines.push(text(a.value) + (differs ? "   ← " + a.source : ""));
  });
  return lines.join("\n");
};
