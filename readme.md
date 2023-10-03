
# HelloID-Conn-Prov-Target-Ultimo-User



| :information_source: Information  |
| :-------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/ultimo-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Ultimo-User](#helloid-conn-prov-target-ultimo-user)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
      - [Creation / correlation process](#creation--correlation-process)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Ultimo-User_ is a _target_ connector. Ultimo-User provides a set of REST API's that allow you to programmatically interact with its data. The connector can be utilized in conjunction with the [Employee Connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee) for a full implementation *(Additional details can be found in the [Remarks](#remarks))*. The User part of the connector provides management of User Accounts and assignment of two types of Permissions. Specifically `Configuration Groups` and `Authorization Groups`.

The following lifecycle events are available:

| Event  | Description | Notes
|---	 |---	|---
| create.ps1 | Create (or update) and correlate an Account and grants or change Configuration Groups| -
| update.ps1 | Update the Account and grants or change Configuration Groups | - |
| enable.ps1 | Enable the Account | - |
| disable.ps1 | Disable the Account | - |
| delete.ps1 | n/a | - |
| grant.ps1 | Grants a permission (Authorization Groups) to the Account | - |
| revoke.ps1 | Revokes a permission (Authorization Groups) from the Account | - |
| entitlements.ps1 | Retrieves all Authorization Groups | - |


## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting                | Description                             | Mandatory |
| ---------------------- | --------------------------------------- | --------- |
| BaseUrl                | The URL to the API      | Yes       |
| ApiKey                 | The ApiKey to connect to the API           | Yes       |
| Application Element Id | The ApplicationElementId to connect to the API *(required for all the user action)* | Yes       |
| Mapping File Path   | The File Path of the mapping file with the Configuration Mapping.                    | Yes       |

### Prerequisites
 - The Ultimo User connector relies on the existence of an existing Ultimo employee. The employee creation can be managed using the [Employee Connector](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee) or by implementing a different synchronization method with the HR system
 - A mapping CSV file is required to determine the configuration group. An example of the mapping file can be found in the Asset folder


### Remarks
- Although the connector operates independently, the order of execution is crucial. When using the HelloID Ultimo Employee Connector, make sure to designate the system as a dependent system. This guarantees that the Employee Connector consistently executes before the User Connector. [Read more about Dependent Systems](https://docs.helloid.com/en/provisioning/target-systems/share-account-fields-between-target-systems/access-shared-target-account-fields.html).
<br>
- The connector first verifies whether the employee exists. However, this process can vary between instances, depending on whether auto-numbering is enabled. For more information about correlation, please refer to the [Employee Connector remarks](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Ultimo-Employee#remarks). The current implementation in the connector assumes that auto-numbering is disabled and that the 'Id' property contains the employee number. If your implementation differs from this, please follow the correlation method described in the employee connector README.
*Current implementation of the Employee Correlation method:*
  
  ```Powershell
    $spaltInvoke = @{
        uri    = "$($config.BaseUrl)/api/v1/object/Employee('$($account.EmployeeId)')"
        Method = 'GET'
    }
    $employee = Invoke-Ultimo-UserRestMethod @spaltInvoke -Verbose:$false
  ```
  <br>
- The EmployeeId of a user account cannot be updated.

- To determine whether a user should be updated, we created a custom comparison object because of the differences between the request and the response body of the API. Please keep this in mind when adding extra properties to the account object, and ensure that any added properties are also included in the comparison object. This applies to both the create.ps1 and update.ps1 scripts.
  ```Powershell
        $previousAccount = [PSCustomObject]@{
            ExternalAccountName = $user.ExternalAccountName
            UserDescription     = $user.Description
        }
  ```
- The connector does not support having the exact same name for both a configuration group and an authorization groups.
- The Configuration mapping file should map the "HelloID" Job Title or possibly any other value to an Ultimo Configuration Group. *(The current implementation uses the primary contract (Title.Code))*
- The connector manages two types of permissions. First, there is a Configuration Group, which can be viewed as a user type or template. In addition to the Configuration Group, you can also add one or more Authorization groups.
  - **Configuration Groups** are managed directly in the `create.ps1` and `update.ps1` scripts since a configuration group is mandatory when creating a new User account. You can only apply a single configuration at a time.
  - **Authorization groups** are managed with entitlements.
- Ultimo does have a retention period for active and deactivated accounts. Normally, you cannot deactivate an account that was recently activated; the cooldown period is typically 10 days. This cannot be resolved within the connector itself, so to prevent errors, you should keep this in mind while configuring the business rules.



#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the `configuration` by setting the checkbox `UpdatePersonOnCorrelate` to the value of `true`.

> Be aware that this might have unexpected implications.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
