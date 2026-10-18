# Publishing checklist

1. Publish the contents of this `Nuni` directory as the root of [github.com/myoh0623/Nuni](https://github.com/myoh0623/Nuni). Do not present the surrounding Lunar checkout as Nuni's own work.
2. Keep `LICENSE`, `THIRD_PARTY_NOTICES.md`, and `LICENSES/Lunar-MIT.txt` in source and binary distributions.
3. Replace the development bundle identifier `org.nuni.display` with a reverse-DNS identifier under a domain you control before notarized distribution.
4. Keep release certificates, notarization credentials, and update-signing keys outside the repository.
5. Run `./verify.sh` and resolve every failure before tagging a release.
6. Sign and notarize release builds. The included script only creates an ad-hoc signature for local use.
7. Re-test on each supported macOS release because dynamically loaded display APIs can change.
8. Do not add hidden Lunar sources, licence bypasses, Lunar signing materials, or a bundled `ddcctl` binary.

The name search performed during development was only a basic conflict check, not a formal trademark clearance. Check the intended countries and software categories before a public launch.
