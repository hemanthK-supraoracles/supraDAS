module CAFE::danft_example {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::option;
    use supra_framework::event::{Self, EventHandle};
    use supra_framework::account;
    use supra_framework::timestamp;
    use 0x4::collection;
    use 0x4::token::{Self, Token};
    use 0x1::object::{Self, Object};
    use aptos_token_objects::token::{BurnRef};

    // Error codes
    const E_ALREADY_MINTED: u64 = 1;
    const E_NOT_AUTHORIZED: u64 = 2;
    const E_TOKEN_NOT_FOUND: u64 = 3;

    // Struct to store collection metadata
    struct CollectionMetadata has key {
        creation_timestamp_secs: u64,
        mint_event_handle: EventHandle<MintEvent>,
        transfer_event_handle: EventHandle<TransferEvent>,
        burn_event_handle: EventHandle<BurnEvent>
    }

    struct CustomData has key, drop {
        burn_ref: BurnRef
    }

    // Struct to track which addresses have minted
    struct MintTracker has key {
        minted_addresses: vector<address>
    }

    // Event structs
    struct MintEvent has drop, store {
        token_name: String,
        receiver: address,
        timestamp: u64
    }

    struct TransferEvent has drop, store {
        token_name: String,
        from: address,
        to: address,
        timestamp: u64
    }

    struct BurnEvent has drop, store {
        token_name: String,
        owner: address,
        timestamp: u64
    }

    // Initialize the collection and necessary resources
    public entry fun initialize_collection(creator: &signer) {
        let creator_addr = signer::address_of(creator);

        // Create an unlimited collection
        let collection_constructor_ref =
            collection::create_unlimited_collection(
                creator,
                string::utf8(b"My NFT Collection Description"),
                string::utf8(b"My NFT Collection"),
                option::none(),
                string::utf8(b"https://mycollection.com")
            );

        // Create collection signer and add metadata
        let collection_signer = object::generate_signer(&collection_constructor_ref);
        move_to(
            &collection_signer,
            CollectionMetadata {
                creation_timestamp_secs: timestamp::now_seconds(),
                mint_event_handle: account::new_event_handle<MintEvent>(creator),
                transfer_event_handle: account::new_event_handle<TransferEvent>(creator),
                burn_event_handle: account::new_event_handle<BurnEvent>(creator)
            }
        );

        // Initialize mint tracker if it doesn't exist
        if (!exists<MintTracker>(creator_addr)) {
            move_to(creator, MintTracker { minted_addresses: vector::empty() });
        };
    }

    // Mint an NFT with a check for one-per-wallet
    public entry fun mint_nft(
        creator: &signer,
        receiver: address,
        name: String,
        description: String,
        uri: String
    ) acquires CollectionMetadata, MintTracker {
        let creator_addr = signer::address_of(creator);
        let tracker = borrow_global_mut<MintTracker>(creator_addr);

        // Check if receiver has already minted
        assert!(
            !vector::contains(&tracker.minted_addresses, &receiver),
            error::already_exists(E_ALREADY_MINTED)
        );

        // Mint the NFT
        let token_constructor_ref =
            token::create(
                creator,
                string::utf8(b"My NFT Collection"),
                name,
                description,
                option::none(),
                uri
            );

        let token_signer = &object::generate_signer(&token_constructor_ref);
        let burn_ref = token::generate_burn_ref(&token_constructor_ref);

        // Store the burn ref somewhere safe
        move_to(token_signer, CustomData { burn_ref });

        // Transfer to receiver
        let token_obj =
            object::object_from_constructor_ref<token::Token>(&token_constructor_ref);
        object::transfer(creator, token_obj, receiver);

        // Update mint tracker
        vector::push_back(&mut tracker.minted_addresses, receiver);

        // Emit mint event
        let collection_addr =
            collection::create_collection_address(
                &creator_addr, &string::utf8(b"My NFT Collection")
            );
        // let collection_signer = object::generate_signer_for_object(&collection_addr);
        let metadata = borrow_global_mut<CollectionMetadata>(collection_addr);
        event::emit_event(
            &mut metadata.mint_event_handle,
            MintEvent { token_name: name, receiver, timestamp: timestamp::now_seconds() }
        );
    }

    // Transfer an NFT
    public entry fun transfer_nft(
        sender: &signer, token_addr: address, receiver: address
    ) acquires CollectionMetadata {
        let sender_addr = signer::address_of(sender);
        let token_obj = object::address_to_object<token::Token>(token_addr);

        // Verify sender owns the token
        assert!(
            object::is_owner(token_obj, sender_addr),
            error::permission_denied(E_NOT_AUTHORIZED)
        );

        // Perform transfer
        object::transfer(sender, token_obj, receiver);

        // Emit transfer event
        let collection_addr =
            collection::create_collection_address(
                &signer::address_of(sender), &string::utf8(b"My NFT Collection")
            );
        let metadata = borrow_global_mut<CollectionMetadata>(collection_addr);
        event::emit_event(
            &mut metadata.transfer_event_handle,
            TransferEvent {
                token_name: token::name(token_obj),
                from: sender_addr,
                to: receiver,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    // Burn an NFT
    public entry fun burn_nft(
        owner: &signer, token: Object<Token>, collection_owner: address,
    ) acquires CollectionMetadata, CustomData {
        let owner_addr = signer::address_of(owner);
        let token_address = object::object_address(&token);

        let token_name = token::name(token);

        // Verify owner
        assert!(
            object::is_owner(token, owner_addr),
            error::permission_denied(E_NOT_AUTHORIZED)
        );

        // Retrieve the burn ref from storage
        let CustomData { burn_ref } = move_from<CustomData>(token_address);
        // Burn the token
        token::burn(burn_ref);

        // Emit burn event
        let collection_addr =
            collection::create_collection_address(
                &collection_owner, &string::utf8(b"My NFT Collection")
            );
        let metadata = borrow_global_mut<CollectionMetadata>(collection_addr);
        event::emit_event(
            &mut metadata.burn_event_handle,
            BurnEvent {
                token_name,
                owner: owner_addr,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    // View function to check if an address has minted
    #[view]
    public fun has_minted(creator_addr: address, user_addr: address): bool acquires MintTracker {
        if (!exists<MintTracker>(creator_addr)) {
            return false
        };
        let tracker = borrow_global<MintTracker>(creator_addr);
        vector::contains(&tracker.minted_addresses, &user_addr)
    }
}
