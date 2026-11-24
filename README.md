# HelloID-Conn-Prov-Target-Ultimo-User

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-User/blob/main/Logo.png?raw=true">
</p>

> [!WARNING]
> Keep the following in mind before implementing this connector:
>
> - The connector relies on a custom API interface provided by an Ultimo implementation partner, see [Requirements](#requirements)
> - Set the concurrent actions of the target system in HelloID to `1`, see [API limits and quotas](#api-limits-and-quotas)
> - Ultimo cannot delete a user, so Delete is a soft-delete, see [Delete behavior](#delete-behavior)
> - `UserId`, `EmployeeId` and `GroupId` are mapped for Create only, see [Field mapping](#field-mapping)
>
> Read the [Remarks](#remarks) carefully and test in the Ultimo acceptance environment first.

## Table of contents

- [HelloID-Conn-Prov-Target-Ultimo-User](#helloid-conn-prov-target-ultimo-user)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Upgrading from version 1.x](#upgrading-from-version-1x)
    - [Execution order with Employee connector](#execution-order-with-employee-connector)
    - [Employee correlation behavior](#employee-correlation-behavior)
    - [EmployeeId cannot be updated](#employeeid-cannot-be-updated)
    - [Characters in the EmployeeId](#characters-in-the-employeeid)
    - [Language of Ultimo messages](#language-of-ultimo-messages)
    - [Custom comparison object for update logic](#custom-comparison-object-for-update-logic)
    - [Configuration and authorization group naming](#configuration-and-authorization-group-naming)
    - [Configuration group mapping](#configuration-group-mapping)
    - [Delete behavior](#delete-behavior)
    - [Permission model](#permission-model)
    - [Governance reconciliation resolutions](#governance-reconciliation-resolutions)
    - [API limits and quotas](#api-limits-and-quotas)
    - [Archived accounts](#archived-accounts)
    - [Ultimo retention period](#ultimo-retention-period)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
    - [Script conventions](#script-conventions)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Ultimo-User_ is a _target_ connector. _Ultimo-User_ provides a set of REST APIs that allow you to programmatically interact with its data.

The connector can be utilized in conjunction with the [Employee Connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee) for a full implementation. The User part of the connector provides management of User Accounts and assignment of two types of permissions: `Configuration Groups` and `Authorization Groups`.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks                                                          |
| ----------------------------------------- | --------- | --------------------------------------- | ---------------------------------------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete | Delete is a soft-delete, see [Delete behavior](#delete-behavior) |
| **Permissions**                           | ✅         | Import, Grant, Revoke                   | Authorization Groups (entitlements)                              |
| **Resources**                             | ❌         | -                                       |                                                                  |
| **Entitlement Import: Accounts**          | ✅⚠️        | -                                       | An account counts as enabled when `ActivationDateTime` is filled. Soft-deleted accounts can optionally be filtered out, see [Archived accounts](#archived-accounts) |
| **Entitlement Import: Permissions**       | ✅⚠️        | -                                       | Soft-deleted accounts can optionally be filtered out, see [Archived accounts](#archived-accounts) |
| **Governance Reconciliation Resolutions** | ✅⚠️        | Disable, Revoke                         | Delete is not supported, see [Governance reconciliation resolutions](#governance-reconciliation-resolutions) |

Legend: ✅ supported, ✅⚠️ supported with limitations, ❌ not supported.

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-User/refs/heads/main/Icon.png
```

### Requirements

**API access from Ultimo:**
- Ultimo does not provide a standard interface for user management in all environments. This connector relies on a custom API interface provided by an Ultimo implementation partner, for example Meditain.
- Assistance from an Ultimo consultant is required to enable and configure this custom interface. The consultant provides the `BaseUrl`, `ApplicationElementId` and `ApiKey`.

**System requirements:**
- The connector relies on the existence of an Ultimo employee. Employee creation can be managed using the [Employee Connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee) or another synchronization method.
- The Ultimo configuration group is determined in the field mapping (`GroupId`), see [Configuration group mapping](#configuration-group-mapping).
- The system user linked to the API key must use English, see [Language of Ultimo messages](#language-of-ultimo-messages).
- Use an API key that is configured for a single Ultimo company. When the API key is configured for multiple companies, Ultimo requires the `Ultimo-Company` header, which the connector does not send.

**Technical requirements:**
- Set the concurrent actions of the target system in HelloID to `1`. The actions run in parallel by default, which makes it likely that the Ultimo limit of 100 requests per 10 seconds is exceeded, see [API limits and quotas](#api-limits-and-quotas).

### Connection settings

The following settings are required to connect to the API.

| Setting                | Description                                                                           | Mandatory |
| ---------------------- | ------------------------------------------------------------------------------------- | --------- |
| BaseUrl                | The URL to the API                                                                    | Yes       |
| Application Element Id | The ApplicationElementId to connect to the API (required for all user-related action) | Yes       |
| ApiKey                 | The ApiKey to connect to the API                                                      | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Ultimo-User_ to a person in _HelloID_.

| Setting                   | Value               |
| ------------------------- | ------------------- |
| Enable correlation        | `True`              |
| Person correlation field  | `Person.ExternalId` |
| Account correlation field | `UserId`            |

Only `UserId` can be used as account correlation field. The connector looks up the correlation value with the Ultimo `GetUser` action, which takes a user id, so it cannot search on another field. The `UserId` field mapping (`Person.ExternalId` by default) must therefore match the person correlation field. A user that HelloID created itself is then found again on a later create.

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

All customer-specific logic, such as the mapping of a title to a configuration group or the generation of the user description, belongs in the field mapping. The scripts are generic.

| Field                 | Actions        | Remarks                                                                                                                                                              |
| --------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EmployeeId`          | Create         | Mandatory. The Ultimo employee the user belongs to. Create stops when it is empty. Not mapped for Update, see [EmployeeId cannot be updated](#employeeid-cannot-be-updated)                                   |
| `UserId`              | Create         | Mandatory. Stored in the account data. Used as correlation field. Mapped to `Person.ExternalId`, so it matches the correlation configuration. Not mapped for Update, because the Ultimo user Id cannot be changed |
| `ExternalAccountName` | Create, Update | Optional. The name of the user for external authentication. The default mapping is the `userPrincipalName` of the `Person.Accounts.MicrosoftActiveDirectory` target system, adjust it per customer. Mapped for Update too, so changing the mapping changes the value for existing users at the next update          |
| `UserDescription`     | Create, Update | Mandatory, it is required by the Ultimo `UpdateUser` action. Stored in the account data. Complex mapping that generates the display name. Optionally add a Delete mapping for the soft-delete, see [Delete behavior](#delete-behavior) |
| `GroupId`             | Create         | Mandatory, Create stops when it is empty. The Ultimo configuration group. The default is the fixed value `SELFSERV` for every user. Mapped for Create by default. Mapping it for Update is possible, but carries a risk, see [Configuration group mapping](#configuration-group-mapping)                                    |

### Account Reference

The account reference is populated with the Ultimo user property `id`.

## Remarks

### Upgrading from version 1.x

Version 2.0.0 contains breaking changes. Check the following before updating an existing implementation:

- The CSV mapping file is replaced by the `GroupId` field mapping, see [Configuration group mapping](#configuration-group-mapping).
- `UserId` is mapped to `Person.ExternalId` for Create only (it was `sAMAccountName`). Existing accounts keep their AccountReference.
- `ExternalAccountName` is mapped to the `userPrincipalName` (it was `sAMAccountName`) and is also mapped for Update, so the next update changes the value for existing users. Keep the previous mapping when that is not wanted.

### Execution order with Employee connector

Although the connector operates independently, the order of execution is crucial. When using the HelloID Ultimo Employee Connector, configure the system as a dependent system so the Employee Connector always executes before the User Connector.

For more information, see [Dependent Systems](https://docs.helloid.com/en/provisioning/target-systems/share-account-fields-between-target-systems/access-shared-target-account-fields.html).

### Employee correlation behavior

The connector first validates whether the employee exists. This can vary between environments, depending on whether auto-numbering is enabled.

The current implementation assumes auto-numbering is disabled and that the `Id` property contains the employee number.

```powershell
$getEmployeeSplatParams = @{
    Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($actionContext.Data.EmployeeId)')"
    Method = 'GET'
}
$null = Invoke-UltimoUserRestMethod @getEmployeeSplatParams
```

The employee check runs before the correlation. When the employee does not exist, `create.ps1` stops, also when the Ultimo user already exists and would only have to be correlated. This is intentional: the Employee connector or another synchronization must have created the employee first, see [Execution order with Employee connector](#execution-order-with-employee-connector).

If your implementation differs, follow the correlation method described in the [Employee Connector README](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee#remarks).

### EmployeeId cannot be updated

The `EmployeeId` of a user account cannot be updated. It is therefore only mapped for _Create_.

### Characters in the EmployeeId

The `EmployeeId` is used in the route of the Ultimo API (`Employee('{EmployeeId}')`). Ultimo does not accept the characters `/ < > * % & : \ ?` in an Id that is used in the route. `create.ps1` therefore stops with a clear error when the `EmployeeId` contains one of these characters.

### Language of Ultimo messages

The connector recognizes that a user does not exist by the English message `User {UserId} not found.` that Ultimo returns. Ultimo returns messages in the language of the system user linked to the API key (see the `Accept-Language` header in the [Ultimo documentation](https://developer.ultimo.net/api-guide/rest)). When that user uses another language, the connector can no longer recognize a missing user and reports an error instead. The message is matched loosely (`User * not found*`), so a small difference in the user id in the message does not matter. Make sure the system user of the API key uses English.

### Custom comparison object for update logic

To determine whether a user should be updated, this connector uses a custom comparison object because the API request and response bodies differ. Only properties that are mapped for _Update_ are compared, and `null` and empty values are treated as equal. The comparison is case-sensitive, so a change that only affects casing (for example `jan de vries` to `Jan de Vries`) is also updated.

When adding extra account properties, include them in this comparison object in `update.ps1`.

```powershell
$currentAccount = [PSCustomObject]@{
    ExternalAccountName = $correlatedAccount.ExternalAccountName
    UserDescription     = $correlatedAccount.Description
}
```

### Configuration and authorization group naming

The connector does not support using exactly the same name for both a configuration group and an authorization group.

### Configuration group mapping

The `GroupId` field mapping determines the Ultimo configuration group of a new user. A configuration group is mandatory when creating a user. By default every user gets the same configuration group: the fixed value `SELFSERV`.

The configuration group is part of the Ultimo user object, is sent with the `CreateUser` action and can occur only once per user. It is therefore set through the field mapping and not through Business Rules, which assign entitlements that can be granted multiple times.

To assign a different configuration group per function, replace the fixed value with a custom JavaScript mapping. The example below maps the title code of the primary contract to a configuration group, with the key `*ALL` as fallback for all other titles. Replace the title codes and configuration groups with those of the customer.

```javascript
function getGroupId(titleCode) {
    // Example mapping, replace with the title codes and Configuration Groups of the customer
    const mapping = {
        '*ALL': 'SELFSERV',
        'MANA': 'BUILDING',
        'SALES': 'BUILDING'
    };

    return mapping[titleCode] || mapping['*ALL'];
}

getGroupId(Person.PrimaryContract.Title.Code);
```

> [!WARNING]
> **`GroupId` is mapped for _Create_ by default. It can also be mapped for _Update_, but do this consciously.**
>
> The configuration group is the default group of an employee and determines the basic rights of the user in Ultimo. When `GroupId` is mapped for _Update_, the connector replaces the current configuration group of every existing user with the result of the mapping. This can have a large impact:
>
> - Users who were assigned a different configuration group in Ultimo, manually or by another process, lose that group and the rights that come with it.
> - With a custom mapping, users whose title does not occur in the mapping fall back to the `*ALL` group and can lose rights overnight, without any warning.
> - A change in the source data, such as a new title code, immediately changes the rights of the affected users on the next update.
>
> Only map `GroupId` for _Update_ when the configuration group is fully managed by HelloID, the mapping is complete and it has been tested with a DryRun on the real data. If `GroupId` is not mapped for _Update_, the connector never changes the configuration group of an existing user.

> [!IMPORTANT]
> The CSV mapping file (`mappingFilePath`) that was used before version 2.0.0 is no longer supported. Move its content to the `GroupId` field mapping.

### Delete behavior

Ultimo does not support deleting a user. Delete is therefore a soft-delete: the fields that are mapped for the _Delete_ action in the field mapping are updated. The default field mapping does not map any field for _Delete_, so by default nothing is changed.

To make a deleted user recognizable in Ultimo, add a _Delete_ mapping to a field. For example, a complex mapping on `UserDescription` that prefixes the description:

```javascript
function getValue() {
    // Use the same logic as the UserDescription mapping for Create and Update (the display name by name convention) and add the prefix
    return 'uitdienst_' + generateDisplayName();
}
getValue();
```

- When no fields are mapped for _Delete_, the user is left unchanged and this is reported in the audit log.
- When the user no longer exists, Delete is reported as successful.
- The configuration group (`GroupId`) is never part of the soft-delete.
- Delete does not disable the account, this is handled by the _Disable_ action.

### Permission model

The connector manages two permission types:

- Configuration Groups are set in `create.ps1` through the `GroupId` field mapping (by default the fixed value `SELFSERV`), because a configuration group is mandatory when creating a new user account. `update.ps1` only changes the configuration group when `GroupId` is also mapped for Update, see the warning in [Configuration group mapping](#configuration-group-mapping). Only one configuration can be applied at a time.
- Authorization Groups are managed with entitlements (`permissions/groups` scripts). The configuration group of a user is not returned as a permission when importing permissions.

### Governance reconciliation resolutions

The connector supports the _Disable_ and _Revoke_ resolutions. These only need the account reference.

The _Delete_ resolution is not supported. _Delete_ is a soft-delete that updates the fields mapped for the _Delete_ action in the field mapping, see [Delete behavior](#delete-behavior). A reconciliation resolution has no person context, so those mapped values are not available and `delete.ps1` would report success without changing anything.

### API limits and quotas

Ultimo limits the use of its REST API. The limits apply to all API keys combined, so they are shared with other integrations, such as the Employee connector. See the [Ultimo documentation on limits and quotas](https://developer.ultimo.net/api-guide/rest/limits-and-quotas). The limits can change, so check the documentation for the current values.

| Limit                                 | Value                                  | Behavior of the connector                                                                      |
| ------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Requests per 10 seconds               | 100 (all API keys combined)            | The connector waits 10 seconds and retries a maximum of 3 times, see below                      |
| Requests per day                      | 10,000 (all API keys combined)         | Not retried: the action fails until the quota resets. Plan around it                           |
| Maximum payload per request           | 1 MB                                   | Not an issue for the requests of this connector                                                |

When the limit per 10 seconds is exceeded, Ultimo returns HTTP 429 with the following message:

```json
{ "message": "Too many requests. A maximum of 100 requests per 10 seconds are allowed. Try again later.", "code": "TooManyRequests" }
```

- **Retry:** every request in the connector retries a maximum of 3 times after a 429 with the message of the limit per 10 seconds, with a delay of 10 seconds (the length of the window). Every retry is logged as a warning. When the limit is still exceeded after the last retry, the action fails and HelloID retries it in the next run.
- **Other 429 responses:** a 429 with another message, such as the daily quota, is not retried, because waiting does not help. The action fails immediately with the message of Ultimo. The exact message of the daily quota is not known (yet), so only the message of the limit per 10 seconds is recognized.
- **Concurrent actions:** set the number of concurrent actions of the target system in HelloID to `1`. A higher number makes it likely that the limit is exceeded, because the actions run in parallel and each retry counts as a request.
- **Daily quota:** the quota of 10,000 requests per day cannot be increased. A create costs 3 requests, an update 1 to 3, enable, disable and delete 2 each, and grant and revoke 2 per permission. Spread an initial load of many users over multiple days or run it outside working hours. It is possible to set a daily quota per API key in Ultimo, so the connector, the Employee connector and other parties do not block each other.
- **Payload too large:** HTTP 413 and 400 (batch size) are not retried, the request is reported as failed. The connector does not use batch requests.

### Archived accounts

A soft-deleted account stays in Ultimo, see [Delete behavior](#delete-behavior). `import.ps1` and `permissions/groups/importPermissions.ps1` contain a filter for soft-deleted accounts that is **commented out by default**. It checks whether the user description starts with `uitdienst_`.

| Phase                                                 | Filter      | Why                                                                                                                                                         |
| ----------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial implementation                                | Disabled    | Soft-deleted accounts are imported, so they can be correlated and put under management.                                                                     |
| After go-live, when Governance Reconciliation is used | **Enabled** | HelloID treats soft-deleted accounts as deleted. Without the filter they are imported as accounts without an owner and keep returning in every report.     |

To enable the filter, remove the comment characters from the lines below the comment `Optional: filter out soft-deleted accounts` in both scripts.

> [!WARNING]
> The filter only works when the _Delete_ mapping adds the prefix `uitdienst_` to the `UserDescription`. Adjust the prefix in both scripts when the _Delete_ mapping uses another value.

### Ultimo retention period

Ultimo has a retention period for active and deactivated accounts. Normally, you cannot deactivate an account that was recently activated (typically 10 days). This cannot be solved in the connector itself, so account lifecycle rules should account for this cooldown period.

## Development resources

### API endpoints

The following endpoints are used by the connector.

| Endpoint                                          | HTTP Method | Description                                                           |
| ------------------------------------------------- | ----------- | --------------------------------------------------------------------- |
| `/api/v1/object/Employee('{EmployeeId}')`         | GET         | Validate whether the referenced employee exists in Ultimo             |
| `/api/v1/action/_ExternalAuthorizationManagement` | POST        | Action endpoint for user lifecycle and authorization group management |

### API documentation

The general REST API guide of Ultimo is available at [developer.ultimo.net](https://developer.ultimo.net/api-guide/rest). The custom endpoint `_ExternalAuthorizationManagement` is not publicly documented. The custom interface and some behavior, such as auto-numbering and the use of the employee number as `Id`, can differ per Ultimo implementation. Ask the Ultimo implementation partner for the details of the environment.

### Script conventions

- Each action sets `$actionMessage` before every step, so the audit log shows what was being done when an error occurred.
- Every script contains the same `Invoke-UltimoUserRestMethod` and `Resolve-UltimoUserError` functions. Scripts that look up a user also contain `Get-UltimoUser`, which returns `$null` when the user does not exist.
- A user that cannot be found is an error for Update, Enable and Grant. For Disable, Delete and Revoke it is reported as successful, as there is nothing left to do.
- Log and audit messages refer to an existing account as `account with AccountReference: [...]`.
- The import scripts log `Starting …` and `Completed …` with the name of the HelloID script (for example `Starting import permissions script`). The messages in between describe what the script is doing.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

