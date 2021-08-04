# Standard Library

This is modified version of Diem's [Move Standard Library](https://github.com/diem/diem/tree/main/language/diem-framework).

Pontem Network Move Standard library.

## Build

Clone current repository and use [dove](https://github.com/pontem-network/move-tools#dove) to build:

```sh
git clone git@github.com:pontem-network/move-stdlib.git
cd move-stdlib
dove build
```

See built modules:

```sh
ls -la ./target/modules
```

## Restricted

Current version contains restricted functions. It's so because of access to tc_signer and dr_signer for any developer.

Current list of restricted functions:

* AccountFreezing.move:
  * freeze_account
  * unfreeze_account
* AccountLimits.move:
  * publish_window
  * update_limits_definition
  * update_window_info
* DesignatedDealer:
  * tiered_mint
* Diem.move:
  * publish_burn_capability
  * update_xdx_exchange_rate
* DiemAccount.move:
  * create_validator_account
  * create_validator_operator_account
  * tiered_mint
* DiemConfig.move:
  * disable_reconfiguration
  * enable_reconfiguration
  * reconfigure
* DiemSystem.move:
  * add_validator
  * remove_validator
* DiemTransactionPublishingOption.move:
  * set_open_script
  * set_open_module
  * halt_all_transactions
  * resume_transactions
* DiemVersion.move:
  * set
* DiemVMConfig.move:
  * set_gas_constants
* Roles.move:
  * new_validator_role
  * new_validator_operator_role
* ValidatorConfig.move:
  * publish
* ValidatorOperatorConfig.move:
  * publish

## LICENSE

See [LICENSE](./LICENSE)

