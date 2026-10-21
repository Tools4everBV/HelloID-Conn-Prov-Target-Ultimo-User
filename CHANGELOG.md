# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 21-10-2026

### Added
- `delete.ps1`: Ultimo does not support deleting a user, so Delete is a soft-delete that updates the fields mapped for the _Delete_ action. No field is mapped for _Delete_ by default; the README describes an example, such as prefixing the `UserDescription`
- Governance reconciliation resolution for Delete
- README: sections for the configuration group mapping, delete behavior, governance reconciliation resolutions, script conventions and a field mapping overview

### Changed
- **BREAKING**: The configuration group is determined by the `GroupId` field mapping. The CSV mapping file (`mappingFilePath` in the configuration and `assets/ConfigurationMapping.csv`) has been removed. Move the content of the CSV to the `GroupId` field mapping, see the example in `fieldMapping.json`
- **BREAKING**: Permission scripts renamed to `grantPermission.ps1`, `revokePermission.ps1`, `permissions.ps1` and `importPermissions.ps1`
- **BREAKING**: `importPermissions.ps1` returns `Reference` as permission reference, matching the `Reference` returned by `permissions.ps1`. This was `Id` before
- All scripts rebuilt to the current HelloID PowerShell V2 structure: `$actionMessage` for every step, audit logs with an `Action`, `DryRun` handling per action and consistent error handling. The `Resolve-Ultimo-UserError` function is renamed to `Resolve-UltimoUserError`
- Looking up a user is done by the shared `Get-UltimoUser` function in each script
- Update only compares the properties that are mapped for _Update_, and treats `null` and empty values as equal
- Request bodies are sent as UTF-8
- `UserId` and `UserDescription` are stored in the account data
- Disable, Revoke and Delete report a user that cannot be found as successful
- `GroupId` field mapping is a complex mapping with an example title to configuration group mapping, and is mapped for _Create_ only. Mapping it for _Update_ replaces the configuration group of existing users, which can cause them to lose rights. The README contains a warning
- `UserDescription` field mapping is a complex mapping that generates the display name from the name convention, instead of the HelloID display name

### Fixed
- The message that is checked for a user that is not found during Create used an empty value, so a non-existing user could result in an error instead of a new account
- `importPermissions.ps1` only returns permissions that are also returned by `permissions.ps1`, as HelloID cannot link any other permission
- `import.ps1` no longer fails when Ultimo returns no users

## [1.1.0] - 25-11-2025

### Added
- Import scripts

## [1.0.0] - 26-06-2024

This is the first official release of HelloID-Conn-Prov-Target-Ultimo-User.
