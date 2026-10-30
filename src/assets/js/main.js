// main.js — light/dark theme override.
//
// The theme itself is CSS: main.css defaults to light and switches on
// prefers-color-scheme, so with this file blocked or disabled the site still
// follows the operating system. All this script adds is the ability to
// *disagree* with that preference, and a control to do it with — which is why
// the button ships `hidden` and is only revealed here.

const STORAGE_KEY = "theme";
const root = document.documentElement;

// localStorage throws rather than returning null in Safari's private mode and
// under some cookie-blocking settings. A visitor who cannot persist a choice
// should still get a working toggle for the current page.
function readStored() {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return value === "light" || value === "dark" ? value : null;
  } catch {
    return null;
  }
}

function writeStored(value) {
  try {
    localStorage.setItem(STORAGE_KEY, value);
  } catch {
    /* Preference is not persistable; it still applies to this page. */
  }
}

// Applied before the button is wired up, and as early as a deferred script
// can: parsing is done but first paint has not happened, so a stored override
// does not flash the other theme.
const stored = readStored();
if (stored) root.dataset.theme = stored;

const systemDark = window.matchMedia("(prefers-color-scheme: dark)");

function activeTheme() {
  return root.dataset.theme || (systemDark.matches ? "dark" : "light");
}

const toggle = document.getElementById("theme-toggle");

if (toggle) {
  const sync = () => toggle.setAttribute("aria-pressed", String(activeTheme() === "dark"));

  toggle.hidden = false;
  sync();

  toggle.addEventListener("click", () => {
    const next = activeTheme() === "dark" ? "light" : "dark";
    root.dataset.theme = next;
    writeStored(next);
    sync();
  });

  // Follow the OS while the visitor has not overridden it.
  systemDark.addEventListener("change", () => {
    if (!root.dataset.theme) sync();
  });
}
