/* Umami's before-send hook for cuebox.gd. Loaded just before the counter (both
   deferred, so they run in order). Keeps a referrer to its origin: which site
   sent someone here, never which page or search. What is counted is written out
   on /licenses/ under "Privacy"; change that first if anything else is counted. */
window.cueboxAnalytics = function (type, payload) {
  try {
    if (payload && payload.referrer) payload.referrer = new URL(payload.referrer).origin;
  } catch (e) {
    if (payload) payload.referrer = "";
  }
  return payload;
};
