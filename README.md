# Kortex for Mac

Native SwiftUI app for Kortex Finances on macOS 14+. It shares only the Firebase project with the
Android app (`../kortex`); the Android Firestore document shapes are the contract this app follows.
Designs: Figma › Kortex › "Kortex - Finances (Mac OS)".

## Layout

- `App/` — the app target: entry point, entitlements, asset catalog. Kept thin.
- `Packages/KortexKit/` — everything else (theme, fonts, screens, and later models and sync), as a
  Swift package so it builds and tests with plain `swift`.
- `project.yml` — XcodeGen spec. `Kortex.xcodeproj` is generated from it and not committed.
  Entitlements live in `project.yml`; XcodeGen rewrites `App/Kortex.entitlements`.
- `scripts/app-icon/` — the app icon from Figma (`icon.svg`, node "App icon") and the script that renders
  it onto the macOS icon grid: `xcrun swift scripts/app-icon/generate.swift` rewrites `AppIcon.appiconset`.

## Develop in VS Code

Needs Xcode (selected with `xcode-select`) and `brew install xcodegen`.

- Build: `scripts/build.sh` (VS Code: ⇧⌘B, task "Build Kortex")
- Build and open the app: `scripts/run.sh` (task "Run Kortex")
- Package tests: `xcrun swift test --package-path Packages/KortexKit` (task "Test KortexKit")

Builds land in `.build/xcode/Build/Products/Debug/Kortex.app`.

The first build compiles Firestore's C++ dependencies and takes several minutes; later ones are quick.

## Firebase and signing

- `App/GoogleService-Info.plist` comes from the Firebase console (Apple app `dev.kortex.mac` in the
  Kortex project) and is not committed. `scripts/build.sh` reads its `REVERSED_CLIENT_ID` into
  `App/Generated.xcconfig`, which becomes the URL scheme Google sign-in returns on.
- Signing is automatic with team `7CB2TRZYZ6`; the Apple ID must be signed in to Xcode › Settings ›
  Accounts. Keychain Sharing is on because Firebase Auth and GoogleSignIn keep the session there.

## Sync

`KortexCloud.FinanceSync` keeps a live listener on each `users/{uid}/fin*` collection and folds the
documents into `FinanceData`; Firestore's persistent cache is the local store. Documents are read
exactly as the Android app's `sync/finance/FinanceDocs.kt` reads them (`KortexFinance.FinanceDocs`),
and balances follow its `domain/calc/Balances.kt`.

Writes go through the rules in `KortexFinance/Write` (ported from Android's use cases: validation,
derived ids such as `rec_…` so paying a recurring payment on two devices is one entry, merchant
learning), which produce a `Change`. `FinanceSync.apply` commits it as one Firestore batch, with the
documents built field for field as Android writes them (`FinanceDocWriter`): every field written,
`serverUpdatedAt` as a server timestamp, deletes as `deleted: true` markers.

Screens and sheets only see the `KortexFinance.FinanceStore` protocol, which `FinanceSync` conforms to;
`PreviewFinanceStore` keeps everything in memory, for `#Preview`s and tests without Firebase.

## Full account numbers

