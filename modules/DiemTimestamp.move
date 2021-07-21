address 0x1 {

/// This module keeps a global wall clock that stores the current Unix time in microseconds.
/// It interacts with the other modules in the following ways:
///
/// * Genesis: to initialize the timestamp
/// * VASP: to keep track of when credentials expire
/// * DiemSystem, DiemAccount, DiemConfig: to check if the current state is in the genesis state
/// * DiemBlock: to reach consensus on the global wall clock time
/// * AccountLimits: to limit the time of account limits
///
/// This module moreover enables code to assert that it is running in genesis (`Self::assert_genesis`) or after
/// genesis (`Self::assert_operating`). These are essentially distinct states of the system. Specifically,
/// if `Self::assert_operating` succeeds, assumptions about invariants over the global state can be made
/// which reflect that the system has been successfully initialized.
module DiemTimestamp {
    use 0x1::CoreAddresses;
    use 0x1::Errors;

    /// A singleton resource holding the current Unix time in microseconds
    struct CurrentTimeMicroseconds has key {
        microseconds: u64,
    }

    /// Conversion factor between seconds and microseconds
    const MICRO_CONVERSION_FACTOR: u64 = 1000000;

    /// The blockchain is not in the genesis state anymore
    const ENOT_GENESIS: u64 = 0;
    /// The blockchain is not in an operating state yet
    const ENOT_OPERATING: u64 = 1;
    /// An invalid timestamp was provided
    const ETIMESTAMP: u64 = 2;

//    public fun set_time_has_started(dr_account: &signer) {
//        assert_genesis();
//        CoreAddresses::assert_diem_root(dr_account);
//        let timer = CurrentTimeMicroseconds { microseconds: 0 };
//        move_to(dr_account, timer);
//    }
//    spec fun set_time_has_started {
//        /// The friend of this function is `Genesis::initialize` which means that
//        /// this function can't be verified on its own and has to be verified in
//        /// context of Genesis execution.
//        /// After time has started, all invariants guarded by `DiemTimestamp::is_operating`
//        /// will become activated and need to hold.
//        pragma friend = 0x1::Genesis::initialize;
//        include AbortsIfNotGenesis;
//        include CoreAddresses::AbortsIfNotDiemRoot{account: dr_account};
//        ensures is_operating();
//    }

    /// Updates the wall clock time by consensus. Requires VM privilege and will be invoked during block prologue.
    public fun update_global_time(
        account: &signer,
        proposer: address,
        timestamp: u64
    ) acquires CurrentTimeMicroseconds {
        assert_operating();
        // Can only be invoked by DiemVM signer.
        CoreAddresses::assert_vm(account);

        let global_timer = borrow_global_mut<CurrentTimeMicroseconds>(CoreAddresses::DIEM_ROOT_ADDRESS());
        let now = global_timer.microseconds;
        if (proposer == CoreAddresses::VM_RESERVED_ADDRESS()) {
            // NIL block with null address as proposer. Timestamp must be equal.
            assert(now == timestamp, Errors::invalid_argument(ETIMESTAMP));
        } else {
            // Normal block. Time must advance
            assert(now < timestamp, Errors::invalid_argument(ETIMESTAMP));
        };
        global_timer.microseconds = timestamp;
    }

    /// Gets the current time in microseconds.
    public fun now_microseconds(): u64 acquires CurrentTimeMicroseconds {
        assert_operating();
        borrow_global<CurrentTimeMicroseconds>(CoreAddresses::DIEM_ROOT_ADDRESS()).microseconds
    }

    /// Gets the current time in seconds.
    public fun now_seconds(): u64 acquires CurrentTimeMicroseconds {
        now_microseconds() / MICRO_CONVERSION_FACTOR
    }

    /// Helper function to determine if Diem is in genesis state.
    public fun is_genesis(): bool {
        !exists<CurrentTimeMicroseconds>(CoreAddresses::DIEM_ROOT_ADDRESS())
    }

    /// Helper function to assert genesis state.
    public fun assert_genesis() {
        assert(is_genesis(), Errors::invalid_state(ENOT_GENESIS));
    }

    /// Helper function to determine if Diem is operating. This is the same as `!is_genesis()` and is provided
    /// for convenience. Testing `is_operating()` is more frequent than `is_genesis()`.
    public fun is_operating(): bool {
        exists<CurrentTimeMicroseconds>(CoreAddresses::DIEM_ROOT_ADDRESS())
    }

    /// Helper function to assert operating (!genesis) state.
    public fun assert_operating() {
        assert(is_operating(), Errors::invalid_state(ENOT_OPERATING));
    }
}
}
