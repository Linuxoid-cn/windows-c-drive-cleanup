# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Detailed README with maintenance, contribution and troubleshooting sections.
- `CONTRIBUTING.md`, `CHANGELOG.md`, `NOTICE`, `.gitattributes`.
- GitHub Actions workflow `validate.yml` running `scripts/validate-skill.ps1`.
- Apache-2.0 `LICENSE` (consistent with the ChatGLM3 open-source project).

## [0.1.0] - 2026-11-17

### Added
- Skill `windows-c-drive-cleanup` with `SKILL.md` and `USAGE.md`.
- Scripts: `scan-c-drive.ps1`, `clean-c-drive.ps1`, `verify-cleanup.ps1`, `run-skill.ps1`, `validate-skill.ps1`.
- Machine-readable junk catalog `resources/junk-catalog.json` (A/B/C levels, 40 targets).
- Classification rules `resources/junk-rules.md` with admission checklist.
- Report templates `templates/scan-report-template.md` and `templates/cleanup-report-template.md`.
- Safety model: allow-list only, C-level blocked, `-Yes` required, in-use files skipped, reparse points skipped.
- Verified on Windows 11 build 26200: A+B identified 24.43 GB / 55,707 files; 24.74 GB actually freed.

[Unreleased]: https://github.com/Linuxoid-cn/windows-c-drive-cleanup/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Linuxoid-cn/windows-c-drive-cleanup/releases/tag/v0.1.0
