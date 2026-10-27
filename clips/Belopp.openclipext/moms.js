// Moms: splits an amount into net, VAT and gross, both ways, because a selected amount can be
// either including or excluding VAT. Several amounts are summed first. The rate is the one
// written in the selection (25 %, 12 % or 6 %), else the "Momssats" option.
var belopp = require("./lib/belopp.js");

var SWEDISH_RATES = [25, 12, 6];

function rateFrom(selection) {
  var written = String(selection).match(/(?:^|[^\d.,])(\d{1,2})(?:[.,]0+)?\s?%/);
  if (written && SWEDISH_RATES.indexOf(+written[1]) !== -1) return +written[1];
  var chosen = parseInt(openclip.option("rate"), 10);
  return SWEDISH_RATES.indexOf(chosen) !== -1 ? chosen : 25;
}

module.exports = function action(selection) {
  var amounts = belopp.parseAmounts(selection);
  if (amounts.length === 0) throw new Error("Hittade inget belopp i markeringen");

  var amount = belopp.round2(amounts.reduce(function (s, a) { return s + a.value; }, 0));
  var rate = rateFrom(selection);
  var f = belopp.formatAmount;

  // Net is rounded first and VAT is the difference, so the three always add up to the öre.
  var netFromGross = belopp.round2(amount / (1 + rate / 100));
  var vatInGross = belopp.round2(amount - netFromGross);
  var vatOnNet = belopp.round2((amount * rate) / 100);
  var grossFromNet = belopp.round2(amount + vatOnNet);

  var lines = [];
  if (amounts.length > 1) lines.push("Summan av " + amounts.length + " belopp: " + f(amount), "");
  lines.push(
    "Om " + f(amount) + " är inklusive " + rate + " % moms",
    "Exkl. moms: " + f(netFromGross),
    "Moms: " + f(vatInGross),
    "",
    "Om " + f(amount) + " är exklusive " + rate + " % moms",
    "Inkl. moms: " + f(grossFromNet),
    "Moms: " + f(vatOnNet)
  );
  return lines.join("\n");
};
