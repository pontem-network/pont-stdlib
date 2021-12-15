/// This module defines a struct storing the metadata of the block and new block events.
module PontemFramework::PontBlock {
    use PontemFramework::CoreAddresses;
    use PontemFramework::PontTimestamp;
    use Std::Errors;

    struct BlockMetadata has key {
        /// Height of the current block
        height: u64,
    }

    struct NewBlockEvent has drop, store {
        round: u64,
        proposer: address,
        previous_block_votes: vector<address>,

        /// On-chain time during  he block at the given height
        time_microseconds: u64,
    }

    /// The `BlockMetadata` resource is in an invalid state
    const EBLOCK_METADATA: u64 = 0;
    /// An invalid signer was provided. Expected the signer to be the VM or a Validator.
    const EVM_OR_VALIDATOR: u64 = 1;

    /// This can only be invoked by the Association address, and only a single time.
    /// Currently, it is invoked in the genesis transaction
    public fun initialize_block_metadata(account: &signer) {
        PontTimestamp::assert_genesis();
        // Operational constraint, only callable by the Association address
        CoreAddresses::assert_root(account);

        assert(!is_initialized(), Errors::already_published(EBLOCK_METADATA));
        move_to<BlockMetadata>(
            account,
            BlockMetadata {
                height: 0,
            }
        );
    }
    spec initialize_block_metadata {
        include PontTimestamp::AbortsIfNotGenesis;
        include CoreAddresses::AbortsIfNotRoot;
        aborts_if is_initialized() with Errors::ALREADY_PUBLISHED;
        ensures is_initialized();
        ensures get_current_block_height() == 0;
    }

    /// Helper function to determine whether this module has been initialized.
    fun is_initialized(): bool {
        exists<BlockMetadata>(@Root)
    }

    /// Get the current block height
    public fun get_current_block_height(): u64 acquires BlockMetadata {
        assert(is_initialized(), Errors::not_published(EBLOCK_METADATA));
        borrow_global<BlockMetadata>(@Root).height
    }

    spec module { } // Switch documentation context to module level.

    /// # Initialization
    /// This implies that `BlockMetadata` is published after initialization and stays published
    /// ever after
    spec module {
        invariant [suspendable] PontTimestamp::is_operating() ==> is_initialized();
    }
}
