// Obsidian for DropClip, run by dagens.sh and ny.sh as
//   /usr/bin/osascript -l JavaScript lib/obsidian.js <dagens|ny>
// Input comes in environment variables (OBSIDIAN_CLIP_TEXT, OBSIDIAN_CLIP_VAULT,
// OBSIDIAN_CLIP_HEADING). The return value of run() is printed by osascript: one DropClip shell
// JSON toast. Errors become an error toast, so the script always exits 0.
// It reads and writes the vault's Markdown files directly and never touches dot-folders, apart
// from reading the three config files in .obsidian.
ObjC.import("Foundation");
ObjC.import("AppKit");

var fm = $.NSFileManager.defaultManager;

var MONTHS = "januari februari mars april maj juni juli augusti september oktober november december".split(" ");
var MONTHS_SHORT = "jan feb mar apr maj jun jul aug sep okt nov dec".split(" ");
var DAYS = "söndag måndag tisdag onsdag torsdag fredag lördag".split(" ");
var DAYS_SHORT = "sön mån tis ons tor fre lör".split(" ");

function run(argv) {
  try {
    var command = argv[0];
    if (command === "dagens") return toast(captureToDaily(), "success");
    if (command === "ny") return toast(newNote(), "success");
    throw new Error("Okänt kommando: " + command);
  } catch (e) {
    return toast(e.message || String(e), "error");
  }
}

function toast(message, style) {
  return JSON.stringify({ type: "toast", message: message, style: style });
}

// --- Environment and files ---------------------------------------------------------------

function env(name) {
  var value = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name));
  return value === undefined || value === null ? "" : String(value);
}

function join() {
  var parts = [];
  for (var i = 0; i < arguments.length; i++) {
    var p = String(arguments[i] || "");
    if (p !== "") parts.push(i === 0 ? p.replace(/\/+$/, "") : p.replace(/^\/+|\/+$/g, ""));
  }
  return parts.join("/");
}

function exists(path) {
  return fm.fileExistsAtPath(path);
}

function isDirectory(path) {
  var isDir = Ref();
  return fm.fileExistsAtPathIsDirectory(path, isDir) && !!isDir[0];
}

function readText(path) {
  var value = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  return value === undefined || value === null ? null : String(value);
}

function readJSON(path) {
  var text = readText(path);
  if (text === null) return {};
  try {
    var value = JSON.parse(text);
    return value && typeof value === "object" ? value : {};
  } catch (e) {
    return {};
  }
}

function writeText(path, text) {
  var parent = $(path).stringByDeletingLastPathComponent.js;
  if (!isDirectory(parent)) {
    fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(parent, true, $(), null);
  }
  if (!$(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) {
    throw new Error("Kunde inte spara " + $(path).lastPathComponent.js);
  }
}

// Paths inside the vault that this script writes to; a dot-folder (or ..) is refused.
function checkWritable(relPath) {
  relPath.split("/").forEach(function (segment) {
    if (segment.charAt(0) === ".") throw new Error("Skriver inte i dolda mappar: " + relPath);
  });
}

// --- Vault and config --------------------------------------------------------------------

function resolveVault(optionPath) {
  var path = optionPath.trim();
  if (path !== "") {
    path = $(path).stringByExpandingTildeInPath.js.replace(/\/+$/, "");
    if (!isDirectory(join(path, ".obsidian"))) {
      throw new Error("Hittar inget Obsidian-valv i " + path + ". Kontrollera Valv (sökväg).");
    }
    return path;
  }

  var registry = readJSON($("~/Library/Application Support/obsidian/obsidian.json").stringByExpandingTildeInPath.js);
  var vaults = registry.vaults || {};
  var best = null;
  Object.keys(vaults).forEach(function (key) {
    var v = vaults[key];
    if (!v || !v.path) return;
    var rank = [v.open === true ? 1 : 0, Number(v.ts) || 0];
    if (!best || rank[0] > best.rank[0] || (rank[0] === best.rank[0] && rank[1] > best.rank[1])) {
      best = { path: v.path, rank: rank };
    }
  });
  if (!best) {
    throw new Error("Hittar inget Obsidian-valv. Öppna valvet i Obsidian eller ange Valv (sökväg).");
  }
  if (!isDirectory(join(best.path, ".obsidian"))) {
    throw new Error("Valvet " + best.path + " finns inte längre. Öppna det i Obsidian eller ange Valv (sökväg).");
  }
  return best.path;
}

function trimFolder(folder) {
  return String(folder || "").trim().replace(/^\/+|\/+$/g, "");
}

function readConfig(vault) {
  var daily = readJSON(join(vault, ".obsidian/daily-notes.json"));
  var templates = readJSON(join(vault, ".obsidian/templates.json"));
  var app = readJSON(join(vault, ".obsidian/app.json"));
  var location = app.newFileLocation;
  return {
    dailyFolder: trimFolder(daily.folder),
    dailyFormat: String(daily.format || "").trim() || "YYYY-MM-DD",
    dailyTemplate: trimFolder(daily.template),
    templatesFolder: trimFolder(templates.folder),
    // Obsidian only uses newFileFolderPath when "Default location for new notes" is a folder.
    newFileFolder: location === "root" || location === "current" ? "" : trimFolder(app.newFileFolderPath)
  };
}

// --- Dates and templates -----------------------------------------------------------------

function pad(n) {
  return n < 10 ? "0" + n : String(n);
}

// The moment.js tokens Obsidian templates use, rendered the way moment's sv locale does.
function formatMoment(d, format) {
  return format.replace(/\[([^\]]*)\]|YYYY|YY|MMMM|MMM|MM|M|DD|D|dddd|ddd|HH|H|mm|ss/g, function (token, literal) {
    if (literal !== undefined) return literal;
    switch (token) {
      case "YYYY": return String(d.getFullYear());
      case "YY": return pad(d.getFullYear() % 100);
      case "MMMM": return MONTHS[d.getMonth()];
      case "MMM": return MONTHS_SHORT[d.getMonth()];
      case "MM": return pad(d.getMonth() + 1);
      case "M": return String(d.getMonth() + 1);
      case "DD": return pad(d.getDate());
      case "D": return String(d.getDate());
      case "dddd": return DAYS[d.getDay()];
      case "ddd": return DAYS_SHORT[d.getDay()];
      case "HH": return pad(d.getHours());
      case "H": return String(d.getHours());
      case "mm": return pad(d.getMinutes());
      case "ss": return pad(d.getSeconds());
    }
    return token;
  });
}

