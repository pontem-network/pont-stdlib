address 0x1 {

/// This module defines a struct storing the metadata of the block and new block events.
module DiemBlock {
    use 0x1::CoreAddresses;
    use 0x1::Errors;
    use 0x1::DiemTimestamp;

    struct BlockMetadata has key {
        /// Height of the current block
        height: u64,
    }

    /// The `BlockMetadata` resource is in an invalid state
    const EBLOCK_METADATA: u64 = 0;
    /// An invalid signer was provided. Expected the signer to be the VM or a Validator.
    const EVM_OR_VALIDATOR: u64 = 1;

    /// This can only be invoked by the Association address, and only a single time.
    /// Currently, it is invoked in the genesis transaction
    public fun initialize_block_metadata(account: &signer) {
        DiemTimestamp::assert_genesis();
        // Operational constraint, only callable by the Association address
        CoreAddresses::assert_diem_root(account);

        assert(!is_initialized(), Errors::already_published(EBLOCK_METADATA));
        move_to<BlockMetadata>(
            account,
            BlockMetadata {
                height: 0,
            }
        );
    }

    /// Helper function to determine whether this module has been initialized.
    fun is_initialized(): bool {
        exists<BlockMetadata>(CoreAddresses::DIEM_ROOT_ADDRESS())
    }

    /// Get the current block height
    public fun get_current_block_height(): u64 acquires BlockMetadata {
        assert(is_initialized(), Errors::not_published(EBLOCK_METADATA));
        borrow_global<BlockMetadata>(CoreAddresses::DIEM_ROOT_ADDRESS()).height
    }

    spec module {} // Switch documentation context to module level.

    /// # Initialization
    /// This implies that `BlockMetadata` is published after initialization and stays published
    /// ever after
    spec module {
        invariant [global] DiemTimestamp::is_operating() ==> is_initialized();
    }
}
}
