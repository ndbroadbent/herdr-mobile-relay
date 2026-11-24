const e = new URL(window.__HERDR_ENTRY__ || "/builds/0.27.0-523-2aebe549009b2df7/index.html", location);
  e.search = location.search;
  e.hash = location.hash;
  location.replace(e);
