address 0x1 {

module Block {
    use 0x1::CoreAddresses;

    struct BlockMetadata has key {
        // height of the current block
        height: u64,
    }

    // Get the current block height
    public fun get_current_block_height(): u64 acquires BlockMetadata {
        borrow_global<BlockMetadata>(CoreAddresses::DIEM_ROOT_ADDRESS()).height
    }
}
}
