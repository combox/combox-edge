(function () {
  var root = document.documentElement;
  var code = root.getAttribute("data-code") || "";

  function setText(id, value) {
    var el = document.getElementById(id);
    if (!el) return;
    el.textContent = value || "";
  }

  // Code is numeric only; human text comes from /strings/auto.json to avoid hardcoding.
  setText("code", code);

  var key = "errors.internal_error";
  if (code === "404") key = "errors.not_found";
  else if (code === "403") key = "errors.forbidden";
  else if (code === "502") key = "errors.bad_gateway";
  else if (code === "503") key = "errors.service_unavailable";
  else if (code === "504") key = "errors.gateway_timeout";

  var fallbackTitle = "Error";
  if (code === "404") fallbackTitle = "Not Found";
  else if (code === "403") fallbackTitle = "Forbidden";
  else if (code === "500") fallbackTitle = "Internal Server Error";
  else if (code === "502") fallbackTitle = "Bad Gateway";
  else if (code === "503") fallbackTitle = "Service Temporarily Unavailable";
  else if (code === "504") fallbackTitle = "Gateway Time-out";
  document.title = (code ? code + " " : "") + fallbackTitle;

  fetch("/strings/auto.json", { cache: "no-store" })
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (data) {
      if (!data) return;
      // dot-path lookup
      var parts = key.split(".");
      var cur = data;
      for (var i = 0; i < parts.length; i++) {
        if (!cur || typeof cur !== "object") { cur = null; break; }
        cur = cur[parts[i]];
      }
      if (typeof cur === "string") {
        setText("title", cur);
        document.title = (code ? code + " " : "") + cur;
      }
    })
    .catch(function () {
      // No hardcoded fallback on purpose.
    });
})();

