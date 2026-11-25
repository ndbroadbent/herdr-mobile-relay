const e = new URL(window.__HERDR_ENTRY__ || "/builds/0.27.0-525-33f54c75b9efb30a/index.html", location);
  e.search = location.search;
  e.hash = location.hash;
  location.replace(e);
