address 0x1 {
/// This module holds transactions that can be used to administer accounts in the Diem Framework.
module AccountAdministrationScripts {
    use 0x1::DiemAccount;
    use 0x1::RecoveryAddress;
    use 0x1::SharedEd25519PublicKey;
    use 0x1::DualAttestation;

    /// # Summary
    /// Adds a zero `Currency` balance to the sending `account`. This will enable `account` to
    /// send, receive, and hold `Diem::Diem<Currency>` coins. This transaction can be
    /// successfully sent by any account that is allowed to hold balances
    /// (e.g., VASP, Designated Dealer).
    ///
    /// # Technical Description
    /// After the successful execution of this transaction the sending account will have a
    /// `DiemAccount::Balance<Currency>` resource with zero balance published under it. Only
    /// accounts that can hold balances can send this transaction, the sending account cannot
    /// already have a `DiemAccount::Balance<Currency>` published under it.
    ///
    /// # Parameters
    /// | Name       | Type     | Description                                                                                                                                         |
    /// | ------     | ------   | -------------                                                                                                                                       |
    /// | `Currency` | Type     | The Move type for the `Currency` being added to the sending account of the transaction. `Currency` must be an already-registered currency on-chain. |
    /// | `account`  | `signer` | The signer of the sending account of the transaction.                                                                                               |
    ///
    /// # Common Abort Conditions
    /// | Error Category              | Error Reason                             | Description                                                                |
    /// | ----------------            | --------------                           | -------------                                                              |
    /// | `Errors::NOT_PUBLISHED`     | `Diem::ECURRENCY_INFO`                  | The `Currency` is not a registered currency on-chain.                      |
    /// | `Errors::INVALID_ARGUMENT`  | `DiemAccount::EROLE_CANT_STORE_BALANCE` | The sending `account`'s role does not permit balances.                     |
    /// | `Errors::ALREADY_PUBLISHED` | `DiemAccount::EADD_EXISTING_CURRENCY`   | A balance for `Currency` is already published under the sending `account`. |
    ///
    /// # Related Scripts
    /// * `AccountCreationScripts::create_child_vasp_account`
    /// * `AccountCreationScripts::create_parent_vasp_account`
    /// * `PaymentScripts::peer_to_peer_with_metadata`

    public(script) fun add_currency_to_account<Currency: store>(account: signer) {
        DiemAccount::add_currency<Currency>(&account);
    }

    /// # Summary
    /// Stores the sending accounts ability to rotate its authentication key with a designated recovery
    /// account. Both the sending and recovery accounts need to belong to the same VASP and
    /// both be VASP accounts. After this transaction both the sending account and the
    /// specified recovery account can rotate the sender account's authentication key.
    ///
    /// # Technical Description
    /// Adds the `DiemAccount::KeyRotationCapability` for the sending account
    /// (`to_recover_account`) to the `RecoveryAddress::RecoveryAddress` resource under
    /// `recovery_address`. After this transaction has been executed successfully the account at
    /// `recovery_address` and the `to_recover_account` may rotate the authentication key of
    /// `to_recover_account` (the sender of this transaction).
    ///
    /// The sending account of this transaction (`to_recover_account`) must not have previously given away its unique key
    /// rotation capability, and must be a VASP account. The account at `recovery_address`
    /// must also be a VASP account belonging to the same VASP as the `to_recover_account`.
    /// Additionally the account at `recovery_address` must have already initialized itself as
    /// a recovery account address using the `AccountAdministrationScripts::create_recovery_address` transaction script.
    ///
    /// The sending account's (`to_recover_account`) key rotation capability is
    /// removed in this transaction and stored in the `RecoveryAddress::RecoveryAddress`
    /// resource stored under the account at `recovery_address`.
    ///
    /// # Parameters
    /// | Name                 | Type      | Description                                                                                               |
    /// | ------               | ------    | -------------                                                                                             |
    /// | `to_recover_account` | `signer`  | The signer of the sending account of this transaction.                                                    |
    /// | `recovery_address`   | `address` | The account address where the `to_recover_account`'s `DiemAccount::KeyRotationCapability` will be stored. |
    ///
    /// # Common Abort Conditions
    /// | Error Category             | Error Reason                                              | Description                                                                                       |
    /// | ----------------           | --------------                                            | -------------                                                                                     |
    /// | `Errors::INVALID_STATE`    | `DiemAccount::EKEY_ROTATION_CAPABILITY_ALREADY_EXTRACTED` | `to_recover_account` has already delegated/extracted its `DiemAccount::KeyRotationCapability`.    |
    /// | `Errors::NOT_PUBLISHED`    | `RecoveryAddress::ERECOVERY_ADDRESS`                      | `recovery_address` does not have a `RecoveryAddress` resource published under it.                 |
    /// | `Errors::INVALID_ARGUMENT` | `RecoveryAddress::EINVALID_KEY_ROTATION_DELEGATION`       | `to_recover_account` and `recovery_address` do not belong to the same VASP.                       |
    /// | `Errors::LIMIT_EXCEEDED`   | ` RecoveryAddress::EMAX_KEYS_REGISTERED`                  | `RecoveryAddress::MAX_REGISTERED_KEYS` have already been registered with this `recovery_address`. |
    ///
    /// # Related Scripts
    /// * `AccountAdministrationScripts::create_recovery_address`
    /// * `AccountAdministrationScripts::rotate_authentication_key_with_recovery_address`

    public(script) fun add_recovery_rotation_capability(to_recover_account: signer, recovery_address: address) {
        RecoveryAddress::add_rotation_capability(
            DiemAccount::extract_key_rotation_capability(&to_recover_account), recovery_address
        )
    }

    /// # Summary
    /// Rotates the authentication key of the sending account to the newly-specified ed25519 public key and
    /// publishes a new shared authentication key derived from that public key under the sender's account.
    /// Any account can send this transaction.
    ///
    /// # Technical Description
    /// Rotates the authentication key of the sending account to the
    /// [authentication key derived from `public_key`](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys)
    /// and publishes a `SharedEd25519PublicKey::SharedEd25519PublicKey` resource
    /// containing the 32-byte ed25519 `public_key` and the `DiemAccount::KeyRotationCapability` for
    /// `account` under `account`.
    ///
    /// # Parameters
    /// | Name         | Type         | Description                                                                                        |
    /// | ------       | ------       | -------------                                                                                      |
    /// | `account`    | `signer`     | The signer of the sending account of the transaction.                                              |
    /// | `public_key` | `vector<u8>` | A valid 32-byte Ed25519 public key for `account`'s authentication key to be rotated to and stored. |
    ///
    /// # Common Abort Conditions
    /// | Error Category              | Error Reason                                               | Description                                                                                         |
    /// | ----------------            | --------------                                             | -------------                                                                                       |
    /// | `Errors::INVALID_STATE`     | `DiemAccount::EKEY_ROTATION_CAPABILITY_ALREADY_EXTRACTED` | `account` has already delegated/extracted its `DiemAccount::KeyRotationCapability` resource.       |
    /// | `Errors::ALREADY_PUBLISHED` | `SharedEd25519PublicKey::ESHARED_KEY`                      | The `SharedEd25519PublicKey::SharedEd25519PublicKey` resource is already published under `account`. |
    /// | `Errors::INVALID_ARGUMENT`  | `SharedEd25519PublicKey::EMALFORMED_PUBLIC_KEY`            | `public_key` is an invalid ed25519 public key.                                                      |
    ///
    /// # Related Scripts
    /// * `AccountAdministrationScripts::rotate_shared_ed25519_public_key`

    public(script) fun publish_shared_ed25519_public_key(account: signer, public_key: vector<u8>) {
        SharedEd25519PublicKey::publish(&account, public_key)
    }

    /// # Summary
    /// Rotates the `account`'s authentication key to the supplied new authentication key. May be sent by any account.
    ///
    /// # Technical Description
    /// Rotate the `account`'s `DiemAccount::DiemAccount` `authentication_key`
    /// field to `new_key`. `new_key` must be a valid authentication key that
    /// corresponds to an ed25519 public key as described [here](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys),
    /// and `account` must not have previously delegated its `DiemAccount::KeyRotationCapability`.
    ///
    /// # Parameters
    /// | Name      | Type         | Description                                       |
    /// | ------    | ------       | -------------                                     |
    /// | `account` | `signer`     | Signer of the sending account of the transaction. |
    /// | `new_key` | `vector<u8>` | New authentication key to be used for `account`.  |
    ///
    /// # Common Abort Conditions
    /// | Error Category             | Error Reason                                              | Description                                                                         |
    /// | ----------------           | --------------                                            | -------------                                                                       |
    /// | `Errors::INVALID_STATE`    | `DiemAccount::EKEY_ROTATION_CAPABILITY_ALREADY_EXTRACTED` | `account` has already delegated/extracted its `DiemAccount::KeyRotationCapability`. |
    /// | `Errors::INVALID_ARGUMENT` | `DiemAccount::EMALFORMED_AUTHENTICATION_KEY`              | `new_key` was an invalid length.                                                    |
    ///
    /// # Related Scripts
    /// * `AccountAdministrationScripts::rotate_authentication_key_with_nonce`
    /// * `AccountAdministrationScripts::rotate_authentication_key_with_nonce_admin`
    /// * `AccountAdministrationScripts::rotate_authentication_key_with_recovery_address`

    public(script) fun rotate_authentication_key(account: signer, new_key: vector<u8>) {
        let key_rotation_capability = DiemAccount::extract_key_rotation_capability(&account);
        DiemAccount::rotate_authentication_key(&key_rotation_capability, new_key);
        DiemAccount::restore_key_rotation_capability(key_rotation_capability);
    }

    /// # Summary
    /// Rotates the authentication key of a specified account that is part of a recovery address to a
    /// new authentication key. Only used for accounts that are part of a recovery address (see
    /// `AccountAdministrationScripts::add_recovery_rotation_capability` for account restrictions).
    ///
    /// # Technical Description
    /// Rotates the authentication key of the `to_recover` account to `new_key` using the
    /// `DiemAccount::KeyRotationCapability` stored in the `RecoveryAddress::RecoveryAddress` resource
    /// published under `recovery_address`. `new_key` must be a valide authentication key as described
    /// [here](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys).
    /// This transaction can be sent either by the `to_recover` account, or by the account where the
    /// `RecoveryAddress::RecoveryAddress` resource is published that contains `to_recover`'s `DiemAccount::KeyRotationCapability`.
    ///
    /// # Parameters
    /// | Name               | Type         | Description                                                                                                                   |
    /// | ------             | ------       | -------------                                                                                                                 |
    /// | `account`          | `signer`     | Signer of the sending account of the transaction.                                                                             |
    /// | `recovery_address` | `address`    | Address where `RecoveryAddress::RecoveryAddress` that holds `to_recover`'s `DiemAccount::KeyRotationCapability` is published. |
    /// | `to_recover`       | `address`    | The address of the account whose authentication key will be updated.                                                          |
    /// | `new_key`          | `vector<u8>` | New authentication key to be used for the account at the `to_recover` address.                                                |
    ///
    /// # Common Abort Conditions
    /// | Error Category             | Error Reason                                 | Description                                                                                                                                         |
    /// | ----------------           | --------------                               | -------------                                                                                                                                       |
    /// | `Errors::NOT_PUBLISHED`    | `RecoveryAddress::ERECOVERY_ADDRESS`         | `recovery_address` does not have a `RecoveryAddress::RecoveryAddress` resource published under it.                                                  |
    /// | `Errors::INVALID_ARGUMENT` | `RecoveryAddress::ECANNOT_ROTATE_KEY`        | The address of `account` is not `recovery_address` or `to_recover`.                                                                                 |
    /// | `Errors::INVALID_ARGUMENT` | `RecoveryAddress::EACCOUNT_NOT_RECOVERABLE`  | `to_recover`'s `DiemAccount::KeyRotationCapability`  is not in the `RecoveryAddress::RecoveryAddress`  resource published under `recovery_address`. |
    /// | `Errors::INVALID_ARGUMENT` | `DiemAccount::EMALFORMED_AUTHENTICATION_KEY` | `new_key` was an invalid length.                                                                                                                    |
    ///
    /// # Related Scripts
    /// * `AccountAdministrationScripts::rotate_authentication_key`
    /// * `AccountAdministrationScripts::rotate_authentication_key_with_nonce`
    /// * `AccountAdministrationScripts::rotate_authentication_key_with_nonce_admin`

    public(script) fun rotate_authentication_key_with_recovery_address(
            account: signer,
            recovery_address: address,
            to_recover: address,
            new_key: vector<u8>
            ) {
        RecoveryAddress::rotate_authentication_key(&account, recovery_address, to_recover, new_key)
    }

    /// # Summary
    /// Updates the url used for off-chain communication, and the public key used to verify dual
    /// attestation on-chain. Transaction can be sent by any account that has dual attestation
    /// information published under it. In practice the only such accounts are Designated Dealers and
    /// Parent VASPs.
    ///
    /// # Technical Description
    /// Updates the `base_url` and `compliance_public_key` fields of the `DualAttestation::Credential`
    /// resource published under `account`. The `new_key` must be a valid ed25519 public key.
    ///
    /// # Events
    /// Successful execution of this transaction emits two events:
    /// * A `DualAttestation::ComplianceKeyRotationEvent` containing the new compliance public key, and
    /// the blockchain time at which the key was updated emitted on the `DualAttestation::Credential`
    /// `compliance_key_rotation_events` handle published under `account`; and
    /// * A `DualAttestation::BaseUrlRotationEvent` containing the new base url to be used for
    /// off-chain communication, and the blockchain time at which the url was updated emitted on the
    /// `DualAttestation::Credential` `base_url_rotation_events` handle published under `account`.
    ///
    /// # Parameters
    /// | Name      | Type         | Description                                                               |
    /// | ------    | ------       | -------------                                                             |
    /// | `account` | `signer`     | Signer of the sending account of the transaction.                         |
    /// | `new_url` | `vector<u8>` | ASCII-encoded url to be used for off-chain communication with `account`.  |
    /// | `new_key` | `vector<u8>` | New ed25519 public key to be used for on-chain dual attestation checking. |
    ///
    /// # Common Abort Conditions
    /// | Error Category             | Error Reason                           | Description                                                                |
    /// | ----------------           | --------------                         | -------------                                                              |
    /// | `Errors::NOT_PUBLISHED`    | `DualAttestation::ECREDENTIAL`         | A `DualAttestation::Credential` resource is not published under `account`. |
    /// | `Errors::INVALID_ARGUMENT` | `DualAttestation::EINVALID_PUBLIC_KEY` | `new_key` is not a valid ed25519 public key.                               |
    ///
    /// # Related Scripts
    /// * `AccountCreationScripts::create_parent_vasp_account`
    /// * `AccountCreationScripts::create_designated_dealer`
    /// * `AccountAdministrationScripts::rotate_dual_attestation_info`

    public(script) fun rotate_dual_attestation_info(account: signer, new_url: vector<u8>, new_key: vector<u8>) {
        DualAttestation::rotate_base_url(&account, new_url);
        DualAttestation::rotate_compliance_public_key(&account, new_key)
    }

    /// # Summary
    /// Rotates the authentication key in a `SharedEd25519PublicKey`. This transaction can be sent by
    /// any account that has previously published a shared ed25519 public key using
    /// `AccountAdministrationScripts::publish_shared_ed25519_public_key`.
    ///
    /// # Technical Description
    /// `public_key` must be a valid ed25519 public key.  This transaction first rotates the public key stored in `account`'s
    /// `SharedEd25519PublicKey::SharedEd25519PublicKey` resource to `public_key`, after which it
    /// rotates the `account`'s authentication key to the new authentication key derived from `public_key` as defined
    /// [here](https://developers.diem.com/docs/core/accounts/#addresses-authentication-keys-and-cryptographic-keys)
    /// using the `DiemAccount::KeyRotationCapability` stored in `account`'s `SharedEd25519PublicKey::SharedEd25519PublicKey`.
    ///
    /// # Parameters
    /// | Name         | Type         | Description                                           |
    /// | ------       | ------       | -------------                                         |
    /// | `account`    | `signer`     | The signer of the sending account of the transaction. |
    /// | `public_key` | `vector<u8>` | 32-byte Ed25519 public key.                           |
    ///
    /// # Common Abort Conditions
    /// | Error Category             | Error Reason                                    | Description                                                                                   |
    /// | ----------------           | --------------                                  | -------------                                                                                 |
    /// | `Errors::NOT_PUBLISHED`    | `SharedEd25519PublicKey::ESHARED_KEY`           | A `SharedEd25519PublicKey::SharedEd25519PublicKey` resource is not published under `account`. |
    /// | `Errors::INVALID_ARGUMENT` | `SharedEd25519PublicKey::EMALFORMED_PUBLIC_KEY` | `public_key` is an invalid ed25519 public key.                                                |
    ///
    /// # Related Scripts
    /// * `AccountAdministrationScripts::publish_shared_ed25519_public_key`

    public(script) fun rotate_shared_ed25519_public_key(account: signer, public_key: vector<u8>) {
        SharedEd25519PublicKey::rotate_key(&account, public_key)
    }

    /// # Summary
    /// Initializes the sending account as a recovery address that may be used by
    /// other accounts belonging to the same VASP as `account`.
    /// The sending account must be a VASP account, and can be either a child or parent VASP account.
    /// Multiple recovery addresses can exist for a single VASP, but accounts in
    /// each must be disjoint.
    ///
    /// # Technical Description
    /// Publishes a `RecoveryAddress::RecoveryAddress` resource under `account`. It then
    /// extracts the `DiemAccount::KeyRotationCapability` for `account` and adds
    /// it to the resource. After the successful execution of this transaction
    /// other accounts may add their key rotation to this resource so that `account`
    /// may be used as a recovery account for those accounts.
    ///
    /// # Parameters
    /// | Name      | Type     | Description                                           |
    /// | ------    | ------   | -------------                                         |
    /// | `account` | `signer` | The signer of the sending account of the transaction. |
    ///
    /// # Common Abort Conditions
    /// | Error Category              | Error Reason                                               | Description                                                                                   |
    /// | ----------------            | --------------                                             | -------------                                                                                 |
    /// | `Errors::INVALID_STATE`     | `DiemAccount::EKEY_ROTATION_CAPABILITY_ALREADY_EXTRACTED` | `account` has already delegated/extracted its `DiemAccount::KeyRotationCapability`.          |
    /// | `Errors::INVALID_ARGUMENT`  | `RecoveryAddress::ENOT_A_VASP`                             | `account` is not a VASP account.                                                              |
    /// | `Errors::INVALID_ARGUMENT`  | `RecoveryAddress::EKEY_ROTATION_DEPENDENCY_CYCLE`          | A key rotation recovery cycle would be created by adding `account`'s key rotation capability. |
    /// | `Errors::ALREADY_PUBLISHED` | `RecoveryAddress::ERECOVERY_ADDRESS`                       | A `RecoveryAddress::RecoveryAddress` resource has already been published under `account`.     |
    ///
    /// # Related Scripts
    /// * `Script::add_recovery_rotation_capability`
    /// * `Script::rotate_authentication_key_with_recovery_address`

    public(script) fun create_recovery_address(account: signer) {
        RecoveryAddress::publish(&account, DiemAccount::extract_key_rotation_capability(&account))
    }
}
}
