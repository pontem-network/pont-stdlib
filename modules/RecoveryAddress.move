address 0x1 {

/// This module defines an account recovery mechanism that can be used by VASPs.
module RecoveryAddress {
    use 0x1::Errors;
    use 0x1::DiemAccount::{Self, KeyRotationCapability};
    use 0x1::Signer;
    use 0x1::VASP;
    use 0x1::Vector;

    /// A resource that holds the `KeyRotationCapability`s for several accounts belonging to the
    /// same VASP. A VASP account that delegates its `KeyRotationCapability` to
    /// but also allows the account that stores the `RecoveryAddress` resource to rotate its
    /// authentication key.
    /// This is useful as an account recovery mechanism: VASP accounts can all delegate their
    /// rotation capabilities to a single `RecoveryAddress` resource stored under address A.
    /// The authentication key for A can be "buried in the mountain" and dug up only if the need to
    /// recover one of accounts in `rotation_caps` arises.
    struct RecoveryAddress has key {
        rotation_caps: vector<KeyRotationCapability>
    }

    /// Only VASPs can create a recovery address
    const ENOT_A_VASP: u64 = 0;
    /// A cycle would have been created would be created
    const EKEY_ROTATION_DEPENDENCY_CYCLE: u64 = 1;
    /// The signer doesn't have the appropriate privileges to rotate the account's key
    const ECANNOT_ROTATE_KEY: u64 = 2;
    /// Only accounts belonging to the same VASP can delegate their key rotation capability
    const EINVALID_KEY_ROTATION_DELEGATION: u64 = 3;
    /// The account address couldn't be found in the account recovery resource
    const EACCOUNT_NOT_RECOVERABLE: u64 = 4;
    /// A `RecoveryAddress` resource was in an unexpected state
    const ERECOVERY_ADDRESS: u64 = 5;
    /// The maximum allowed number of keys have been registered with this recovery address.
    const EMAX_KEYS_REGISTERED: u64 = 6;

    /// The maximum number of keys that can be registered with a single recovery address.
    const MAX_REGISTERED_KEYS: u64 = 256;

    /// Extract the `KeyRotationCapability` for `recovery_account` and publish it in a
    /// `RecoveryAddress` resource under  `recovery_account`.
    /// Aborts if `recovery_account` has delegated its `KeyRotationCapability`, already has a
    /// `RecoveryAddress` resource, or is not a VASP.
    public fun publish(recovery_account: &signer, rotation_cap: KeyRotationCapability) {
        let addr = Signer::address_of(recovery_account);
        // Only VASPs can create a recovery address
        assert(VASP::is_vasp(addr), Errors::invalid_argument(ENOT_A_VASP));
        // put the rotation capability for the recovery account itself in `rotation_caps`. This
        // ensures two things:
        // (1) It's not possible to get into a "recovery cycle" where A is the recovery account for
        //     B and B is the recovery account for A
        // (2) rotation_caps is always nonempty
        assert(
            *DiemAccount::key_rotation_capability_address(&rotation_cap) == addr,
            Errors::invalid_argument(EKEY_ROTATION_DEPENDENCY_CYCLE)
        );
        assert(!exists<RecoveryAddress>(addr), Errors::already_published(ERECOVERY_ADDRESS));
        move_to(
            recovery_account,
            RecoveryAddress { rotation_caps: Vector::singleton(rotation_cap) }
        )
    }

    /// Rotate the authentication key of `to_recover` to `new_key`. Can be invoked by either
    /// `recovery_address` or `to_recover`.
    /// Aborts if `recovery_address` does not have the `KeyRotationCapability` for `to_recover`.
    public fun rotate_authentication_key(
        account: &signer,
        recovery_address: address,
        to_recover: address,
        new_key: vector<u8>
    ) acquires RecoveryAddress {
        // Check that `recovery_address` has a `RecoveryAddress` resource
        assert(exists<RecoveryAddress>(recovery_address), Errors::not_published(ERECOVERY_ADDRESS));
        let sender = Signer::address_of(account);
        assert(
            // The original owner of a key rotation capability can rotate its own key
            sender == to_recover ||
            // The owner of the `RecoveryAddress` resource can rotate any key
            sender == recovery_address,
            Errors::invalid_argument(ECANNOT_ROTATE_KEY)
        );

        let caps = &borrow_global<RecoveryAddress>(recovery_address).rotation_caps;
        let i = 0;
        let len = Vector::length(caps);
        while ( {
            (i < len)
        })
        {
            let cap = Vector::borrow(caps, i);
            if (DiemAccount::key_rotation_capability_address(cap) == &to_recover) {
                DiemAccount::rotate_authentication_key(cap, new_key);
                return
            };
            i = i + 1
        };
        // Couldn't find `to_recover` in the account recovery resource; abort
        abort Errors::invalid_argument(EACCOUNT_NOT_RECOVERABLE)
    }

    /// Add `to_recover` to the `RecoveryAddress` resource under `recovery_address`.
    /// Aborts if `to_recover.address` and `recovery_address` belong to different VASPs, or if
    /// `recovery_address` does not have a `RecoveryAddress` resource.
    public fun add_rotation_capability(to_recover: KeyRotationCapability, recovery_address: address)
    acquires RecoveryAddress {
        // Check that `recovery_address` has a `RecoveryAddress` resource
        assert(exists<RecoveryAddress>(recovery_address), Errors::not_published(ERECOVERY_ADDRESS));
        // Only accept the rotation capability if both accounts belong to the same VASP
        let to_recover_address = *DiemAccount::key_rotation_capability_address(&to_recover);
        assert(
            VASP::is_same_vasp(recovery_address, to_recover_address),
            Errors::invalid_argument(EINVALID_KEY_ROTATION_DELEGATION)
        );

        let recovery_caps = &mut borrow_global_mut<RecoveryAddress>(recovery_address).rotation_caps;
        assert(
            Vector::length(recovery_caps) < MAX_REGISTERED_KEYS,
            Errors::limit_exceeded(EMAX_KEYS_REGISTERED)
        );

        Vector::push_back(recovery_caps, to_recover);
    }
}
}
