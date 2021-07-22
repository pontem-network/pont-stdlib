address 0x1 {

/// This module defines role-based access control for the Diem framework.
///
/// Roles are associated with accounts and govern what operations are permitted by those accounts. A role
/// is typically asserted on function entry using a statement like `Self::assert_diem_root(account)`. This
/// module provides multiple assertion functions like this one, as well as the functions to setup roles.
///
/// For a conceptual discussion of roles, see the [DIP-2 document][ACCESS_CONTROL].
module Roles {
    use 0x1::Signer;
    use 0x1::CoreAddresses;
    use 0x1::Errors;
    use 0x1::Time;

    /// A `RoleId` resource was in an unexpected state
    const EROLE_ID: u64 = 0;
    /// The signer didn't have the required Diem Root role
    const EDIEM_ROOT: u64 = 1;
    /// The signer didn't have the required Treasury & Compliance role
    const ETREASURY_COMPLIANCE: u64 = 2;
    /// The signer didn't have the required Parent VASP role
    const EPARENT_VASP: u64 = 3;
    /// The signer didn't have the required ParentVASP or ChildVASP role
    const EPARENT_VASP_OR_CHILD_VASP: u64 = 4;
    /// The signer didn't have the required Parent VASP or Designated Dealer role
    const EPARENT_VASP_OR_DESIGNATED_DEALER: u64 = 5;
    /// The signer didn't have the required Designated Dealer role
    const EDESIGNATED_DEALER: u64 = 6;
    /// The signer didn't have the required Child VASP role
    const ECHILD_VASP: u64 = 9;

    ///////////////////////////////////////////////////////////////////////////
    // Role ID constants
    ///////////////////////////////////////////////////////////////////////////

    const DIEM_ROOT_ROLE_ID: u64 = 0;
    const TREASURY_COMPLIANCE_ROLE_ID: u64 = 1;
    const DESIGNATED_DEALER_ROLE_ID: u64 = 2;
    const PARENT_VASP_ROLE_ID: u64 = 5;
    const CHILD_VASP_ROLE_ID: u64 = 6;

    /// The roleId contains the role id for the account. This is only moved
    /// to an account as a top-level resource, and is otherwise immovable.
    struct RoleId has key {
        role_id: u64,
    }

    // =============
    // Role Granting

    /// Publishes diem root role. Granted only in genesis.
    public fun grant_diem_root_role(
        dr_account: &signer,
    ) {
        Time::assert_genesis();
        // Checks actual Diem root because Diem root role is not set
        // until next line of code.
        CoreAddresses::assert_diem_root(dr_account);
        // Grant the role to the diem root account
        grant_role(dr_account, DIEM_ROOT_ROLE_ID);
    }

    /// Publishes treasury compliance role. Granted only in genesis.
    public fun grant_treasury_compliance_role(
        treasury_compliance_account: &signer,
        dr_account: &signer,
    ) acquires RoleId {
        Time::assert_genesis();
        CoreAddresses::assert_treasury_compliance(treasury_compliance_account);
        assert_diem_root(dr_account);
        // Grant the TC role to the treasury_compliance_account
        grant_role(treasury_compliance_account, TREASURY_COMPLIANCE_ROLE_ID);
    }

    /// Publishes a DesignatedDealer `RoleId` under `new_account`.
    /// The `creating_account` must be treasury compliance.
    public fun new_designated_dealer_role(
        creating_account: &signer,
        new_account: &signer,
    ) acquires RoleId {
        assert_treasury_compliance(creating_account);
        grant_role(new_account, DESIGNATED_DEALER_ROLE_ID);
    }

    /// Publish a ParentVASP `RoleId` under `new_account`.
    /// The `creating_account` must be TreasuryCompliance
    public fun new_parent_vasp_role(
        creating_account: &signer,
        new_account: &signer,
    ) acquires RoleId {
        assert_treasury_compliance(creating_account);
        grant_role(new_account, PARENT_VASP_ROLE_ID);
    }

    /// Publish a ChildVASP `RoleId` under `new_account`.
    /// The `creating_account` must be a ParentVASP
    public fun new_child_vasp_role(
        creating_account: &signer,
        new_account: &signer,
    ) acquires RoleId {
        assert_parent_vasp_role(creating_account);
        grant_role(new_account, CHILD_VASP_ROLE_ID);
    }

    /// Helper function to grant a role.
    fun grant_role(account: &signer, role_id: u64) {
        assert(!exists<RoleId>(Signer::address_of(account)), Errors::already_published(EROLE_ID));
        move_to(account, RoleId { role_id });
    }

    // =============
    // Role Checking

    fun has_role(account: &signer, role_id: u64): bool acquires RoleId {
       let addr = Signer::address_of(account);
       exists<RoleId>(addr)
           && borrow_global<RoleId>(addr).role_id == role_id
    }

    public fun has_diem_root_role(account: &signer): bool acquires RoleId {
        has_role(account, DIEM_ROOT_ROLE_ID)
    }

    public fun has_treasury_compliance_role(account: &signer): bool acquires RoleId {
        has_role(account, TREASURY_COMPLIANCE_ROLE_ID)
    }

    public fun has_designated_dealer_role(account: &signer): bool acquires RoleId {
        has_role(account, DESIGNATED_DEALER_ROLE_ID)
    }

    public fun has_parent_VASP_role(account: &signer): bool acquires RoleId {
        has_role(account, PARENT_VASP_ROLE_ID)
    }

    public fun has_child_VASP_role(account: &signer): bool acquires RoleId {
        has_role(account, CHILD_VASP_ROLE_ID)
    }

    public fun get_role_id(a: address): u64 acquires RoleId {
        assert(exists<RoleId>(a), Errors::not_published(EROLE_ID));
        borrow_global<RoleId>(a).role_id
    }

    /// Return true if `addr` is allowed to receive and send `Diem<T>` for any T
    public fun can_hold_balance(account: &signer): bool acquires RoleId {
        // VASP accounts and designated_dealers can hold balances.
        // Administrative accounts (`TreasuryCompliance`, and `DiemRoot`) cannot.
        has_parent_VASP_role(account) ||
        has_child_VASP_role(account) ||
        has_designated_dealer_role(account)
    }

    // ===============
    // Role Assertions

    /// Assert that the account is diem root.
    public fun assert_diem_root(account: &signer) acquires RoleId {
        CoreAddresses::assert_diem_root(account);
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        assert(borrow_global<RoleId>(addr).role_id == DIEM_ROOT_ROLE_ID, Errors::requires_role(EDIEM_ROOT));
    }

    /// Assert that the account is treasury compliance.
    public fun assert_treasury_compliance(account: &signer) acquires RoleId {
        CoreAddresses::assert_treasury_compliance(account);
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        assert(
            borrow_global<RoleId>(addr).role_id == TREASURY_COMPLIANCE_ROLE_ID,
            Errors::requires_role(ETREASURY_COMPLIANCE)
        )
    }

    /// Assert that the account has the parent vasp role.
    public fun assert_parent_vasp_role(account: &signer) acquires RoleId {
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        assert(
            borrow_global<RoleId>(addr).role_id == PARENT_VASP_ROLE_ID,
            Errors::requires_role(EPARENT_VASP)
        )
    }

    /// Assert that the account has the child vasp role.
    public fun assert_child_vasp_role(account: &signer) acquires RoleId {
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        assert(
            borrow_global<RoleId>(addr).role_id == CHILD_VASP_ROLE_ID,
            Errors::requires_role(ECHILD_VASP)
        )
    }

    /// Assert that the account has the designated dealer role.
    public fun assert_designated_dealer(account: &signer) acquires RoleId {
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        assert(
            borrow_global<RoleId>(addr).role_id == DESIGNATED_DEALER_ROLE_ID,
            Errors::requires_role(EDESIGNATED_DEALER)
        )
    }

    /// Assert that the account has either the parent vasp or designated dealer role.
    public fun assert_parent_vasp_or_designated_dealer(account: &signer) acquires RoleId {
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        let role_id = borrow_global<RoleId>(addr).role_id;
        assert(
            role_id == PARENT_VASP_ROLE_ID || role_id == DESIGNATED_DEALER_ROLE_ID,
            Errors::requires_role(EPARENT_VASP_OR_DESIGNATED_DEALER)
        );
    }

    public fun assert_parent_vasp_or_child_vasp(account: &signer) acquires RoleId {
        let addr = Signer::address_of(account);
        assert(exists<RoleId>(addr), Errors::not_published(EROLE_ID));
        let role_id = borrow_global<RoleId>(addr).role_id;
        assert(
            role_id == PARENT_VASP_ROLE_ID || role_id == CHILD_VASP_ROLE_ID,
            Errors::requires_role(EPARENT_VASP_OR_CHILD_VASP)
        );
    }
}
}
