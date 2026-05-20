# Security Policy

## Supported Versions

OtoChef is currently pre-1.0. Security fixes are handled on the `main` branch.

## Reporting A Vulnerability

Please do not report security issues in public GitHub issues.

If you believe you found a vulnerability, contact the maintainers privately with:

- A description of the issue and impact.
- Steps to reproduce.
- A minimal proof of concept, if available.
- Any affected OtoChef version, commit, or configuration.

The maintainers will acknowledge the report, investigate, and coordinate a fix before public disclosure when appropriate.

## Sensitive Data

OtoChef should never commit or persist API keys, local model files, generated app bundles, build output, or local media. Provider API keys belong in macOS Keychain accounts named `translation-api-key.<provider>`.