function renderTemplate(template, title, d) {
  return template.replace(/\{\{\s*(title|date|time)\s*(?::([^}]*))?\}\}/gi, function (m, key, format) {
    key = key.toLowerCase();
    if (key === "title") return title;
    if (format !== undefined && format.trim() !== "") return formatMoment(d, format.trim());
    return formatMoment(d, key === "date" ? "YYYY-MM-DD" : "HH:mm");
  });
}

function templateFile(vault, name) {
  return join(vault, name.replace(/\.md$/i, "") + ".md");
}

// --- Selection ---------------------------------------------------------------------------

function selectionLines() {
  var text = env("OBSIDIAN_CLIP_TEXT").replace(/\r\n?/g, "\n").replace(/^(?:[ \t]*\n)+/, "").replace(/\s+$/, "");
  if (text === "") throw new Error("Ingen text markerad");
  return text.split("\n");
}

// --- Dagens anteckning -------------------------------------------------------------------

function ensureDailyNote(vault, cfg, now) {
  var name = formatMoment(now, cfg.dailyFormat);
  var relPath = join(cfg.dailyFolder, name + ".md");
  checkWritable(relPath);
  var path = join(vault, relPath);
  if (!exists(path)) {
    var content = "";
    if (cfg.dailyTemplate) {
      var template = readText(templateFile(vault, cfg.dailyTemplate));
      if (template !== null) content = renderTemplate(template, name.split("/").pop(), now);
    }
    writeText(path, content);
  }
  return path;
}

// "- HH:mm <first line>", further lines indented two spaces, blank lines left empty.
function captureEntry(lines, now) {
  return lines.map(function (line, i) {
    if (i === 0) return "- " + formatMoment(now, "HH:mm") + " " + line.replace(/^\s+/, "");
    return line.trim() === "" ? "" : "  " + line;
  });
}

