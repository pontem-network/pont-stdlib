/// The `Genesis` module defines the Move initialization entry point of the Pontem framework
/// when executing from a fresh state.
module PontemFramework::Genesis {
    use PontemFramework::PontTimestamp;
    use PontemFramework::PontBlock;
    use PontemFramework::ChainId;
    use PontemFramework::NOX;
    use PontemFramework::KSM;

    /// Initializes the Pontem framework.
    fun initialize(
        root_account: signer,
        chain_id: u8,
    ) {
        initialize_internal(&root_account, chain_id)
    }

    /// Initializes the Pontem Framework.
    /// Extracted in the separate method, so it can be used by both genesis code, and for testing purposes.
    fun initialize_internal(
        root_account: &signer,
        chain_id: u8,
    ) {
        PontBlock::initialize_block_metadata(root_account);
        ChainId::initialize(root_account, chain_id);

        // Currencies setup.
        NOX::initialize(root_account);
        KSM::initialize(root_account);

        PontTimestamp::set_time_has_started(root_account);
    }

    /// For verification of genesis, the goal is to prove that all the invariants which
    /// become active after the end of this function hold. This cannot be achieved with
    /// modular verification as we do in regular continuous testing. Rather, this module must
    /// be verified **together** with the module(s) which provides the invariant.
    spec initialize {
        /// Assume that this is called in genesis state (no timestamp).
        requires PontTimestamp::is_genesis();
    }

    #[test_only]
    public fun setup(root_account: &signer, chain_id: u8) {
        initialize_internal(root_account, chain_id)
    }
}