The account sheet's Number field takes the full number or just the last 4, as on the phone. A full
number is sealed on this Mac (`KortexFinance.SecretBox`: AES-256-GCM in Tink's layout, bound to the
account's uid) with the user's data key and written to `finSecrets`, in the same batch as the account
and its `hasSecret`. Show reads it back after Touch ID or the Mac's password; it's never listened to.

The data key comes from the `financeKey` function, which enforces App Check, and is then kept in the
Keychain (`KortexCloud.FinanceKeys`). App Attest needs a paid Apple Developer membership, so the Mac
uses App Check's debug provider: Settings › Account Numbers shows this Mac's token, which is added
once in Firebase › App Check › Apps › dev.kortex.mac › Manage debug tokens. For a build shared with
others, switch `Cloud.configure()` to `AppAttestProviderFactory` and add the App Attest entitlement.

## Reset data

The account menu at the bottom of the sidebar has Reset Data…, which erases everything and keeps you
signed in. `FinanceSync.eraseAll` reads every `fin*` collection (`finSecrets` included) and writes a
`deleted: true` marker over each live document (`KortexFinance.ResetRules`), so the phone erases them
on its next pull, which only sees changed documents and would miss a removal. Built-in categories stay.
Receipt images in Application Support/Receipts are removed too; settings and the AI key are kept.

## Deleted accounts

Deleting an account or card keeps its entries in history ("Deleted account") unless Delete Account and
Its Entries is chosen. For accounts deleted earlier, here or on the phone, the account menu at the
bottom of the sidebar has Remove Entries of Deleted Accounts… (`AccountRules.removeLeftovers`). Either
way an entry goes only when every account it names is gone, along with deleted cards' bills. A
transfer or card payment that also involves an account you still have is part of that account's
balance, so it stays, its deleted end becoming the unknown account (`FinanceIds.unknownAccount`), and
no balance you have moves.

## Receipts

There is no Paste SMS on the Mac: reading bank SMS is the phone's job. Receipts come in by dropping
a photo or PDF on the window, File › Scan Receipt… (⌘O), or File › Import From Device (Continuity
Camera). `ReceiptScanner` reads them on this Mac with Apple Vision (a digital PDF's own text when it
has some), grouping words into printed rows; `KortexFinance.ReceiptParser` is a port of Android's
`domain/read/Receipt.kt`, with its tests. The image is copied to Application Support/Receipts and
the entry carries that path, as the phone does; images are never uploaded.

## Import a statement (Mac only)

File › Import Statement… (⇧⌘O), Accounts › Add account › From a statement…, or Import statement… on
an account or credit card. The statement's entries go into the account you started from, else the
one whose last 4 digits it prints, else a new account; the review's Add to picker changes that. The PDF's
pages are rendered on this Mac (`StatementReader`) and sent, four pages per request, to Vercel AI
Gateway (`KortexAI.AIGateway`, OpenAI-compatible chat completions with a strict JSON schema). The
default model is `anthropic/claude-sonnet-5.5`; Settings › AI switches to `anthropic/claude-opus-5.5`
for hard scans. The model is told to return only the last 4 digits of account and card numbers.

`KortexFinance.StatementImportRules.prepare` then checks every row against the printed running
balance (turning round a row that only fits the other way, flagging one that fits neither), applies
merchant memory and the suggested categories, and reconciles opening + in − out with the closing
balance. Nothing is written until the review sheet's "Add account and N entries": `commit` adds the
account, an opening entry dated to the statement's start, every included row (`source: STATEMENT`;
Android reads that as MANUAL until it knows the value) and, for a card, its bill. Entry ids derive
from the import, so saving twice doesn't duplicate.

Into an account you already have, `prepare` also reconciles every row with that account's entries
(`StatementImportRules.reconcile`): an entry matches a row when it moves the balance by the same amount
the same way (so a card bill or transfer the phone recorded matches a plain debit) within 3 days, or
carries the row's reference. Each entry matches one row, closest first. A match is sure on the same
reference, an earlier import of the row, the same day, or the same payee; otherwise (amount only, a few
days apart or under another name) it's shown as "Maybe there" under To check. Matched rows start
unticked; ticking one adds it as a second entry. The side pane compares Kortex's balance before and
after the statement with the statement's own, says whether a difference predates it, and lists the
entries Kortex has in its dates that no row matched. Saving adds no account or opening entry, and the
card's bill only if Kortex doesn't have one within 3 days of it. Entry ids derive from the account and
the row as read, so importing the same statement again finds what it added.

Each expense in the review has a Repeats choice: one-off, a new subscription or fixed payment, or
paying one you already have. It's pre-set from the model's `recurring` flag, mandate wording (NACH,
ECS, EMI…), the same merchant and amount a month apart, or a match with an existing recurring
payment; marking one row marks the merchant's other rows. On saving, rows marked to repeat are written
as the occurrence they pay (`rec_…`, as Mark paid writes them), so one the phone already auto-paid is
replaced rather than doubled, new payments are created from the latest row, and next due dates move
past what the statement paid. A new payment is monthly or yearly, chosen in the review's Recurring
box; it's pre-set to yearly only when its rows are 300+ days apart.

