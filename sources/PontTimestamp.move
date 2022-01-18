/// This module keeps a global wall clock that stores the current Unix time in microseconds.
/// It interacts with the other modules in the following ways:
///
/// * To initialize the timestamp from genesis.
/// * To check if the current state is in the genesis state.
///
/// This module moreover enables code to assert that it is running in genesis (`Self::assert_genesis`) or after
/// genesis (`Self::assert_operating`). These are essentially distinct states of the system. Specifically,
/// if `Self::assert_operating` succeeds, assumptions about invariants over the global state can be made
/// which reflect that the system has been successfully initialized.
module PontemFramework::PontTimestamp {
    use Std::Errors;

    use PontemFramework::CoreAddresses;
    friend PontemFramework::Genesis;

    /// A singleton resource holding the current Unix time in microseconds
    struct CurrentTimeMicroseconds has key {
        microseconds: u64,
    }

    /// Conversion factor between seconds and microseconds
    const MICRO_CONVERSION_FACTOR: u64 = 1000000;

    /// The blockchain is not in the genesis state anymore
    const ERR_NOT_GENESIS: u64 = 0;
    /// The blockchain is not in an operating state yet
    const ERR_NOT_OPERATING: u64 = 1;

    /// Marks that time has started and genesis has finished. This can only be called from genesis and with the root
    /// account.
    public(friend) fun set_time_has_started(root_account: &signer) {
        assert_genesis();
        CoreAddresses::assert_root(root_account);
        let timer = CurrentTimeMicroseconds { microseconds: 0 };
        move_to(root_account, timer);
    }
    spec set_time_has_started {
        /// This function can't be verified on its own and has to be verified in the context of Genesis execution.
        ///
        /// After time has started, all invariants guarded by `PontTimestamp::is_operating` will become activated
        /// and need to hold.
        pragma delegate_invariants_to_caller;
        include AbortsIfNotGenesis;
        include CoreAddresses::AbortsIfNotRoot{account: root_account};
        ensures is_operating();
    }

    /// Gets the current time in microseconds.
    public fun now_microseconds(): u64 acquires CurrentTimeMicroseconds {
        assert_operating();
        borrow_global<CurrentTimeMicroseconds>(@Root).microseconds
    }
    spec now_microseconds {
        pragma opaque;
        include AbortsIfNotOperating;
        ensures result == spec_now_microseconds();
    }
    spec fun spec_now_microseconds(): u64 {
        global<CurrentTimeMicroseconds>(@Root).microseconds
    }

    /// Gets the current time in seconds.
    public fun now_seconds(): u64 acquires CurrentTimeMicroseconds {
        now_microseconds() / MICRO_CONVERSION_FACTOR
    }
    spec now_seconds {
        pragma opaque;
        include AbortsIfNotOperating;
        ensures result == spec_now_microseconds() /  MICRO_CONVERSION_FACTOR;
    }
    spec fun spec_now_seconds(): u64 {
        global<CurrentTimeMicroseconds>(@Root).microseconds / MICRO_CONVERSION_FACTOR
    }

    #[test_only]
    public fun set_time_microseconds(ms: u64) acquires CurrentTimeMicroseconds {
        assert!(is_operating(), Errors::invalid_state(ERR_NOT_OPERATING));
        borrow_global_mut<CurrentTimeMicroseconds>(@Root).microseconds = ms;
    }

    #[test_only]
    public fun set_time_seconds(s: u64) acquires CurrentTimeMicroseconds {
        let microseconds = s * MICRO_CONVERSION_FACTOR;
        set_time_microseconds(microseconds);
    }

    /// Helper function to determine if Pontem is in genesis state.
    public fun is_genesis(): bool {
        !exists<CurrentTimeMicroseconds>(@Root)
    }

    /// Helper function to assert genesis state.
    public fun assert_genesis() {
        assert!(is_genesis(), Errors::invalid_state(ERR_NOT_GENESIS));
    }
    spec assert_genesis {
        pragma opaque;
        include AbortsIfNotGenesis;
    }

    /// Helper schema to specify that a function aborts if not in genesis.
    spec schema AbortsIfNotGenesis {
        aborts_if !is_genesis() with Errors::INVALID_STATE;
    }

    /// Helper function to determine if Pontem is operating. This is the same as `!is_genesis()` and is provided
    /// for convenience. Testing `is_operating()` is more frequent than `is_genesis()`.
    public fun is_operating(): bool {
        exists<CurrentTimeMicroseconds>(@Root)
    }

    /// Helper function to assert operating (!genesis) state.
    public fun assert_operating() {
        assert!(is_operating(), Errors::invalid_state(ERR_NOT_OPERATING));
    }
    spec assert_operating {
        pragma opaque;
        include AbortsIfNotOperating;
    }

    /// Helper schema to specify that a function aborts if not operating.
    spec schema AbortsIfNotOperating {
        aborts_if !is_operating() with Errors::INVALID_STATE;
    }

    // ====================
    // Module Specification
    spec module {} // switch documentation context to module level

    spec module {
        /// After genesis, `CurrentTimeMicroseconds` is published forever
        invariant is_operating() ==> exists<CurrentTimeMicroseconds>(@Root);

        /// After genesis, time progresses monotonically.
        invariant update
            old(is_operating()) ==> old(spec_now_microseconds()) <= spec_now_microseconds();
    }

    spec module {
        /// All functions which do not have an `aborts_if` specification in this module are implicitly declared
        /// to never abort.
        pragma aborts_if_is_strict;
    }

}
