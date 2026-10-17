# Developer ID signing and Apple notarization

[Apple workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)

Apple notarization checks Developer ID-signed macOS software for malware and signing issues. It is separate from Mac App Store review; LumaShot can continue to be distributed through GitHub Releases.

## Prerequisites / 准备条件

- An active Apple Developer Program membership and access to the appropriate developer team. The standard annual membership is USD 99 or the local price shown by Apple. An existing membership covers the program's supported Apple platforms.
- A valid **Developer ID Application** certificate **and its private key** in this Mac's keychain. Apple Development and Apple Distribution certificates are not substitutes. Creating a local Developer ID certificate normally requires the Account Holder role.
- Xcode with `notarytool`, `stapler`, and `codesign` available.
- Notary-service credentials stored locally in a keychain profile. The signing certificate and notary profile must belong to the same team.

App Sandbox is not a notarization requirement. This workflow enables Hardened Runtime and secure timestamping without adding unrelated runtime exceptions or sandbox restrictions.

## 1. Create or install the certificate / 证书

In Xcode → Settings → Accounts, select the paid team and use Manage Certificates to create **Developer ID Application**, if your role allows it. Alternatively, the Account Holder can use Apple Developer → Certificates, Identifiers & Profiles → Certificates → + → Developer ID → Developer ID Application and follow Apple's CSR instructions. Install the resulting certificate on the Mac that holds its private key.

Confirm the identity locally:

```sh
security find-identity -v -p codesigning
```

The list should contain `Developer ID Application: Your Name (TEAMID)`. No signing identity means the certificate/private-key pair is missing, invalid, expired, or unavailable in the keychain search list.

## 2. Store notarization credentials / 公证认证

Run this **in your local Terminal**:

```sh
xcrun notarytool store-credentials LumaShot-notary
```

Follow the secure interactive prompts. One supported route is your developer Apple Account, its team ID, and an **app-specific password** generated in Apple Account settings. Use the same team as the Developer ID certificate. The command validates and stores credentials in Keychain. A supported App Store Connect API key can also be stored using Apple's documented flags.

Do not put passwords, certificate private keys, API `.p8` files, or exported `.p12` files in the repository or chat. No credentials need to be sent to a collaborator for this local workflow.

## 3. Build, sign, submit, staple, verify / 一键流程

```sh
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='LumaShot-notary' \
./scripts/notarize.sh
```

The identity may also be specified using its SHA-1 fingerprint from `security find-identity`. This fingerprint identifies the certificate; it is not the private key.

The script:

1. Rejects non-Developer-ID identities before building or contacting Apple.
2. Builds a universal app, signs it with Hardened Runtime and secure timestamping, and keeps a dedicated copy for the submission.
3. Uploads a ZIP and records Apple's submission ID under `build/notarization/submission.XXXXXX/`.
4. Waits up to 20 minutes and saves Apple's result and log.
5. Requires `Accepted`, staples the ticket to the **app**, validates it, and runs Gatekeeper assessment.
6. Creates a fresh `*-notarized.zip` containing the stapled app, plus a SHA-256 checksum.

Notarization processing time varies. A wait timeout does not cancel Apple's processing. Resume the same local copy without resubmitting:

```sh
NOTARY_PROFILE='LumaShot-notary' \
./scripts/notarize.sh --resume build/notarization/submission.XXXXXX
```

Do not alter the saved submission app between submission and stapling. Keep the local session directory until the result is verified.

## Distribution / 发布

The notarization script does not upload to GitHub or replace existing release assets. Publish the resulting notarized ZIP and its matching checksum only after successful validation. A new patch release is preferable to silently replacing a previously downloaded artifact. Update release notes to state the actual signature and notarization status.

The existing default build and public CI remain ad-hoc signed unless `DEVELOPER_ID_APPLICATION` is explicitly set. Keep private signing material out of pull-request workflows.
