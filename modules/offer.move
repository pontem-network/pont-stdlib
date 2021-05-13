address 0x1 {
// TODO: add optional timeout for reclaiming by original publisher once we have implemented time
module Offer {
  use 0x1::Signer;

  const ERR_INSUFFICIENT_PRIVILEGES: u64 = 11;

  // A wrapper around value `offered` that can be claimed by the address stored in `for`.
  struct T<Offered> has store, key { offered: Offered, for: address }

  // Publish a value of type `Offered` under the sender's account. The value can be claimed by
  // either the `for` address or the transaction sender.
  public fun create<Offered: store>(account: &signer, offered: Offered, for: address) {
    move_to(account, T<Offered> { offered, for });
  }

  // Claim the value of type `Offered` published at `offer_address`.
  // Only succeeds if the sender is the intended recipient stored in `for` or the original
  // publisher `offer_address`.
  // Also fails if no such value exists.
  public fun redeem<Offered: store>(account: &signer, offer_address: address): Offered acquires T {
    let T<Offered> { offered, for } = move_from<T<Offered>>(offer_address);
    let sender = Signer::address_of(account);
    // fail with INSUFFICIENT_PRIVILEGES
    assert(sender == for || sender == offer_address, ERR_INSUFFICIENT_PRIVILEGES);
    offered
  }

  // Returns true if an offer of type `Offered` exists at `offer_address`.
  public fun exists_at<Offered: store>(offer_address: address): bool {
    exists<T<Offered>>(offer_address)
  }

  // Returns the address of the `Offered` type stored at `offer_address.
  // Fails if no such `Offer` exists.
  public fun address_of<Offered: store>(offer_address: address): address acquires T {
    borrow_global<T<Offered>>(offer_address).for
  }
}
}
