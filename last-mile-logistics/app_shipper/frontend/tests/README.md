# Frontend checks

Run the Node.js unit tests with `npm.cmd test`. Run the sidebar browser check with `npm.cmd run test:sidebar-layout`.

The accounts and admin browser suites use `npm.cmd run test:accounts` and `npm.cmd run test:admin`. Other `*-browser.cjs` and SQL/PowerShell harnesses require their documented local API, database, and browser prerequisites.

Generated screenshots, reports, browser profiles, and build output belong under `.artifacts/`; they are temporary and can be removed at any time.
