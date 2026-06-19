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
    - [Configuration mapping behavior](#configuration-mapping-behavior)
    - [Permission model](#permission-model)
    - [Ultimo retention period](#ultimo-retention-period)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Ultimo-User_ is a _target_ connector. _Ultimo-User_ provides a set of REST APIs that allow you to programmatically interact with its data.

The connector can be utilized in conjunction with the [Employee Connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee) for a full implementation. The User part of the connector provides management of User Accounts and assignment of two types of permissions: `Configuration Groups` and `Authorization Groups`.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                         | Remarks                             |
| ----------------------------------------- | --------- | ------------------------------- | ----------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable | Delete is not available             |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke         | Authorization Groups (entitlements) |
| **Resources**                             | ❌         | -                               |                                     |
| **Entitlement Import: Accounts**          | ✅         | -                               |                                     |
| **Entitlement Import: Permissions**       | ✅         | -                               |                                     |
| **Governance Reconciliation Resolutions** | ✅         | Disable, Revoke                 | Delete is not available             |

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
- A mapping CSV file is required to determine the Ultimo configuration group. An example is available in `assets/ConfigurationMapping.csv`.

### Connection settings

The following settings are required to connect to the API.

| Setting                | Description                                                                           | Mandatory |
| ---------------------- | ------------------------------------------------------------------------------------- | --------- |
| BaseUrl                | The URL to the API                                                                    | Yes       |
| ApiKey                 | The ApiKey to connect to the API                                                      | Yes       |
| Application Element Id | The ApplicationElementId to connect to the API (required for all user-related action) | Yes       |
| Mapping File Path      | The file path of the configuration mapping CSV file                                   | Yes       |

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
$splatInvoke = @{
    Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($actionContext.Data.EmployeeId)')"
    Method = 'GET'
}
$employee = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false
```

If your implementation differs, follow the correlation method described in the [Employee Connector README](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee#remarks).

### EmployeeId cannot be updated

The `EmployeeId` of a user account cannot be updated.

### Custom comparison object for update logic

To determine whether a user should be updated, this connector uses a custom comparison object because the API request and response bodies differ.

When adding extra account properties, include them in this comparison object in both `create.ps1` and `update.ps1`.

```powershell
$previousAccount = [PSCustomObject]@{
    ExternalAccountName = $user.ExternalAccountName
    UserDescription     = $user.Description
}
```

### Configuration and authorization group naming

The connector does not support using exactly the same name for both a configuration group and an authorization group.

### Configuration mapping behavior

The configuration mapping file maps a HelloID value (currently primary contract `Title.Code`) to an Ultimo configuration group.

### Permission model

The connector manages two permission types:

- Configuration Groups are managed directly in `create.ps1` and `update.ps1` because a configuration group is mandatory when creating a new user account. Only one configuration can be applied at a time.
- Authorization Groups are managed with entitlements (`permissions/groups` scripts).

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

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

