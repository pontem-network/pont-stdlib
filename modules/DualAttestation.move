address 0x1 {

/// Module managing dual attestation.
module DualAttestation {
    use 0x1::CoreAddresses;
    use 0x1::Errors;
    use 0x1::PONT::PONT;
    use 0x1::BCS;
    use 0x1::Diem;
    use 0x1::Time;
    use 0x1::Roles;
    use 0x1::Signature;
    use 0x1::Signer;
    use 0x1::VASP;
    use 0x1::Vector;
    use 0x1::Event::{Self, EventHandle};

    /// This resource holds an entity's globally unique name and all of the metadata it needs to
    /// participate in off-chain protocols.
    struct Credential has key {
        /// The human readable name of this entity. Immutable.
        human_name: vector<u8>,
        /// The base_url holds the URL to be used for off-chain communication. This contains the
        /// entire URL (e.g. https://...). Mutable.
        base_url: vector<u8>,
        /// 32 byte Ed25519 public key whose counterpart must be used to sign
        /// (1) the payment metadata for on-chain transactions that require dual attestation (e.g.,
        ///     transactions subject to the travel rule)
        /// (2) information exchanged in the off-chain protocols (e.g., KYC info in the travel rule
        ///     protocol)
        /// Note that this is different than `authentication_key` used in DiemAccount, which is
        /// a hash of a public key + signature scheme identifier, not a public key. Mutable.
        compliance_public_key: vector<u8>,
        /// Expiration date in microseconds from unix epoch. For V1, it is always set to
        /// U64_MAX. Mutable, but only by DiemRoot.
        expiration_date: u64,
        /// Event handle for `compliance_public_key` rotation events. Emitted
        /// every time this `compliance_public_key` is rotated.
        compliance_key_rotation_events: EventHandle<ComplianceKeyRotationEvent>,
        /// Event handle for `base_url` rotation events. Emitted every time this `base_url` is rotated.
        base_url_rotation_events: EventHandle<BaseUrlRotationEvent>,
    }

    /// Struct to store the limit on-chain
    struct Limit has key {
        micro_xdx_limit: u64,
    }

    /// The message sent whenever the compliance public key for a `DualAttestation` resource is rotated.
    struct ComplianceKeyRotationEvent has drop, store {
        /// The new `compliance_public_key` that is being used for dual attestation checking.
        new_compliance_public_key: vector<u8>,
        /// The time at which the `compliance_public_key` was rotated
        time_rotated_seconds: u64,
    }

    /// The message sent whenever the base url for a `DualAttestation` resource is rotated.
    struct BaseUrlRotationEvent has drop, store {
        /// The new `base_url` that is being used for dual attestation checking
        new_base_url: vector<u8>,
        /// The time at which the `base_url` was rotated
        time_rotated_seconds: u64,
    }

    const MAX_U64: u128 = 18446744073709551615;

    // Error codes
    /// A credential is not or already published.
    const ECREDENTIAL: u64 = 0;
    /// A limit is not or already published.
    const ELIMIT: u64 = 1;
    /// Cannot parse this as an ed25519 public key
    const EINVALID_PUBLIC_KEY: u64 = 2;
    /// Cannot parse this as an ed25519 signature (e.g., != 64 bytes)
    const EMALFORMED_METADATA_SIGNATURE: u64 = 3;
    /// Signature does not match message and public key
    const EINVALID_METADATA_SIGNATURE: u64 = 4;
    /// The recipient of a dual attestation payment needs to set a compliance public key
    const EPAYEE_COMPLIANCE_KEY_NOT_SET: u64 = 5;
    /// The recipient of a dual attestation payment needs to set a base URL
    const EPAYEE_BASE_URL_NOT_SET: u64 = 6;

    /// Value of the dual attestation limit at genesis
    const INITIAL_DUAL_ATTESTATION_LIMIT: u64 = 1000;
    /// Suffix of every signed dual attestation message
    const DOMAIN_SEPARATOR: vector<u8> = b"@@$$DIEM_ATTEST$$@@";
    /// A year in microseconds
    const ONE_YEAR: u64 = 31540000000000;
    const U64_MAX: u64 = 18446744073709551615;

    /// Publish a `Credential` resource with name `human_name` under `created` with an empty
    /// `base_url` and `compliance_public_key`. Before receiving any dual attestation payments,
    /// the `created` account must send a transaction that invokes `rotate_base_url` and
    /// `rotate_compliance_public_key` to set these fields to a valid URL/public key.
    public fun publish_credential(
        created: &signer,
        creator: &signer,
        human_name: vector<u8>,
    ) {
        Roles::assert_parent_vasp_or_designated_dealer(created);
        Roles::assert_treasury_compliance(creator);
        assert(
            !exists<Credential>(Signer::address_of(created)),
            Errors::already_published(ECREDENTIAL)
        );
        move_to(created, Credential {
            human_name,
            base_url: Vector::empty(),
            compliance_public_key: Vector::empty(),
            // For testnet and V1, so it should never expire. So set to u64::MAX
            expiration_date: U64_MAX,
            compliance_key_rotation_events: Event::new_event_handle<ComplianceKeyRotationEvent>(created),
            base_url_rotation_events: Event::new_event_handle<BaseUrlRotationEvent>(created),
        })
    }

    /// Rotate the base URL for `account` to `new_url`
    public fun rotate_base_url(account: &signer, new_url: vector<u8>) acquires Credential {
        let addr = Signer::address_of(account);
        assert(exists<Credential>(addr), Errors::not_published(ECREDENTIAL));
        let credential = borrow_global_mut<Credential>(addr);
        credential.base_url = copy new_url;
        Event::emit_event(&mut credential.base_url_rotation_events, BaseUrlRotationEvent {
            new_base_url: new_url,
            time_rotated_seconds: Time::now_seconds(),
        });
    }

    /// Rotate the compliance public key for `account` to `new_key`.
    public fun rotate_compliance_public_key(
        account: &signer,
        new_key: vector<u8>,
    ) acquires Credential {
        let addr = Signer::address_of(account);
        assert(exists<Credential>(addr), Errors::not_published(ECREDENTIAL));
        assert(Signature::ed25519_validate_pubkey(copy new_key), Errors::invalid_argument(EINVALID_PUBLIC_KEY));
        let credential = borrow_global_mut<Credential>(addr);
        credential.compliance_public_key = copy new_key;
        Event::emit_event(&mut credential.compliance_key_rotation_events, ComplianceKeyRotationEvent {
            new_compliance_public_key: new_key,
            time_rotated_seconds: Time::now_seconds(),
        });

    }

    /// Return the human-readable name for the VASP account.
    /// Aborts if `addr` does not have a `Credential` resource.
    public fun human_name(addr: address): vector<u8> acquires Credential {
        assert(exists<Credential>(addr), Errors::not_published(ECREDENTIAL));
        *&borrow_global<Credential>(addr).human_name
    }

    /// Return the base URL for `addr`.
    /// Aborts if `addr` does not have a `Credential` resource.
    public fun base_url(addr: address): vector<u8> acquires Credential {
        assert(exists<Credential>(addr), Errors::not_published(ECREDENTIAL));
        *&borrow_global<Credential>(addr).base_url
    }

    /// Return the compliance public key for `addr`.
    /// Aborts if `addr` does not have a `Credential` resource.
    public fun compliance_public_key(addr: address): vector<u8> acquires Credential {
        assert(exists<Credential>(addr), Errors::not_published(ECREDENTIAL));
        *&borrow_global<Credential>(addr).compliance_public_key
    }

    /// Return the expiration date `addr`
    /// Aborts if `addr` does not have a `Credential` resource.
    public fun expiration_date(addr: address): u64  acquires Credential {
        assert(exists<Credential>(addr), Errors::not_published(ECREDENTIAL));
        *&borrow_global<Credential>(addr).expiration_date
    }

    ///////////////////////////////////////////////////////////////////////////
    // Dual attestation requirements and checking
    ///////////////////////////////////////////////////////////////////////////

    /// Return the address where the credentials for `addr` are stored
    fun credential_address(addr: address): address {
        if (VASP::is_child(addr)) VASP::parent_address(addr) else addr
    }

    /// Helper which returns true if dual attestion is required for a deposit.
    fun dual_attestation_required<Token: store>(
        payer: address, payee: address, deposit_value: u64
    ): bool acquires Limit {
        // travel rule applies for payments over a limit
        let travel_rule_limit_microdiem = get_cur_microdiem_limit();
        let approx_xdx_microdiem_value = Diem::approx_xdx_for_value<Token>(deposit_value);
        let above_limit = approx_xdx_microdiem_value >= travel_rule_limit_microdiem;
        if (!above_limit) {
            return false
        };
        // self-deposits never require dual attestation
        if (payer == payee) {
            return false
        };
        // dual attestation is required if the amount is above the limit AND between distinct
        // VASPs
        VASP::is_vasp(payer) && VASP::is_vasp(payee) &&
            VASP::parent_address(payer) != VASP::parent_address(payee)
    }

    /// Helper to construct a message for dual attestation.
    /// Message is `metadata` | `payer` | `amount` | `DOMAIN_SEPARATOR`.
    fun dual_attestation_message(
        payer: address, metadata: vector<u8>, deposit_value: u64
    ): vector<u8> {
        let message = metadata;
        Vector::append(&mut message, BCS::to_bytes(&payer));
        Vector::append(&mut message, BCS::to_bytes(&deposit_value));
        Vector::append(&mut message, DOMAIN_SEPARATOR);
        message
    }

    /// Helper function to check validity of a signature when dual attestion is required.
    fun assert_signature_is_valid(
        payer: address,
        payee: address,
        metadata_signature: vector<u8>,
        metadata: vector<u8>,
        deposit_value: u64
    ) acquires Credential {
        // sanity check of signature validity
        assert(
            Vector::length(&metadata_signature) == 64,
            Errors::invalid_argument(EMALFORMED_METADATA_SIGNATURE)
        );
        // sanity check of payee compliance key validity
        let payee_compliance_key = compliance_public_key(credential_address(payee));
        assert(
            !Vector::is_empty(&payee_compliance_key),
            Errors::invalid_state(EPAYEE_COMPLIANCE_KEY_NOT_SET)
        );
        // sanity check of payee base URL validity
        let payee_base_url = base_url(credential_address(payee));
        assert(
            !Vector::is_empty(&payee_base_url),
            Errors::invalid_state(EPAYEE_BASE_URL_NOT_SET)
        );
        // cryptographic check of signature validity
        let message = dual_attestation_message(payer, metadata, deposit_value);
        assert(
            Signature::ed25519_verify(metadata_signature, payee_compliance_key, message),
            Errors::invalid_argument(EINVALID_METADATA_SIGNATURE),
        );
    }

    /// Public API for checking whether a payment of `value` coins of type `Currency`
    /// from `payer` to `payee` has a valid dual attestation. This returns without aborting if
    /// (1) dual attestation is not required for this payment, or
    /// (2) dual attestation is required, and `metadata_signature` can be verified on the message
    ///     `metadata` | `payer` | `value` | `DOMAIN_SEPARATOR` using the `compliance_public_key`
    ///     published in `payee`'s `Credential` resource
    /// It aborts with an appropriate error code if dual attestation is required, but one or more of
    /// the conditions in (2) is not met.
    public fun assert_payment_ok<Currency: store>(
        payer: address,
        payee: address,
        value: u64,
        metadata: vector<u8>,
        metadata_signature: vector<u8>
    ) acquires Credential, Limit {
        if (!Vector::is_empty(&metadata_signature) || // allow opt-in dual attestation
            dual_attestation_required<Currency>(payer, payee, value)
        ) {
          assert_signature_is_valid(payer, payee, metadata_signature, metadata, value)
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    // Creating and updating dual attestation limit
    ///////////////////////////////////////////////////////////////////////////

    /// Travel rule limit set during genesis
    public fun initialize(dr_account: &signer) {
        Time::assert_genesis();
        CoreAddresses::assert_diem_root(dr_account); // operational constraint.
        assert(!exists<Limit>(CoreAddresses::DIEM_ROOT_ADDRESS()), Errors::already_published(ELIMIT));
        let initial_limit = (INITIAL_DUAL_ATTESTATION_LIMIT as u128) * (Diem::scaling_factor<PONT>() as u128);
        assert(initial_limit <= MAX_U64, Errors::limit_exceeded(ELIMIT));
        move_to(
            dr_account,
            Limit {
                micro_xdx_limit: (initial_limit as u64)
            }
        )
    }

    /// Return the current dual attestation limit in microdiem
    public fun get_cur_microdiem_limit(): u64 acquires Limit {
        assert(exists<Limit>(CoreAddresses::DIEM_ROOT_ADDRESS()), Errors::not_published(ELIMIT));
        borrow_global<Limit>(CoreAddresses::DIEM_ROOT_ADDRESS()).micro_xdx_limit
    }

    /// Set the dual attestation limit to `micro_diem_limit`.
    /// Aborts if `tc_account` does not have the TreasuryCompliance role
    public fun set_microdiem_limit(tc_account: &signer, micro_xdx_limit: u64) acquires Limit {
        Roles::assert_treasury_compliance(tc_account);
        assert(exists<Limit>(CoreAddresses::DIEM_ROOT_ADDRESS()), Errors::not_published(ELIMIT));
        borrow_global_mut<Limit>(CoreAddresses::DIEM_ROOT_ADDRESS()).micro_xdx_limit = micro_xdx_limit;
    }
}
}