function insertCapture(content, heading, entry) {
  var lines = content.split("\n");
  var headings = [];
  var start = 0;
  if (lines.length > 0 && lines[0].trim() === "---") {
    for (var f = 1; f < lines.length; f++) {
      if (lines[f].trim() === "---" || lines[f].trim() === "...") { start = f + 1; break; }
    }
  }
  var fence = null;
  for (var i = start; i < lines.length; i++) {
    var fenceMatch = /^\s*(`{3,}|~{3,})/.exec(lines[i]);
    if (fenceMatch) {
      if (fence === null) fence = fenceMatch[1].charAt(0);
      else if (fenceMatch[1].charAt(0) === fence) fence = null;
      continue;
    }
    if (fence !== null) continue;
    var m = /^(#{1,6}) (.*)$/.exec(lines[i]);
    if (m) headings.push({ index: i, level: m[1].length, text: m[2].trim() });
  }

  for (var h = 0; h < headings.length; h++) {
    if (headings[h].text !== heading) continue;
    var end = lines.length;
    for (var n = h + 1; n < headings.length; n++) {
      if (headings[n].level <= headings[h].level) { end = headings[n].index; break; }
    }
    var last = headings[h].index;
    for (var k = end - 1; k > headings[h].index; k--) {
      if (lines[k].trim() !== "") { last = k; break; }
    }
    var result = lines.slice(0, last + 1).concat(entry, lines.slice(last + 1)).join("\n");
    return /\n$/.test(result) ? result : result + "\n";
  }

  while (lines.length > 0 && lines[lines.length - 1].trim() === "") lines.pop();
  var head = lines.length > 0 ? lines.join("\n") + "\n\n" : "";
  return head + "## " + heading + "\n\n" + entry.join("\n") + "\n";
}

function captureToDaily() {
  var lines = selectionLines();
  var vault = resolveVault(env("OBSIDIAN_CLIP_VAULT"));
  var cfg = readConfig(vault);
  var now = new Date();
  var heading = env("OBSIDIAN_CLIP_HEADING").trim() || "Fångat";
  var path = ensureDailyNote(vault, cfg, now);
  var content = readText(path);
  if (content === null) throw new Error("Kunde inte läsa dagens anteckning");
  writeText(path, insertCapture(content, heading, captureEntry(lines, now)));
  return "Sparat i dagens anteckning";
}

// --- Ny anteckning -----------------------------------------------------------------------

// Lowercased, NFC-normalised names (without .md) of every note in the vault, skipping hidden files and folders.
function noteNames(vault) {
  var enumerator = fm.enumeratorAtURLIncludingPropertiesForKeysOptionsErrorHandler(
    $.NSURL.fileURLWithPath(vault), $(), 4 /* NSDirectoryEnumerationSkipsHiddenFiles */, null);
  var names = ObjC.deepUnwrap(enumerator.allObjects.valueForKey("lastPathComponent")) || [];
  var set = {};
  names.forEach(function (name) {
    if (/\.md$/i.test(name)) set[name.slice(0, -3).normalize("NFC").toLowerCase()] = true;
  });
  return set;
}

function noteTitle(lines) {
  var first = "";
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== "") { first = lines[i]; break; }
  }
  var title = first.replace(/^[\s#\-*>]+/, "");
  if (title.length > 60) {
    var cut = title.slice(0, 60);
    var space = cut.search(/\s\S*$/);
    title = /\s/.test(title.charAt(60)) || space <= 0 ? cut : cut.slice(0, space);
  }
  title = title.replace(/[\\\/:*?"<>|#^\[\]]/g, "").replace(/\s+/g, " ").trim().replace(/^\.+/, "").trim();
  return title || "Namnlös";
}

function newNote() {
  var lines = selectionLines();
  var vault = resolveVault(env("OBSIDIAN_CLIP_VAULT"));
  var cfg = readConfig(vault);
  var now = new Date();

  var base = noteTitle(lines).normalize("NFC");
  var taken = noteNames(vault);
  var title = base;
  var relPath;
  for (var n = 2; ; n++) {
    relPath = join(cfg.newFileFolder, title + ".md");
    if (!taken[title.toLowerCase()] && !exists(join(vault, relPath))) break;
    title = base + " " + n;
  }
  checkWritable(relPath);

  var template = readText(join(vault, cfg.templatesFolder, "Note Template.md"));
  if (template === null) template = "# {{title}}\n\n";
  var rendered = renderTemplate(template, title, now).replace(/\s+$/, "");
  // A leading heading became the title; keeping it would repeat the template's H1.
  var bodyLines = lines.slice();
  while (bodyLines.length && bodyLines[0].trim() === "") bodyLines.shift();
  if (bodyLines.length && /^#{1,6}\s/.test(bodyLines[0])) bodyLines.shift();
  var body = bodyLines.join("\n").replace(/^\s*\n/, "");
  writeText(join(vault, relPath), (rendered === "" ? "" : rendered + "\n\n") + body + "\n");

  var vaultName = $(vault).lastPathComponent.js;
  var url = "obsidian://open?vault=" + encodeURIComponent(vaultName) +
    "&file=" + encodeURIComponent(relPath.replace(/\.md$/, ""));
  var opened = $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(url));
  return opened ? "Skapade " + title : "Skapade " + title + ", men kunde inte öppna Obsidian";
}
