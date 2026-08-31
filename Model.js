function posInt(value, fallback) {
  var n = parseInt(value, 10)
  if (!isFinite(n) || n < 0) return fallback
  return n
}

function floatOr(value, fallback) {
  var n = parseFloat(value)
  return isFinite(n) ? n : fallback
}

function mibAlloc(mib) {
  var n = Number(mib)
  if (!isFinite(n) || n < 0) return "—"
  if (n >= 1024) return (n / 1024).toFixed(n >= 10240 ? 0 : 1) + " GB"
  return String(Math.round(n)) + " MiB"
}

function speedMhz(mhz) {
  var n = Number(mhz)
  if (!isFinite(n) || n <= 0) return "—"
  if (n >= 1000) return (n / 1000).toFixed(2) + " GHz"
  return String(Math.round(n)) + " MHz"
}

function watts(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return "—"
  return n.toFixed(0) + " W"
}

function percent(a, b) {
  var num = Number(a)
  var den = Number(b)
  if (!isFinite(num) || !isFinite(den) || den <= 0) return 0
  return Math.max(0, Math.min(100, Math.round((num / den) * 100)))
}

// Space the way Style.space would for a non-scaled Spacer-like slot; used by
// the panel when Style is unreachable through a defined property only.
function gap(n) {
  return n
}

if (typeof module !== "undefined") {
  module.exports = {
    posInt: posInt,
    floatOr: floatOr,
    mibAlloc: mibAlloc,
    speedMhz: speedMhz,
    watts: watts,
    percent: percent,
    gap: gap
  }
}