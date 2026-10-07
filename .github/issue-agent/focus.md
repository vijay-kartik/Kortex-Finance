# Daily issue agent — focus areas

The scheduled Claude agent (`.github/workflows/claude-daily-issues.yml`) reads this file
on every run. Edit the list below to steer what it looks for; the change takes effect
on the next run once it is on `main`.

The agent runs every 4 hours (6 times a day, first run at 04:00 IST) and files one issue
per run. Each run is assigned the next area in this list, wrapping back to 1 after the
last, so with 10 areas every area comes up once every 40 hours. If a run finds nothing
worth filing in its area, it moves on to the next area in the list.

Keep each area on the form `N. **Title** — description`: the workflow reads the bold
titles to build the rotation and the `area:<title>` labels.

## Focus areas

1. **Bugs and crashes** — force unwraps and `try!`, swallowed errors, Swift concurrency
   mistakes (actor isolation, `Sendable`, unstructured `Task`s that outlive their view),
   Firestore listeners that are never removed, retain cycles in closures.
2. **Security and privacy** — finance data and full account numbers (`SecretBox`,
   `finSecrets`), Keychain usage, the AI Gateway key, secrets in source, sensitive data in
   logs, sandbox entitlements in `project.yml` broader than needed.
3. **Android parity** — the Android app (vijay-kartik/Kortex) is the contract: Firestore
   document shapes, field names, derived ids, the data-key/secret format and balance rules
   must match it. Flag divergences that would corrupt or misread data on either side.
4. **Architecture** — the package layering: `KortexFinance` stays plain Swift (no Firebase,
   no SwiftUI), `KortexCloud` is the only layer that talks to Firebase, screens go through
   `AppModel`/the write rules instead of touching Firestore, and `App/` stays thin.
5. **Performance** — work on the main actor (OCR, PDF reading, folding large snapshots),
   needless SwiftUI view invalidation, unbounded lists or queries.
6. **Test coverage** — important logic (calculators, write rules, document decoding and
   writing, statement and receipt parsing) with no tests in `Packages/KortexKit/Tests`.
7. **Design system** — the code must follow the design guide in the Figma project, page
   "Kortex - Finances (Mac OS)". Figma project link Kortex file: https://www.figma.com/design/8CBjHcKRkTl4AroVOQlhL4/Kortex?m=auto&t=9HVYWMYh5Rh0d1pZ-6
8. **Clean architecture** — Code must follow clean architecture everywhere. Clean code principles and SOLID principles as well.
9. **Code duplication** — Any duplication in code if it can be reduced, must be reduced. Though not at the cost of code readability.
10. **New Features** — Suggest incremental improvements in the existing features, and also request for new features with the mindset of bettering this product as a native Mac app.


## Out of scope

- Pure style or formatting nits.
- Decided Mac-only differences from Android: no Paste SMS (reading bank SMS is
  phone-only), and statement import with the `STATEMENT` entry source.
- App Check's debug provider instead of App Attest (documented in `README.md`).
