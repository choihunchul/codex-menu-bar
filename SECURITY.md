# Security Policy

## Supported Versions

The table below outlines which versions of CodexMenuBar are actively supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| v1.x    | :white_check_mark: |
| < v1.0  | :x:                |

## Reporting a Vulnerability

We take the security of CodexMenuBar seriously. If you find any vulnerability, credential leaks, or security issues, please do not open a public issue. Instead, report it using one of the following methods:

1. **Private Vulnerability Reporting**: Use the GitHub Private Vulnerability Reporting feature on this repository.
2. **Email**: Send an email to the repository owner/maintainer. (Please refer to the repository profile or project contacts).

### What to Include in a Report
- A detailed description of the vulnerability.
- Steps to reproduce the issue (proof of concept).
- Potential impact of the vulnerability.

We will acknowledge your report within 48 hours and work with you to resolve the issue as quickly as possible.

## Security Practices & Core Values

As part of our commitment to security-first development:
- **No Hardcoded Secrets**: We strictly prohibit hardcoding any API keys, credentials, or secrets in the codebase. All configurations must be managed via environment variables (e.g., `.env` files, macOS Keychain, or build settings).
- **Static Analysis (SAST)**: We run automated security scanning (CodeQL) on every push and pull request to identify potential vulnerabilities.
- **Dependency Auditing**: We regularly monitor Swift Package Manager dependencies for known security alerts.
