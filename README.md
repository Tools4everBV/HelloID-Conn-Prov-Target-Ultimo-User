# HelloID-Conn-Prov-Target-Ultimo-User

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-User/blob/main/Logo.png?raw=true">
</p>

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
    - [Execution order with Employee connector](#execution-order-with-employee-connector)
    - [Employee correlation behavior](#employee-correlation-behavior)
    - [EmployeeId cannot be updated](#employeeid-cannot-be-updated)
    - [Custom comparison object for update logic](#custom-comparison-object-for-update-logic)
    - [Configuration and authorization group naming](#configuration-and-authorization-group-naming)
    - [Configuration group mapping](#configuration-group-mapping)
    - [Delete behavior](#delete-behavior)
    - [Permission model](#permission-model)
    - [Governance reconciliation resolutions](#governance-reconciliation-resolutions)
    - [API limits and quotas](#api-limits-and-quotas)
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
| **Entitlement Import: Accounts**          | ✅         | -                                       |                                                                  |
| **Entitlement Import: Permissions**       | ✅         | -                                       |                                                                  |
| **Governance Reconciliation Resolutions** | ✅         | Disable, Delete, Revoke                 | Delete is a soft-delete                                          |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-User/refs/heads/main/Icon.png
```

### Requirements

- Ultimo does not provide a standard interface for user management in all environments. This connector relies on a custom API interface provided by an Ultimo implementation partner.
- Assistance from an Ultimo consultant is required to enable and configure this custom interface.
- The connector relies on the existence of an Ultimo employee. Employee creation can be managed using the [Employee Connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee) or another synchronization method.
- The Ultimo configuration group is determined in the field mapping (`GroupId`), see [Configuration group mapping](#configuration-group-mapping).

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

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

All customer-specific logic, such as the mapping of a title to a configuration group or the generation of the user description, belongs in the field mapping. The scripts are generic.

| Field                 | Actions        | Remarks                                                                                                                                                              |
| --------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EmployeeId`          | Create         | The Ultimo employee the user belongs to. Not mapped for Update, see [EmployeeId cannot be updated](#employeeid-cannot-be-updated)                                   |
| `UserId`              | Create, Update | Stored in the account data. Used as correlation field                                                                                                                |
| `ExternalAccountName` | Create, Update |                                                                                                                                                                      |
| `UserDescription`     | Create, Update | Stored in the account data. Complex mapping that generates the display name. Optionally add a Delete mapping for the soft-delete, see [Delete behavior](#delete-behavior) |
| `GroupId`             | Create         | The Ultimo configuration group. Mapped for Create by default. Mapping it for Update is possible, but carries a risk, see [Configuration group mapping](#configuration-group-mapping)                                    |

### Account Reference

The account reference is populated with the Ultimo user property `id`.

## Remarks

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

If your implementation differs, follow the correlation method described in the [Employee Connector README](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee#remarks).

### EmployeeId cannot be updated

The `EmployeeId` of a user account cannot be updated. It is therefore only mapped for _Create_.

### Custom comparison object for update logic

To determine whether a user should be updated, this connector uses a custom comparison object because the API request and response bodies differ. Only properties that are mapped for _Update_ are compared, and `null` and empty values are treated as equal.

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

The `GroupId` field mapping determines the Ultimo configuration group of a new user. A configuration group is mandatory when creating a user. The default mapping is a complex mapping that maps the primary contract `Title.Code` to a configuration group, with the key `*ALL` as fallback for all other titles. Adjust the example in `fieldMapping.json` to the configuration groups of the customer.

> [!WARNING]
> **`GroupId` is mapped for _Create_ by default. It can also be mapped for _Update_, but do this consciously.**
>
> The configuration group is the default group of an employee and determines the basic rights of the user in Ultimo. When `GroupId` is mapped for _Update_, the connector replaces the current configuration group of every existing user with the result of the mapping. This can have a large impact:
>
> - Users who were assigned a different configuration group in Ultimo, manually or by another process, lose that group and the rights that come with it.
> - Users whose title does not occur in the mapping fall back to the `*ALL` group and can lose rights overnight, without any warning.
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
    return 'uitdienst_' + Person.DisplayName;
}
getValue();
```

- When no fields are mapped for _Delete_, the user is left unchanged and this is reported in the audit log.
- When the user no longer exists, Delete is reported as successful.
- The configuration group (`GroupId`) is never part of the soft-delete.
- Delete does not disable the account, this is handled by the _Disable_ action.

### Permission model

The connector manages two permission types:

- Configuration Groups are set in `create.ps1` through the `GroupId` field mapping, because a configuration group is mandatory when creating a new user account. `update.ps1` only changes the configuration group when `GroupId` is also mapped for Update, see the warning in [Configuration group mapping](#configuration-group-mapping). Only one configuration can be applied at a time.
- Authorization Groups are managed with entitlements (`permissions/groups` scripts). The configuration group of a user is not returned as a permission when importing permissions.

### Governance reconciliation resolutions

The connector supports the _Disable_, _Delete_ and _Revoke_ resolutions. _Delete_ is a soft-delete, see [Delete behavior](#delete-behavior).

### API limits and quotas

Ultimo limits the use of its REST API. The limits apply to all API keys combined, so they are shared with other integrations, such as the Employee connector. See the [Ultimo documentation on limits and quotas](https://developer.ultimo.net/api-guide/rest/limits-and-quotas). The limits can change, so check the documentation for the current values.

| Limit                                 | Value                                  | Behavior of the connector                                                                      |
| ------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Requests per 10 seconds               | 100 (all API keys combined)            | The connector waits 10 seconds and retries a maximum of 3 times, see below                      |
| Requests per day                      | 10,000 (all API keys combined)         | Cannot be handled by the connector, the action fails until the quota resets. Plan around it    |
| Maximum payload per request           | 1 MB                                   | Not an issue for the requests of this connector                                                |

When the limit per 10 seconds is exceeded, Ultimo returns HTTP 429 with the following message:

```json
{ "message": "Too many requests. A maximum of 100 requests per 10 seconds are allowed. Try again later.", "code": "TooManyRequests" }
```

- **Retry:** every request in the connector retries a maximum of 3 times after a 429, with a delay of 10 seconds (the length of the window). Every retry is logged as a warning. When the limit is still exceeded after the last retry, the action fails and HelloID retries it in the next run.
- **Concurrent actions:** set the number of concurrent actions of the target system in HelloID to `1`. A higher number makes it likely that the limit is exceeded, because the actions run in parallel and each retry counts as a request.
- **Daily quota:** the quota of 10,000 requests per day cannot be increased. A create costs 3 requests, an update 1 to 3, enable, disable and delete 2 each, and grant and revoke 2 per permission. Spread an initial load of many users over multiple days or run it outside working hours. It is possible to set a daily quota per API key in Ultimo, so the connector, the Employee connector and other parties do not block each other.
- **Payload too large:** HTTP 413 and 400 (batch size) are not retried, the request is reported as failed. The connector does not use batch requests.
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

Not available.

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

