#[test_only]
module PontemFramework::NativeTokenTests {
    use PontemFramework::PONT::{Self, PONT};
    use PontemFramework::KSM::{Self, KSM};
    use PontemFramework::PontAccount;
    use Std::Signer;

    #[test(root_acc = @Root, user_acc = @0x42)]
    fun test_mint_deposit_and_burn_some_coins(root_acc: signer, user_acc: signer) {
        let ponts = PONT::mint(&root_acc, 2);
        let ksms = KSM::mint(&root_acc, 3);

        let user_addr = Signer::address_of(&user_acc);
        PontAccount::deposit(&root_acc, user_addr, ponts, b"");
        PontAccount::deposit(&root_acc, user_addr, ksms, b"");

        assert!(PontAccount::balance<PONT>(user_addr) == 2, 1);
        assert!(PontAccount::balance<KSM>(user_addr) == 3, 2);

        let withdrawn_ponts = PontAccount::withdraw<PONT>(&user_acc, 1);
        let withdrawn_ksms = PontAccount::withdraw<PONT>(&user_acc, 1);
        assert!(PontAccount::balance<PONT>(user_addr) == 1, 3);
        assert!(PontAccount::balance<KSM>(user_addr) == 2, 4);

        PONT::burn(&root_acc, withdrawn_ponts);
        PONT::burn(&root_acc, withdrawn_ksms);
    }
}