On a bank statement, a debit that pays a credit card bill is a Card bill payment, not money out: the
model's `cardBillPayment` flag or card-bill wording ("CC PAYMENT", "CREDIT CARD", a card's last 4
beside BillPay/BBPS) marks it (`StatementImportRules.markCardPayments`). The card it paid is the one
whose number the details print, else whose bill was for that amount (in full or the minimum), else
whose bank they name, else your only card; otherwise the review asks. Saving writes a `CARD_PAYMENT`
from this account to the card, against the card's latest bill on or before that day, so it lowers
both balances, settles the bill and isn't spending. A payment the card already has for the same amount
within 3 days from another account (a card statement's guess of where it came from) is the same one:
saving moves it to this account instead of paying the card twice. With no card in Kortex, the row
stays money out, flagged, with no category and its details kept as the note.

Bill payments on a card's own statement are linked to its bill the same way. Each also looks for the
debit a bank statement saved as money out before the card was in Kortex
(`StatementImportRules.matchOnBanks`): the same amount within 3 days from a bank, cash or wallet,
reading like a card bill or carrying the row's reference, else with no name and no category; never
one paying a recurring payment. The row is then paid from that account and saving turns the debit
into the payment (same id, the bank's date), so it stops counting as spending and the card isn't paid
twice. Choosing another paid-from account in the review leaves the debit as it is. Either order of
importing a bank and a card statement ends the same.

With no such debit, a card's bill payment is from your bank when you have exactly one, else from an
unknown account (`FinanceIds.unknownAccount`, "Unknown account" in the review): saved as a
`CARD_PAYMENT` from a uid no account has, so the card's balance is right at once and no bank's moves
(the phone shows it as a deleted account). A bank statement imported later takes it over
(`matchOnCards`): a debit with no payee for the same amount within 3 days becomes that card's bill
payment, and saving records the card's payment as paid from this bank, so both sides are assigned and
nothing is paid twice.

A card's credit that doesn't read like a bill payment (a refund, a reversal, cashback) is a Refund /
credit row, added like the rest. It's saved as a `CARD_PAYMENT` from `FinanceIds.cardCredit`, a uid
no account has: it lowers what the card owes and nothing else, pays no bill (no `statementUid`), and a
bank's debit is never taken for it. The purchase it refunds still counts as spending in full. The
phone, which has no refunds yet, shows it as a bill payment from a deleted account, with the card's
balance right; the Mac shows "Refund / credit", titled by the statement's details.

Money between your own accounts is a Transfer out or Transfer in, never spending or income, and never
in a category (`StatementImportRules.markTransfers`). A row is one when its details print another of
your accounts' last 4 digits and name no payee; one the model flags (`ownTransfer`) also counts when
the details name that account's bank. Otherwise it stays money out or in: a payment to someone else
is real spending, so the review never guesses a transfer from the amount alone. `matchTransfers` then
looks among your other accounts' entries for the other side (money in there for money out here, the
same amount within 3 days, not paying a recurring payment): one whose details print this account's
number or share the reference, or, for a transfer or flagged row, one with no payee and no category.
Saving turns it into the transfer (same id, the day the money left), so it isn't counted twice. A
flagged row with no other side in Kortex is added as money out or in, in no category, with its
details as the note, until that account's statement comes in. The review's Type menu switches any
row to a transfer and its last column picks the other account.

Two instalments with the same payee and amount (two SIPs or EMIs through Indian Clearing Corp) are
kept apart by a mandate reference when the details carry one: a code that comes back on every debit
of one mandate, never twice in a month, always for about the same amount (a route code two mandates
share fails that). Without one, a payee and amount that debits twice in most months becomes two
payments, each month's first debit going to the first and its second to the second. Debits that
match recurring payments you already have share them out the same way, in date order within the
month.

The gateway key lives in the Keychain (Settings › AI), never in the repo or the app. To check the
pipeline on a real statement without the UI, printing only counts and check results:

    AI_GATEWAY_API_KEY=… KORTEX_STATEMENT=/path/to/statement.pdf \
      xcrun swift test --package-path Packages/KortexKit --filter StatementPipelineCheck

Not on the Mac yet: the AI fallback for receipts the patterns can't fully read.
Statements are still made by the phone.
