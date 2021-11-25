/// PONT Coin. The one and only.
/// Put into separate module to highlight its importance and role in Pontem
/// ecosystem. Also moved not to be mistaken for peg-zone coin. Same-naming
/// attack from peg-zone is impossible when XFI coin moved outside of Coins module
module DiemFramework::PONT {
    use DiemFramework::AccountLimits;
    use DiemFramework::CoreAddresses;
    use Std::FixedPoint32;
    use DiemFramework::Diem;
    use DiemFramework::DiemTimestamp;

    struct PONT has key, store {}

    struct Drop has key {
        mint_cap: Diem::MintCapability<PONT>,
        burn_cap: Diem::BurnCapability<PONT>,
    }

    /// Registers the `XUS` cointype. This can only be called from genesis.
    public fun initialize(
        dr_account: &signer,
        tc_account: &signer,
    ) {
        DiemTimestamp::assert_genesis();
        // Operational constraint
        CoreAddresses::assert_currency_info(dr_account);
        let (mint_cap, burn_cap) = Diem::register_native_currency<PONT>(
            dr_account,
            FixedPoint32::create_from_rational(1, 1), // exchange rate to PONT
            10000000000, // scaling_factor = 10^10
            10000000000, // fractional_part = 10^10
            b"PONT",
            b"PONT"
        );

        AccountLimits::publish_unrestricted_limits<PONT>(dr_account);
        Diem::update_minting_ability<PONT>(tc_account, false);
        move_to(dr_account, Drop {mint_cap, burn_cap});
    }
}
