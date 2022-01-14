#[test_only]
module PontemFramework::PontBlockTests {
    use PontemFramework::PontBlock;
    use PontemFramework::Genesis;

    #[test(root_acc = @Root)]
    fun test_initial_block_height(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        assert!(PontBlock::get_current_block_height() == 0, 1);
    }
}
