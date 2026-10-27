// Valuta: converts an amount at the Riksbank's mid rate for the date in the selection (the
// invoice date), or the latest rate when there is none. Foreign currency becomes SEK; an amount
// in SEK becomes the "Valuta för SEK-belopp" option. Weekends and holidays have no rate, so the
// closest earlier banking day is used and said so.
var belopp = require("./lib/belopp.js");

// Currencies the Riksbank still publishes (series SEK<code>PMI, SEK per one unit).
var CURRENCIES = "AUD BRL CAD CHF CNY CZK DKK EUR GBP HKD HUF IDR ILS INR ISK JPY KRW MXN MYR NOK NZD PHP PLN RON SGD THB TRY USD ZAR".split(" ");
var SYMBOLS = { "€": "EUR", $: "USD", "£": "GBP", "¥": "JPY" };
var API = "https://api.riksbank.se/swea/v1/Observations/";

function currencyFrom(selection) {
  var codes = String(selection).toUpperCase().match(/\b[A-Z]{3}\b/g) || [];
  for (var i = 0; i < codes.length; i++) {
    if (codes[i] === "SEK" || CURRENCIES.indexOf(codes[i]) !== -1) return codes[i];
  }
  for (var symbol in SYMBOLS) if (selection.indexOf(symbol) !== -1) return SYMBOLS[symbol];
  if (/\d\s*(kr|kronor)\b|\b(kr|kronor)\s*\d/i.test(selection)) return "SEK";
  return null;
}

function daysBefore(iso, days) {
  var d = new Date(iso + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

function getJSON(url) {
  return openclip.fetch(url).then(function (res) {
    if (res.status === 429) throw new Error("Riksbanken tar inte emot fler frågor just nu, försök igen om en stund");
    if (!res.ok) throw new Error("Riksbanken svarade " + res.status);
    return res.json();
  });
}

// { date, value } for the banking day on or before `date`, or the latest one.
function rateFor(code, date) {
  var series = "SEK" + code + "PMI";
  if (!date) return getJSON(API + "Latest/" + series);
  return getJSON(API + series + "/" + daysBefore(date, 10) + "/" + date).then(function (rows) {
    if (!rows || rows.length === 0) throw new Error("Ingen kurs för " + code + " runt " + date);
    return rows[rows.length - 1];
  });
}

module.exports = function action(selection) {
  var amounts = belopp.parseAmounts(selection);
  if (amounts.length === 0) return Promise.reject(new Error("Hittade inget belopp i markeringen"));
  var source = currencyFrom(selection);
  if (!source) return Promise.reject(new Error("Hittade ingen valuta, skriv till exempel EUR 1 200"));

  var amount = amounts[0].value;
  var date = belopp.findDate(selection);
  var toSEK = source !== "SEK";
  var other = toSEK ? source : String(openclip.option("target") || "EUR").toUpperCase();
  if (CURRENCIES.indexOf(other) === -1) return Promise.reject(new Error(other + " finns inte hos Riksbanken"));

  return rateFor(other, date).then(function (rate) {
    var result = toSEK ? amount * rate.value : amount / rate.value;
    var target = toSEK ? "SEK" : other;
    var f = belopp.formatAmount;
    var copied = f(result, belopp.copyStyle(openclip));

    if (openclip.input.isSecondaryClick) {
      var lines = [
        f(amount) + " " + source + " = " + f(result) + " " + target,
        "Kurs: " + belopp.formatRate(rate.value) + " SEK per " + other,
        "Kursdag: " + rate.date + " (Riksbankens mittkurs)",
      ];
      if (date && date !== rate.date) lines.push(date + " saknar kurs (helg eller helgdag), närmast föregående bankdag användes.");
      if (!date) lines.push("Inget datum i markeringen, senaste kursen användes.");
      if (amounts.length > 1) lines.push("Markeringen hade " + amounts.length + " belopp; det första räknades om.");
      lines.push("", "Riksbankens kurser är indikativa. Följ Lavendlas rutin om bokföringen kräver en annan kurs.");
      return lines.join("\n");
    }

    openclip.copy(copied);
    openclip.toast(f(result) + " " + target + " kopierat · kurs " + belopp.formatRate(rate.value) + " (" + rate.date + ")", "success");
    return undefined;
  });
};
