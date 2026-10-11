# Campus-card merchant aliases

The static configuration is published from the private
`HeZeBang/shanghaitech-cpdaily-auth` repository at
`public/api/campus-card/merchant-aliases.json`. Vercel deploys it at
`https://techpie.geekpie.club/api/campus-card/merchant-aliases.json` after a
Pull Request is merged into `main`. This Flutter repository does not deploy
that endpoint. Its bundled file is an offline fallback copy, not the source
used for future remote updates.

No account credentials, cookies, account identifiers, or transaction data are
sent when requesting the public file. On each application launch the runtime
loads its last valid cached configuration and the bundled configuration,
selecting the newer version, then makes one asynchronous request to the fixed
URL. A valid remote configuration with a higher version updates memory and the
local cache. Network failures, invalid responses, and older versions preserve
the current configuration. The refresh does not delay the transaction list,
and a new application installation is not required after the server publishes
a higher version. Missing mappings still display original merchant names.

## Configuration

`schemaVersion` is currently `1`. `version` is a positive increasing integer:
every correction, removal or rollback must be published with a higher version.
`updatedAt` is an ISO 8601 timestamp. `entries` is a full replacement snapshot,
not a patch. Omitting an old entry removes it from the next snapshot.
The bundled snapshot is version `5`. Remote corrections must use a higher
version, including removals; a newer empty snapshot removes bundled aliases
and stays effective on later launches. Bundled and remote entries are not merged.

The following entry is entirely synthetic. Do not publish it as a real mapping.

```json
{
  "merchantId": "SYNTHETIC-MERCHANT",
  "posCode": "0238",
  "alias": "Example cafeteria · Example stall",
  "verifiedAt": "2026-10-11",
  "evidence": "Synthetic example only",
  "enabled": true,
  "category": "dining"
}
```

Identifiers must be strings, including leading zeros. `posCode` is optional:
omit it for a cafeteria/area alias. `category` is optional and accepts `dining`
or `other`; use `dining` only after verification. All other entry fields are
required. Verification dates use `YYYY-MM-DD`.

Exact merchant-plus-POS matches take priority over merchant-only matches.
There is no global POS matching and no company-name inference. Duplicate keys
(even identical duplicates), conflicting names, and disabled keys suppress
matching for that identity. A blocked merchant-only key also suppresses its
terminal aliases. The UI uses the original name in these cases. An invalid
schema or entry rejects the entire new snapshot, preserving the old snapshot.
Configurations are limited to 1 MiB and 5,000 entries.

## Verification and contributions

Real transaction details were inspected locally and showed merchant and POS
identifiers, including the same POS code under different merchants. That proves
composite matching is necessary. On 2026-10-11 the user explicitly confirmed both
issue #118 pairs as verified: merchant `243000125` with POS `0238` is
`丝路二楼 · 米粉`, and the same merchant with POS `0237` is
`丝路二楼 · 炸鸡`. On 2026-10-12 the user also confirmed these exact pairs:

- `243000481` + `0302`: `校内全家`.
- `243000481` + `0305`: `校内全家`.
- `243000125` + `0235`: `丝路二楼 · 煲仔饭`.
- `243000161` + `0213`: `尚科二楼 · 滑蛋饭窗口`.
- `243000161` + `0209`: `尚科二楼 · 铁板窗口`.
- `243000381` + `0310`: `白玉兰一楼 · 麻辣香锅`.
- `243000381` + `0315`: `白玉兰一楼 · 港式烧腊窗口`.

All nine exact pairs are included in the bundled snapshot.
No merchant-wide alias is assumed for unverified terminals. The asset stores
only public merchant identifiers, names, verification dates and a nonpersonal
confirmation reference. Tests use synthetic transactions and also validate
the shipped configuration.

The repository parses `merchantno`, `merno`, `merchantid`, `poscode` and
`terminalno` as optional identifier fields. Conflicting alternate fields yield
no usable identity. Other raw fields remain available in transaction details.
If a real response uses another field, verify its meaning before adding it.

The detail screen accepts voluntary cafeteria/area, floor and stall information.
It previews these values and merchant identifiers before opening a prefilled
Issue in `HeZeBang/TechPie-flutter`. The user publishes it on GitHub. GitHub
contributions are public and require a GitHub account. Photos are previewed only
on the device; the user attaches them in GitHub after checking for faces,
payment codes and account information. No photo is automatically uploaded.
Amounts, timestamps, account identifiers, transaction IDs and raw history are
excluded from the generated Issue. An unknown identity's invitation appears
once per device; the manual contribution action remains available.

macOS's image picker requires `com.apple.security.files.user-selected.read-only`,
which is included in the shared Debug and Release entitlements. Local signing
overrides that replace the entitlement file must retain this permission too.

Maintainers compare duplicate submissions and conflicts, verify a real purchase
and location, then publish an alias with a verification date and a brief
nonpersonal evidence reference. Never paste account information or full history
into public evidence. Terminal replacements, closures and ambiguous identifiers
require correction/removal or `enabled: false` in a higher version. A submitted
Issue is only a pending lead and never changes public aliases automatically.

## Balance

`补足信用额度` records are still parsed as `creditReplenishment`. By default,
all transaction lists hide those records and records with merchant `900000001`
and no POS code (such as payment-code settings). Their details are hidden too.
The campus-card settings switch `显示所有记录` reveals these records and their
details for debugging. This preference defaults to off and persists only on the
device. Hidden records do not count toward the payment page's minimum visible
history count. Server pagination and balance parsing remain unchanged.

The displayed balance is parsed from `/home` → `cardinfo.cardbal` in yuan.
Payment-code responses may refresh the same snapshot from `data.cardbal`, using
the existing account and response-order guards. This change does not alter the
calculation or claim it represents cash rather than a credit-related balance.
The official account/credit meaning still requires verification.
