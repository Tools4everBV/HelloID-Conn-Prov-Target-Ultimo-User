# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 21-10-2026

### Added
- `delete.ps1`: Ultimo does not support deleting a user, so Delete is a soft-delete that updates the fields mapped for the _Delete_ action. No field is mapped for _Delete_ by default; the README describes an example, such as prefixing the `UserDescription`
- Governance reconciliation resolution for Delete
- README: sections for the configuration group mapping, delete behavior, governance reconciliation resolutions, script conventions and a field mapping overview

### Changed
- **BREAKING**: The configuration group is determined by the `GroupId` field mapping. Move the content of the CSV mapping file to the `GroupId` field mapping, see the example in `fieldMapping.json`
- **BREAKING**: `GroupId` is mapped for _Create_ only. Mapping it for _Update_ replaces the configuration group of existing users, which can cause them to lose rights. The README contains a warning
- **BREAKING**: `importPermissions.ps1` returns `Reference` as permission reference, matching the `Reference` returned by `permissions.ps1`. This was `Id` before
- `EmployeeId` is mapped for _Create_ only, because it cannot be updated
- `UserDescription` field mapping is a complex mapping that generates the display name from the name convention, instead of the HelloID display name
- `UserId` and `UserDescription` are stored in the account data
- All scripts rebuilt to the current HelloID PowerShell V2 structure: `$actionMessage` for every step, audit logs with an `Action`, `DryRun` handling per action and consistent error handling
- The `Resolve-Ultimo-UserError` function is renamed to `Resolve-UltimoUserError`, and looking up a user is done by the shared `Get-UltimoUser` function
- Log and audit messages refer to an account as `account with AccountReference: [...]`, and the import scripts log `Starting …` and `Completed …` with the name of the HelloID script
- Update only compares the properties that are mapped for _Update_, and treats `null` and empty values as equal
- Request bodies are sent as UTF-8
- Disable, Revoke and Delete report a user that cannot be found as successful
- Permission scripts renamed: `RevokePermission.ps1` to `revokePermission.ps1` and `importPermission.ps1` to `importPermissions.ps1`

### Removed
- The CSV configuration mapping: the `mappingFilePath` connection setting and `assets/ConfigurationMapping.csv`

### Fixed
- Create checked a user that could not be found against the `UserId` from the field mapping instead of the correlation value, so a non-existing user could result in an error instead of a new account
- `importPermissions.ps1` only returns permissions that are also returned by `permissions.ps1`, as HelloID cannot link any other permission
- `import.ps1` no longer fails when Ultimo returns no users

## [1.1.0] - 25-11-2025

### Added
- Import scripts

## [1.0.0] - 26-06-2024

This is the first official release of HelloID-Conn-Prov-Target-Ultimo-User.
