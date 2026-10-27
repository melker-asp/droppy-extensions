// Shared parsing and formatting for the Belopp actions.
//
// Amounts arrive the way they are written in invoices, bank statements, PDFs and web pages:
// "1 234,50 kr", "1.234,50", "1,234.50", "-500", "−500", "(500)", "12 345". Dates, times and
// percentages are taken out first so "2026-10-07" or "25 %" never count as amounts.

var DATE_PATTERNS = [
  /\b\d{4}-\d{2}-\d{2}\b/g, // 2026-10-07
  /\b\d{1,2}[./]\d{1,2}[./]\d{2,4}\b/g, // 7/10/2026, 07.10.26
  /\b\d{1,2}:\d{2}(?::\d{2})?\b/g, // 14:30, 14:30:05
];
var PERCENT_PATTERN = /\d+(?:[.,]\d+)?\s?%/g;

function normalize(text) {
  return String(text || "")
    .replace(/[    ]/g, " ") // non-breaking and thin spaces
    .replace(/[−–—]/g, "-"); // minus sign, en and em dash
}

// Reads one number token such as "1.234,50", "1,234.50", "12345", "0,125" or "1,234".
// Returns null when the token is not a well-formed number.
function interpretToken(token) {
  var body = token.replace(/['\s]/g, "");
  var dots = (body.match(/\./g) || []).length;
  var commas = (body.match(/,/g) || []).length;
  var decimalMark = null;

  if (dots && commas) {
    decimalMark = body.lastIndexOf(".") > body.lastIndexOf(",") ? "." : ",";
  } else if (dots + commas === 1) {
    var mark = dots ? "." : ",";
    var parts = body.split(mark);
    // A single separator followed by exactly three digits groups thousands ("1,234", "12.500"),
    // unless the whole part is zero ("0,125"). Amounts with two decimals are never ambiguous.
    decimalMark = parts[1].length === 3 && parts[0] !== "0" ? null : mark;
  }

  var groupMark = decimalMark === "." ? "," : decimalMark === "," ? "." : null;
  var integerPart = body;
  var fraction = "";
  if (decimalMark) {
    var at = body.lastIndexOf(decimalMark);
    integerPart = body.slice(0, at);
    fraction = body.slice(at + 1);
    if (integerPart.indexOf(decimalMark) !== -1) return null; // two decimal marks
  }
  var groups = groupMark ? integerPart.split(groupMark) : integerPart.split(/[.,]/);
  if (groups.length > 1) {
    if (!/^\d{1,3}$/.test(groups[0])) return null;
    for (var i = 1; i < groups.length; i++) if (!/^\d{3}$/.test(groups[i])) return null;
  }
  var digits = groups.join("");
  if (!/^\d+$/.test(digits) || (fraction && !/^\d+$/.test(fraction))) return null;
  return parseFloat(digits + (fraction ? "." + fraction : ""));
}

// Splits a run like "12 345 2026 100" that the regex matched as one token into the pieces that
// are valid space-grouped numbers: ["12 345", "2026", "100"].
function splitSpaceGroups(run) {
  var chunks = run.split(" ");
  var out = [];
  var current = chunks[0];
  for (var i = 1; i < chunks.length; i++) {
    var lead = current.replace(/[.,'].*$/, "");
    var groupable = /^\d{1,3}(?: \d{3})*$/.test(lead) && current.indexOf(",") === -1 && current.indexOf(".") === -1;
    if (groupable && /^\d{3}(?:[.,]\d+)?$/.test(chunks[i])) {
      current += " " + chunks[i];
    } else {
      out.push(current);
      current = chunks[i];
    }
  }
  out.push(current);
  return out;
}

// Every amount in the text, in order: [{ value, source }].
function parseAmounts(text) {
  var clean = normalize(text);
  DATE_PATTERNS.forEach(function (pattern) {
    clean = clean.replace(pattern, " ");
  });
  clean = clean.replace(PERCENT_PATTERN, " ");

  var results = [];
  // Columns copied from a table are separated by tabs or runs of spaces; never join across them.
  clean.split(/\t| {2,}|\n|\r/).forEach(function (cell) {
    // A space belongs to the match only after a minus ("- 500"), so the match never starts on the
    // space after a word and the letter check below sees the character right before the amount.
    var pattern = /(\(?)(?:(-) ?)?(\d[\d .,']*\d|\d)(\)?)(-?)/g;
    var match;
    while ((match = pattern.exec(cell)) !== null) {
      var before = cell.charAt(match.index - 1);
      if (/[A-Za-zÅÄÖåäö]/.test(before)) continue; // part of a word or code, such as "A123"
      var pieces = splitSpaceGroups(match[3].replace(/ +$/, ""));
      pieces.forEach(function (piece, index) {
        var value = interpretToken(piece);
        if (value === null) return;
        var first = index === 0;
        var last = index === pieces.length - 1;
        var negative =
          (first && match[2] === "-") || (first && match[1] === "(" && last && match[4] === ")") || (last && match[5] === "-" && !/\d/.test(cell.charAt(pattern.lastIndex)));
        results.push({ value: negative ? -value : value, source: piece.trim() });
      });
    }
  });
  return results;
}

function round2(value) {
  return Math.round((value + (value >= 0 ? Number.EPSILON : -Number.EPSILON)) * 100) / 100;
}

// "excel": 12345,50 (pastes as a number into Swedish Excel). "text": 12 345,50.
function formatAmount(value, style) {
  var rounded = round2(value);
  var sign = rounded < 0 ? "-" : "";
  var fixed = Math.abs(rounded).toFixed(2).split(".");
  var whole = fixed[0];
  if (style !== "excel") whole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return sign + whole + "," + fixed[1];
}

// Four decimals as the Riksbank publishes EUR (11,2240); small rates keep their significant
// digits (JPY 0,06347, IDR 0,00056).
function formatRate(value) {
  var text = value >= 1 ? value.toFixed(4) : String(parseFloat(value.toPrecision(4)));
  return text.replace(".", ",");
}

// The copy format the user picked in the options, "excel" unless they chose text.
function copyStyle(openclip) {
  var chosen = openclip && typeof openclip.option === "function" ? openclip.option("format") : "";
  return /text/i.test(chosen || "") ? "text" : "excel";
}

var MONTHS = {
  jan: 1, feb: 2, mar: 3, apr: 4, maj: 5, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, okt: 10, oct: 10, nov: 11, dec: 12,
};

function pad(n) {
  return n < 10 ? "0" + n : String(n);
}

function isoDate(year, month, day) {
  if (year < 100) year += 2000;
  var date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return year + "-" + pad(month) + "-" + pad(day);
}

// The first date in the text as "YYYY-MM-DD", or null: 2026-10-07, 7/10/2026, 7.10.2026, 7 okt 2026.
function findDate(text) {
  var clean = normalize(text);
  var m = clean.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (m) return isoDate(+m[1], +m[2], +m[3]);
  m = clean.match(/\b(\d{1,2})[./](\d{1,2})[./](\d{2,4})\b/);
  if (m) return isoDate(+m[3], +m[2], +m[1]);
  m = clean.match(/\b(\d{1,2})\s+([A-Za-zåäö]{3})[a-zåäö]*\.?\s+(\d{4})\b/i);
  if (m && MONTHS[m[2].toLowerCase()]) return isoDate(+m[3], MONTHS[m[2].toLowerCase()], +m[1]);
  return null;
}

module.exports = {
  parseAmounts: parseAmounts,
  formatAmount: formatAmount,
  formatRate: formatRate,
  copyStyle: copyStyle,
  findDate: findDate,
  round2: round2,
};
