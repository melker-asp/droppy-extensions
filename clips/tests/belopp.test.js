// Tests for Belopp.openclipext. Run from clips/: node --test tests/
// Each action runs against a stand-in for DropClip's `openclip` bridge.
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const PKG = path.join(__dirname, "..", "Belopp.openclipext");
const belopp = require(path.join(PKG, "lib/belopp.js"));

function bridge({ secondary = false, options = {}, responses = {} } = {}) {
  const effects = [];
  return {
    effects,
    input: { isSecondaryClick: secondary },
    option: (id) => options[id] || "",
    copy: (text) => effects.push(["copy", text]),
    toast: (message, style) => effects.push(["toast", message, style]),
    fetch: (url) => {
      const key = Object.keys(responses).find((k) => url.includes(k));
      if (!key) return Promise.reject(new Error("unexpected fetch " + url));
      const { status = 200, body } = responses[key];
      return Promise.resolve({ status, ok: status >= 200 && status < 300, text: () => JSON.stringify(body), json: () => body });
    },
  };
}

function run(file, selection, opts) {
  global.openclip = bridge(opts);
  delete require.cache[require.resolve(path.join(PKG, file))];
  const result = require(path.join(PKG, file))(selection);
  return { result, effects: global.openclip.effects };
}

const values = (text) => belopp.parseAmounts(text).map((a) => a.value);

test("reads the ways amounts are written", () => {
  assert.deepEqual(values("1 234,50 kr"), [1234.5]);
  assert.deepEqual(values("1.234,50"), [1234.5]);
  assert.deepEqual(values("1,234.50"), [1234.5]);
  assert.deepEqual(values("12 345,00"), [12345]);
  assert.deepEqual(values("1,234"), [1234]);
  assert.deepEqual(values("0,125"), [0.125]);
  assert.deepEqual(values("99,5"), [99.5]);
  assert.deepEqual(values("1 000 000"), [1000000]);
});

test("reads negative amounts", () => {
  assert.deepEqual(values("-500"), [-500]);
  assert.deepEqual(values("−500,25"), [-500.25]);
  assert.deepEqual(values("(1 200,00)"), [-1200]);
  assert.deepEqual(values("1 200,00-"), [-1200]);
});

test("skips dates, times, percentages and codes", () => {
  assert.deepEqual(values("Fakturadatum 2026-10-07 Belopp 1 250,00"), [1250]);
  assert.deepEqual(values("Förfaller 7/10/2026 kl 14:30, 500 kr"), [500]);
  assert.deepEqual(values("Moms 25 % på 800"), [800]);
  assert.deepEqual(values("Artikel A123 kostar 40"), [40]);
});

test("keeps table columns apart", () => {
  assert.deepEqual(values("Hyra\t12 000,00\nEl\t1 450,50\nInternet\t399,00"), [12000, 1450.5, 399]);
  assert.deepEqual(values("100  200"), [100, 200]);
  assert.deepEqual(values("12 345 2026 100"), [12345, 2026, 100]);
});

test("formats for Excel and for text", () => {
  assert.equal(belopp.formatAmount(12345.5, "excel"), "12345,50");
  assert.equal(belopp.formatAmount(12345.5, "text"), "12 345,50");
  assert.equal(belopp.formatAmount(-1234567.891, "text"), "-1 234 567,89");
  assert.equal(belopp.formatAmount(1.005, "excel"), "1,01");
});

test("finds the invoice date", () => {
  assert.equal(belopp.findDate("Fakturadatum 2026-10-04"), "2026-10-04");
  assert.equal(belopp.findDate("Datum 4/10/2026"), "2026-10-04");
  assert.equal(belopp.findDate("4.10.26"), "2026-10-04");
  assert.equal(belopp.findDate("den 4 oktober 2026"), "2026-10-04");
  assert.equal(belopp.findDate("31/02/2026"), null);
  assert.equal(belopp.findDate("1 200 EUR"), null);
});

test("Summera copies the sum, and lists what it read on a secondary click", () => {
  const column = "1 250,00\n-250,00\n399,50";
  assert.equal(run("summera.js", column).result, "1399,50");
  assert.equal(run("summera.js", column, { options: { format: "Text: 12 345,50" } }).result, "1 399,50");
  const card = run("summera.js", column, { secondary: true }).result;
  assert.match(card, /^Summa: 1 399,50\nAntal: 3\nMedel: 466,50/);
  assert.match(card, /-250,00/);
  assert.throws(() => run("summera.js", "inga siffror här"));
});

test("Moms splits both ways and adds up to the öre", () => {
  const card = run("moms.js", "1 250,00 kr").result;
  assert.match(card, /inklusive 25 % moms\nExkl\. moms: 1 000,00\nMoms: 250,00/);
  assert.match(card, /exklusive 25 % moms\nInkl\. moms: 1 562,50\nMoms: 312,50/);
  assert.match(run("moms.js", "Livsmedel 112,00 inkl. 12 % moms").result, /Exkl\. moms: 100,00\nMoms: 12,00/);
  assert.match(run("moms.js", "106", { options: { rate: "6" } }).result, /Exkl\. moms: 100,00/);
  assert.match(run("moms.js", "125 % av 100").result, /inklusive 25 %/); // 125 % is not a VAT rate
  const odd = run("moms.js", "99,99").result.match(/Exkl\. moms: ([\d ,]+)\nMoms: ([\d ,]+)/);
  const toNumber = (s) => parseFloat(s.replace(/ /g, "").replace(",", "."));
  assert.equal(Math.round((toNumber(odd[1]) + toNumber(odd[2])) * 100), 9999);
});

const EUR_WEEK = { body: [{ date: "2026-10-01", value: 11.3 }, { date: "2026-10-02", value: 11.2 }] };

test("Valuta converts at the rate of the banking day on or before the invoice date", async () => {
  const { result, effects } = run("valuta.js", "EUR 1 200,00 fakturadatum 2026-10-04", { responses: { "SEKEURPMI/2026-09-24/2026-10-04": EUR_WEEK } });
  assert.equal(await result, undefined);
  assert.deepEqual(effects[0], ["copy", "13440,00"]);
  assert.match(effects[1][1], /13 440,00 SEK kopierat · kurs 11,2000 \(2026-10-02\)/);
});

test("Valuta explains itself on a secondary click", async () => {
  const card = await run("valuta.js", "1 200 € 2026-10-04", { secondary: true, responses: { SEKEURPMI: EUR_WEEK } }).result;
  assert.match(card, /^1 200,00 EUR = 13 440,00 SEK\nKurs: 11,2000 SEK per EUR\nKursdag: 2026-10-02/);
  assert.match(card, /2026-10-04 saknar kurs/);
});

test("Valuta turns SEK into the chosen currency with the latest rate", async () => {
  const { effects } = run("valuta.js", "1 000 kr", { options: { target: "USD" }, responses: { "Latest/SEKUSDPMI": { body: { date: "2026-10-07", value: 10 } } } });
  await new Promise((r) => setImmediate(r));
  assert.deepEqual(effects[0], ["copy", "100,00"]);
});

test("Valuta says what is missing", async () => {
  await assert.rejects(run("valuta.js", "1 200").result, /Hittade ingen valuta/);
  await assert.rejects(run("valuta.js", "EUR").result, /Hittade inget belopp/);
  await assert.rejects(run("valuta.js", "EUR 10 2026-10-04", { responses: { SEKEURPMI: { status: 429, body: {} } } }).result, /inte emot fler frågor/);
});
