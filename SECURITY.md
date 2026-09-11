# Security

This is a pre-release configuration kit. Report a suspected privacy leak or unintended approval privately through the repository's GitHub security reporting feature when enabled. If that feature is unavailable, contact the maintainer through their published profile contact without posting sensitive evidence publicly.

Never include credentials, raw app content or real clipboard data. Describe the action, app version and expected result with synthetic text.

Accessibility permission is powerful. Review the source before granting it. Y intentionally targets Allow once only. No matching, unique permission controls means no approval, even when a generic Return key would have worked.

Source builds are ad-hoc signed, not notarized. No unsigned prebuilt release should be presented as a verified, notarized product. Signing and distribution are separate release decisions.
