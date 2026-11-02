"use strict";
(function () {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Ho_Chi_Minh",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });

  function today(instant = new Date()) {
    const parts = Object.fromEntries(
      formatter.formatToParts(instant).map(part => [part.type, part.value]),
    );
    return parts.year + "-" + parts.month + "-" + parts.day;
  }

  // Compare YYYY-MM-DD dates directly; do not turn a licence date into an instant.
  function isLicenseExpired(expiresAt, instant = new Date()) {
    return Boolean(expiresAt) && expiresAt < today(instant);
  }

  window.VietnamDate = Object.freeze({ today, isLicenseExpired });
})();
