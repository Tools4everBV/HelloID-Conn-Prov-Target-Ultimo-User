# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-11-24

### Added
- `delete.ps1`: Ultimo does not support deleting a user, so Delete is a soft-delete that updates the fields mapped for the _Delete_ action. No field is mapped for _Delete_ by default; the README describes an example, such as prefixing the `UserDescription`
- Retry for requests that exceed the Ultimo limit of 100 requests per 10 seconds (HTTP 429): a maximum of 3 retries with a delay of 10 seconds. Other 429 responses, such as the daily quota, are not retried, and a README section on the API limits and quotas
- `create.ps1` validates that the `EmployeeId` does not contain characters that Ultimo does not accept in an Id in the route of the API
- Optional filter for soft-deleted accounts in `import.ps1` and `importPermissions.ps1` (commented out by default), see the README section _Archived accounts_
- README: sections for the configuration group mapping, delete behavior, governance reconciliation resolutions, script conventions and a field mapping overview

### Changed
- **BREAKING**: The configuration group is determined by the `GroupId` field mapping. Move the content of the CSV mapping file to the `GroupId` field mapping, see the example in `fieldMapping.json`
- **BREAKING**: `GroupId` is mapped for _Create_ by default. It can also be mapped for _Update_, but that replaces the configuration group of existing users, which can cause them to lose rights. The README contains a warning
- `EmployeeId` and `UserId` are mapped for _Create_ only, because they cannot be updated. `UserId` is now mapped to `Person.ExternalId` (was a `sAMAccountName` complex mapping), so a user created by HelloID is found again by the correlation on `Person.ExternalId`. Existing accounts are not affected, because the AccountReference comes from the Ultimo response. Re-import `fieldMapping.json` or adjust the mapping, and keep the previous mapping when existing implementations rely on it
- `GroupId` defaults to the fixed configuration group `SELFSERV` for every user. A different group per function is possible with a custom JavaScript mapping, see the example in the README
- Update compares case-sensitively, so a change that only affects casing is updated
- `ExternalAccountName` is mapped to `Person.Accounts.MicrosoftActiveDirectory.userPrincipalName` by default (was `sAMAccountName`), the most used value for external authentication. It is mapped for Update too, so existing implementations that rely on the previous value should keep their own mapping, otherwise the next update changes it
- `update.ps1` keeps `UserId` (from the AccountReference) in the account data, although it is not mapped for Update
- A user that does not exist is recognized with a looser match on the Ultimo message (`User * not found*`)
- `import.ps1` returns only the fields of the field mapping (`UserId`, `ExternalAccountName`, `UserDescription` and `GroupId`) as account data instead of the full Ultimo object
- `fieldMapping.json` descriptions mark the mandatory fields and describe `UserId` and `ExternalAccountName`
- README: the Governance reconciliation resolutions are Disable (supported) and Delete (not supported) because a resolution has no person context. Added remarks on the account status after create, the correlation on `UserId`, the employee check before the correlation, the configuration group mapping (not through Business Rules) and upgrading from version 1.x
- README: warning block, requirements split in API access, system and technical requirements (concurrent actions), and a link to the Ultimo API guide
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
- `importPermissions.ps1` returned `Id` as permission reference key instead of `Reference`, so HelloID could not link imported permissions to the permissions returned by `permissions.ps1`
- `importPermissions.ps1` no longer fails when Ultimo returns no authorization groups

## [1.1.0] - 2025-11-25

### Added
- Import scripts

## [1.0.0] - 2024-06-26

This is the first official release of HelloID-Conn-Prov-Target-Ultimo-User.
