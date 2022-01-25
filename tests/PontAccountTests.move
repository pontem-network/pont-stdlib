#[test_only]
module PontemFramework::PontAccountTests {
    use Std::Signer;
    use PontemFramework::Genesis;
    use PontemFramework::NOX::{Self, NOX};
    use PontemFramework::PontAccount;
    use PontemFramework::Token;

    #[test(root_acc = @Root, user1_acc = @0x11, user2_acc = @0x12)]
    fun test_mint_some_tokens_and_move_them_around(root_acc: signer, user1_acc: signer, user2_acc: signer) {
        Genesis::setup(&root_acc, 1);

        let user1_addr = Signer::address_of(&user1_acc);
        let user2_addr = Signer::address_of(&user2_acc);

        let ponts = NOX::mint(&root_acc, 10);
        let (ponts_7, ponts_3) = Token::split(ponts, 3);

        PontAccount::deposit(&root_acc, user1_addr, ponts_7);
        PontAccount::deposit(&root_acc, user2_addr, ponts_3);

        assert!(PontAccount::balance<NOX>(user1_addr) == 7, 1);
        assert!(PontAccount::balance<NOX>(user2_addr) == 3, 2);

        PontAccount::pay_from<NOX>(&user1_acc, user2_addr, 5);
        assert!(PontAccount::balance<NOX>(user1_addr) == 2, 3);
        assert!(PontAccount::balance<NOX>(user2_addr) == 8, 4);
    }
}
