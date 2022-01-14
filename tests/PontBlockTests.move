#[test_only]
module PontemFramework::PontBlockTests {
    use PontemFramework::PontBlock;
    use PontemFramework::Genesis;

    #[test(root_acc = @Root)]
    fun test_set_block_height(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        PontBlock::set_current_block_height(10);
        assert!(PontBlock::get_current_block_height() == 10, 1);
    }
}
