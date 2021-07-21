address 0x1 {
/// The chain id distinguishes between different chains (e.g., testnet and the main Diem network).
/// One important role is to prevent transactions intended for one chain from being executed on another.
/// This code provides a container for storing a chain id and functions to initialize and get it.
module ChainId {
    use 0x1::CoreAddresses;
    use 0x1::Errors;
    use 0x1::Time;
    use 0x1::Signer;

    struct ChainId has key {
        id: u8
    }

    /// The `ChainId` resource was not in the required state
    const ECHAIN_ID: u64 = 0;

    /// Publish the chain ID `id` of this Diem instance under the DiemRoot account
    public fun initialize(dr_account: &signer, id: u8) {
        Time::assert_genesis();
        CoreAddresses::assert_diem_root(dr_account);
        assert(!exists<ChainId>(Signer::address_of(dr_account)), Errors::already_published(ECHAIN_ID));
        move_to(dr_account, ChainId { id })
    }

    spec fun initialize {
        pragma opaque;
        let dr_addr = Signer::address_of(dr_account);
        modifies global<ChainId>(dr_addr);
        include CoreAddresses::AbortsIfNotDiemRoot{account: dr_account};
        aborts_if exists<ChainId>(dr_addr) with Errors::ALREADY_PUBLISHED;
        ensures exists<ChainId>(dr_addr);
    }

    /// Return the chain ID of this Diem instance
    public fun get(): u8 acquires ChainId {
        Time::assert_operating();
        borrow_global<ChainId>(CoreAddresses::DIEM_ROOT_ADDRESS()).id
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Helper Functions

    spec define spec_get_chain_id(): u8 {
        global<ChainId>(CoreAddresses::DIEM_ROOT_ADDRESS()).id
    }
}
}
