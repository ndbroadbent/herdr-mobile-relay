const e = new URL(window.__HERDR_ENTRY__ || "/builds/0.27.0-524-1c7deecdb1a708b3/index.html", location);
  e.search = location.search;
  e.hash = location.hash;
  location.replace(e);
