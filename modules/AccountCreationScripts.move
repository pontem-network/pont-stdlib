address 0x1 {
module AccountCreationScripts {
    use 0x1::DiemAccount;

    /// # Summary
    /// Creates a Child VASP account with its parent being the sending account of the transaction.
    /// The sender of the transaction must be a Parent VASP account.
    ///
    /// # Technical Description
    /// Creates a `ChildVASP` account for the sender `parent_vasp` at `child_address` with a balance of
    /// `child_initial_balance` in `CoinType` and an initial authentication key of
    /// `auth_key_prefix | child_address`. Authentication key prefixes, and how to construct them from an ed25519 public key is described
    /// [here](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys).
    ///
    /// If `add_all_currencies` is true, the child address will have a zero balance in all available
    /// currencies in the system.
    ///
    /// The new account will be a child account of the transaction sender, which must be a
    /// Parent VASP account. The child account will be recorded against the limit of
    /// child accounts of the creating Parent VASP account.
    ///
    /// # Events
    /// Successful execution will emit:
    /// * A `DiemAccount::CreateAccountEvent` with the `created` field being `child_address`,
    /// and the `rold_id` field being `Roles::CHILD_VASP_ROLE_ID`. This is emitted on the
    /// `DiemAccount::AccountOperationsCapability` `creation_events` handle.
    ///
    /// Successful execution with a `child_initial_balance` greater than zero will additionaly emit:
    /// * A `DiemAccount::SentPaymentEvent` with the `payee` field being `child_address`.
    /// This is emitted on the Parent VASP's `DiemAccount::DiemAccount` `sent_events` handle.
    /// * A `DiemAccount::ReceivedPaymentEvent` with the  `payer` field being the Parent VASP's address.
    /// This is emitted on the new Child VASPS's `DiemAccount::DiemAccount` `received_events` handle.
    ///
    /// # Parameters
    /// | Name                    | Type         | Description                                                                                                                                 |
    /// | ------                  | ------       | -------------                                                                                                                               |
    /// | `CoinType`              | Type         | The Move type for the `CoinType` that the child account should be created with. `CoinType` must be an already-registered currency on-chain. |
    /// | `parent_vasp`           | `signer`     | The reference of the sending account. Must be a Parent VASP account.                                                                        |
    /// | `child_address`         | `address`    | Address of the to-be-created Child VASP account.                                                                                            |
    /// | `auth_key_prefix`       | `vector<u8>` | The authentication key prefix that will be used initially for the newly created account.                                                    |
    /// | `add_all_currencies`    | `bool`       | Whether to publish balance resources for all known currencies when the account is created.                                                  |
    /// | `child_initial_balance` | `u64`        | The initial balance in `CoinType` to give the child account when it's created.                                                              |
    ///
    /// # Common Abort Conditions
    /// | Error Category              | Error Reason                                             | Description                                                                              |
    /// | ----------------            | --------------                                           | -------------                                                                            |
    /// | `Errors::INVALID_ARGUMENT`  | `DiemAccount::EMALFORMED_AUTHENTICATION_KEY`            | The `auth_key_prefix` was not of length 32.                                              |
    /// | `Errors::REQUIRES_ROLE`     | `Roles::EPARENT_VASP`                                    | The sending account wasn't a Parent VASP account.                                        |
    /// | `Errors::ALREADY_PUBLISHED` | `Roles::EROLE_ID`                                        | The `child_address` address is already taken.                                            |
    /// | `Errors::LIMIT_EXCEEDED`    | `VASP::ETOO_MANY_CHILDREN`                               | The sending account has reached the maximum number of allowed child accounts.            |
    /// | `Errors::NOT_PUBLISHED`     | `Diem::ECURRENCY_INFO`                                  | The `CoinType` is not a registered currency on-chain.                                    |
    /// | `Errors::INVALID_STATE`     | `DiemAccount::EWITHDRAWAL_CAPABILITY_ALREADY_EXTRACTED` | The withdrawal capability for the sending account has already been extracted.            |
    /// | `Errors::NOT_PUBLISHED`     | `DiemAccount::EPAYER_DOESNT_HOLD_CURRENCY`              | The sending account doesn't have a balance in `CoinType`.                                |
    /// | `Errors::LIMIT_EXCEEDED`    | `DiemAccount::EINSUFFICIENT_BALANCE`                    | The sending account doesn't have at least `child_initial_balance` of `CoinType` balance. |
    /// | `Errors::INVALID_ARGUMENT`  | `DiemAccount::ECANNOT_CREATE_AT_VM_RESERVED`            | The `child_address` is the reserved address 0x0.                                         |
    ///
    /// # Related Scripts
    /// * `AccountCreationScripts::create_parent_vasp_account`
    /// * `AccountAdministrationScripts::add_currency_to_account`
    /// * `AccountAdministrationScripts::rotate_authentication_key`
    /// * `AccountAdministrationScripts::add_recovery_rotation_capability`
    /// * `AccountAdministrationScripts::create_recovery_address`

    public(script) fun create_child_vasp_account<CoinType: store>(
        parent_vasp: signer,
        child_address: address,
        auth_key_prefix: vector<u8>,
        add_all_currencies: bool,
        child_initial_balance: u64
    ) {
        DiemAccount::create_child_vasp_account<CoinType>(
            &parent_vasp,
            child_address,
            auth_key_prefix,
            add_all_currencies,
        );
        // Give the newly created child `child_initial_balance` coins
        if (child_initial_balance > 0) {
            let vasp_withdrawal_cap = DiemAccount::extract_withdraw_capability(&parent_vasp);
            DiemAccount::pay_from<CoinType>(
                &vasp_withdrawal_cap, child_address, child_initial_balance, x"", x""
            );
            DiemAccount::restore_withdraw_capability(vasp_withdrawal_cap);
        };
    }

    /// # Summary
    /// Creates a Parent VASP account with the specified human name. Must be called by the Treasury Compliance account.
    ///
    /// # Technical Description
    /// Creates an account with the Parent VASP role at `address` with authentication key
    /// `auth_key_prefix` | `new_account_address` and a 0 balance of type `CoinType`. If
    /// `add_all_currencies` is true, 0 balances for all available currencies in the system will
    /// also be added. This can only be invoked by an TreasuryCompliance account.
    /// Authentication keys, prefixes, and how to construct them from an ed25519 public key are described
    /// [here](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys).
    ///
    /// # Events
    /// Successful execution will emit:
    /// * A `DiemAccount::CreateAccountEvent` with the `created` field being `new_account_address`,
    /// and the `rold_id` field being `Roles::PARENT_VASP_ROLE_ID`. This is emitted on the
    /// `DiemAccount::AccountOperationsCapability` `creation_events` handle.
    ///
    /// # Parameters
    /// | Name                  | Type         | Description                                                                                                                                                    |
    /// | ------                | ------       | -------------                                                                                                                                                  |
    /// | `CoinType`            | Type         | The Move type for the `CoinType` currency that the Parent VASP account should be initialized with. `CoinType` must be an already-registered currency on-chain. |
    /// | `tc_account`          | `signer`     | The signer of the sending account of this transaction. Must be the Treasury Compliance account.                                                                |
    /// | `new_account_address` | `address`    | Address of the to-be-created Parent VASP account.                                                                                                              |
    /// | `auth_key_prefix`     | `vector<u8>` | The authentication key prefix that will be used initially for the newly created account.                                                                       |
    /// | `human_name`          | `vector<u8>` | ASCII-encoded human name for the Parent VASP.                                                                                                                  |
    /// | `add_all_currencies`  | `bool`       | Whether to publish balance resources for all known currencies when the account is created.                                                                     |
    ///
    /// # Common Abort Conditions
    /// | Error Category              | Error Reason                            | Description                                                                                |
    /// | ----------------            | --------------                          | -------------                                                                              |
    /// | `Errors::REQUIRES_ADDRESS`  | `CoreAddresses::ETREASURY_COMPLIANCE`   | The sending account is not the Treasury Compliance account.                                |
    /// | `Errors::REQUIRES_ROLE`     | `Roles::ETREASURY_COMPLIANCE`           | The sending account is not the Treasury Compliance account.                                |
    /// | `Errors::NOT_PUBLISHED`     | `Diem::ECURRENCY_INFO`                 | The `CoinType` is not a registered currency on-chain.                                      |
    /// | `Errors::ALREADY_PUBLISHED` | `Roles::EROLE_ID`                       | The `new_account_address` address is already taken.                                        |
    ///
    /// # Related Scripts
    /// * `AccountCreationScripts::create_child_vasp_account`
    /// * `AccountAdministrationScripts::add_currency_to_account`
    /// * `AccountAdministrationScripts::rotate_authentication_key`
    /// * `AccountAdministrationScripts::add_recovery_rotation_capability`
    /// * `AccountAdministrationScripts::create_recovery_address`
    /// * `AccountAdministrationScripts::rotate_dual_attestation_info`

    public(script) fun create_parent_vasp_account<CoinType: store>(
        tc_account: signer,
        new_account_address: address,
        auth_key_prefix: vector<u8>,
        human_name: vector<u8>,
        add_all_currencies: bool
    ) {
        DiemAccount::create_parent_vasp_account<CoinType>(
            &tc_account,
            new_account_address,
            auth_key_prefix,
            human_name,
            add_all_currencies
        );
    }

    /// # Summary
    /// Creates a Designated Dealer account with the provided information, and initializes it with
    /// default mint tiers. The transaction can only be sent by the Treasury Compliance account.
    ///
    /// # Technical Description
    /// Creates an account with the Designated Dealer role at `addr` with authentication key
    /// `auth_key_prefix` | `addr` and a 0 balance of type `Currency`. If `add_all_currencies` is true,
    /// 0 balances for all available currencies in the system will also be added. This can only be
    /// invoked by an account with the TreasuryCompliance role.
    /// Authentication keys, prefixes, and how to construct them from an ed25519 public key are described
    /// [here](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys).
    ///
    /// At the time of creation the account is also initialized with default mint tiers of (500_000,
    /// 5000_000, 50_000_000, 500_000_000), and preburn areas for each currency that is added to the
    /// account.
    ///
    /// # Events
    /// Successful execution will emit:
    /// * A `DiemAccount::CreateAccountEvent` with the `created` field being `addr`,
    /// and the `rold_id` field being `Roles::DESIGNATED_DEALER_ROLE_ID`. This is emitted on the
    /// `DiemAccount::AccountOperationsCapability` `creation_events` handle.
    ///
    /// # Parameters
    /// | Name                 | Type         | Description                                                                                                                                         |
    /// | ------               | ------       | -------------                                                                                                                                       |
    /// | `Currency`           | Type         | The Move type for the `Currency` that the Designated Dealer should be initialized with. `Currency` must be an already-registered currency on-chain. |
    /// | `tc_account`         | `signer`     | The signer of the sending account of this transaction. Must be the Treasury Compliance account.                                                     |
    /// | `addr`               | `address`    | Address of the to-be-created Designated Dealer account.                                                                                             |
    /// | `auth_key_prefix`    | `vector<u8>` | The authentication key prefix that will be used initially for the newly created account.                                                            |
    /// | `human_name`         | `vector<u8>` | ASCII-encoded human name for the Designated Dealer.                                                                                                 |
    /// | `add_all_currencies` | `bool`       | Whether to publish preburn, balance, and tier info resources for all known (SCS) currencies or just `Currency` when the account is created.         |
    ///
    ///
    /// # Common Abort Conditions
    /// | Error Category              | Error Reason                            | Description                                                                                |
    /// | ----------------            | --------------                          | -------------                                                                              |
    /// | `Errors::REQUIRES_ADDRESS`  | `CoreAddresses::ETREASURY_COMPLIANCE`   | The sending account is not the Treasury Compliance account.                                |
    /// | `Errors::REQUIRES_ROLE`     | `Roles::ETREASURY_COMPLIANCE`           | The sending account is not the Treasury Compliance account.                                |
    /// | `Errors::NOT_PUBLISHED`     | `Diem::ECURRENCY_INFO`                 | The `Currency` is not a registered currency on-chain.                                      |
    /// | `Errors::ALREADY_PUBLISHED` | `Roles::EROLE_ID`                       | The `addr` address is already taken.                                                       |
    ///
    /// # Related Scripts
    /// * `TreasuryComplianceScripts::tiered_mint`
    /// * `PaymentScripts::peer_to_peer_with_metadata`
    /// * `AccountAdministrationScripts::rotate_dual_attestation_info`

    public(script) fun create_designated_dealer<Currency: store>(
        tc_account: signer,
        addr: address,
        auth_key_prefix: vector<u8>,
        human_name: vector<u8>,
        add_all_currencies: bool,
    ) {
        DiemAccount::create_designated_dealer<Currency>(
            &tc_account,
            addr,
            auth_key_prefix,
            human_name,
            add_all_currencies
        );
    }
}
}
