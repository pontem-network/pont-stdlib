address 0x1 {

/// A VASP is one type of balance-holding account on the blockchain. VASPs from a two-layer
/// hierarchy.  The main account, called a "parent VASP" and a collection of "child VASP"s.
/// This module provides functions to manage VASP accounts.

module VASP {
    use 0x1::Errors;
    use 0x1::Time;
    use 0x1::Signer;
    use 0x1::Roles;
    use 0x1::AccountLimits;

    /// Each VASP has a unique root account that holds a `ParentVASP` resource. This resource holds
    /// the VASP's globally unique name and all of the metadata that other VASPs need to perform
    /// off-chain protocols with this one.
    struct ParentVASP has key {
        /// Number of child accounts this parent has created.
        num_children: u64
    }

    /// A resource that represents a child account of the parent VASP account at `parent_vasp_addr`
    struct ChildVASP has key { parent_vasp_addr: address }

    /// The `ParentVASP` or `ChildVASP` resources are not in the required state
    const EPARENT_OR_CHILD_VASP: u64 = 0;
    /// The creation of a new Child VASP account would exceed the number of children permitted for a VASP
    const ETOO_MANY_CHILDREN: u64 = 1;
    /// The account must be a Parent or Child VASP account
    const ENOT_A_VASP: u64 = 2;
    /// The creating account must be a Parent VASP account
    const ENOT_A_PARENT_VASP: u64 = 3;


    /// Maximum number of child accounts that can be created by a single ParentVASP
    const MAX_CHILD_ACCOUNTS: u64 = 65536; // 2^16

    ///////////////////////////////////////////////////////////////////////////
    // To-be parent-vasp called functions
    ///////////////////////////////////////////////////////////////////////////

    /// Create a new `ParentVASP` resource under `vasp`
    /// Aborts if `dr_account` is not the diem root account,
    /// or if there is already a VASP (child or parent) at this account.
    public fun publish_parent_vasp_credential(vasp: &signer, tc_account: &signer) {
        Time::assert_operating();
        Roles::assert_treasury_compliance(tc_account);
        Roles::assert_parent_vasp_role(vasp);
        let vasp_addr = Signer::address_of(vasp);
        assert(!is_vasp(vasp_addr), Errors::already_published(EPARENT_OR_CHILD_VASP));
        move_to(vasp, ParentVASP { num_children: 0 });
    }

    /// Create a child VASP resource for the `parent`
    /// Aborts if `parent` is not a ParentVASP
    public fun publish_child_vasp_credential(
        parent: &signer,
        child: &signer,
    ) acquires ParentVASP {
        Roles::assert_parent_vasp_role(parent);
        Roles::assert_child_vasp_role(child);
        let child_vasp_addr = Signer::address_of(child);
        assert(!is_vasp(child_vasp_addr), Errors::already_published(EPARENT_OR_CHILD_VASP));
        let parent_vasp_addr = Signer::address_of(parent);
        assert(is_parent(parent_vasp_addr), Errors::invalid_argument(ENOT_A_PARENT_VASP));
        let num_children = &mut borrow_global_mut<ParentVASP>(parent_vasp_addr).num_children;
        // Abort if creating this child account would put the parent VASP over the limit
        assert(*num_children < MAX_CHILD_ACCOUNTS, Errors::limit_exceeded(ETOO_MANY_CHILDREN));
        *num_children = *num_children + 1;
        move_to(child, ChildVASP { parent_vasp_addr });
    }

    /// Return `true` if `addr` is a parent or child VASP whose parent VASP account contains an
    /// `AccountLimits<CoinType>` resource.
    /// Aborts if `addr` is not a VASP
    public fun has_account_limits<CoinType: store>(addr: address): bool acquires ChildVASP {
        AccountLimits::has_window_published<CoinType>(parent_address(addr))
    }

    ///////////////////////////////////////////////////////////////////////////
    // Publicly callable APIs
    ///////////////////////////////////////////////////////////////////////////

    /// Return `addr` if `addr` is a `ParentVASP` or its parent's address if it is a `ChildVASP`
    /// Aborts otherwise
    public fun parent_address(addr: address): address acquires ChildVASP {
        if (is_parent(addr)) {
            addr
        } else if (is_child(addr)) {
            borrow_global<ChildVASP>(addr).parent_vasp_addr
        } else { // wrong account type, abort
            abort(Errors::invalid_argument(ENOT_A_VASP))
        }
    }

    /// Returns true if `addr` is a parent VASP.
    public fun is_parent(addr: address): bool {
        exists<ParentVASP>(addr)
    }

    /// Returns true if `addr` is a child VASP.
    public fun is_child(addr: address): bool {
        exists<ChildVASP>(addr)
    }

    /// Returns true if `addr` is a VASP.
    public fun is_vasp(addr: address): bool {
        is_parent(addr) || is_child(addr)
    }

    /// Returns true if both addresses are VASPs and they have the same parent address.
    public fun is_same_vasp(addr1: address, addr2: address): bool acquires ChildVASP {
        is_vasp(addr1) && is_vasp(addr2) && parent_address(addr1) == parent_address(addr2)
    }

    /// If `addr` is the address of a `ParentVASP`, return the number of children.
    /// If it is the address of a ChildVASP, return the number of children of the parent.
    /// The total number of accounts for this VASP is num_children() + 1
    /// Aborts if `addr` is not a ParentVASP or ChildVASP account
    public fun num_children(addr: address): u64  acquires ChildVASP, ParentVASP {
        // If parent VASP succeeds, the parent is guaranteed to exist.
        *&borrow_global<ParentVASP>(parent_address(addr)).num_children
    }
}
}
