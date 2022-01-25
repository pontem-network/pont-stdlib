#[test_only]
module PontemFramework::NativeTokenTests {
    use PontemFramework::NOX::{Self, NOX};
    use PontemFramework::KSM::{Self, KSM};
    use PontemFramework::Token;
    use PontemFramework::PontAccount;
    use PontemFramework::Genesis;
    use Std::Signer;

    #[test(root_acc = @Root, user_acc = @0x42)]
    fun test_mint_deposit_and_burn_some_coins(root_acc: signer, user_acc: signer) {
        Genesis::setup(&root_acc, 1);

        let ponts = NOX::mint(&root_acc, 2);
        let ksms = KSM::mint(&root_acc, 3);

        let user_addr = Signer::address_of(&user_acc);
        PontAccount::deposit(&root_acc, user_addr, ponts);
        PontAccount::deposit(&root_acc, user_addr, ksms);

        assert!(PontAccount::balance<NOX>(user_addr) == 2, 1);
        assert!(PontAccount::balance<KSM>(user_addr) == 3, 2);

        let withdrawn_ponts = PontAccount::withdraw<NOX>(&user_acc, 1);
        let withdrawn_ksms = PontAccount::withdraw<KSM>(&user_acc, 1);

        assert!(PontAccount::balance<NOX>(user_addr) == 1, 3);
        assert!(PontAccount::balance<KSM>(user_addr) == 2, 4);

        NOX::burn(&root_acc, withdrawn_ponts);
        KSM::burn(&root_acc, withdrawn_ksms);

        assert!(Token::total_value<NOX>() == 1, 3);
        assert!(Token::total_value<KSM>() == 2, 3);
    }
}
