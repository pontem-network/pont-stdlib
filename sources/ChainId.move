/// The chain id distinguishes between different chains (e.g., testnet and the main Pontem network).
/// Allows to get chain id in a smart contract.
module PontemFramework::ChainId {
    use PontemFramework::CoreAddresses;
    use PontemFramework::PontTimestamp;
    use Std::Errors;
    use Std::Signer;

    struct ChainId has key {
        id: u8
    }

    /// The `ChainId` resource was not in the required state
    const ERR_CHAIN_ID: u64 = 0;

    /// Publish the chain ID `id` of this Pontem instance under the Root account
    public fun initialize(root_account: &signer, id: u8) {
        PontTimestamp::assert_genesis();
        CoreAddresses::assert_root(root_account);
        assert!(
            !exists<ChainId>(Signer::address_of(root_account)),
            Errors::already_published(ERR_CHAIN_ID)
        );
        move_to(root_account, ChainId { id })
    }

    spec initialize {
        pragma opaque;
        let root_addr = Signer::address_of(root_account);
        modifies global<ChainId>(root_addr);
        include PontTimestamp::AbortsIfNotGenesis;
        include CoreAddresses::AbortsIfNotRoot{ account: root_account };
        aborts_if exists<ChainId>(root_addr) with Errors::ALREADY_PUBLISHED;
        ensures exists<ChainId>(root_addr);
    }

    /// Return the chain ID of this Pontem instance
    public fun get(): u8 acquires ChainId {
        PontTimestamp::assert_operating();
        borrow_global<ChainId>(@Root).id
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Initialization

    spec module {
        /// When Diem is operating, the chain id is always available.
        invariant [suspendable] PontTimestamp::is_operating() ==> exists<ChainId>(@Root);

        // Could also specify that ChainId is not stored on any other address, but it doesn't matter.
    }

    /// # Helper Functions

    spec fun spec_get_chain_id(): u8 {
        global<ChainId>(@Root).id
    }
}
