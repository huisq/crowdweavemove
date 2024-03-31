module deployer::dao{

    //==============================================================================================
    // Dependencies - DO NOT MODIFY
    //==============================================================================================

    friend deployer::cw;
    use std::string::{Self, String};
    use std::option::{Self};
    use aptos_token_objects::collection::{Self};
    use aptos_framework::account::{Self, SignerCapability};
    use std::signer;
    use aptos_framework::object::{Self};
    use aptos_token_objects::token;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_std::debug;
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
    use std::vector;
    use aptos_std::string_utils;

    //==============================================================================================
    // Constants - DO NOT MODIFY
    //==============================================================================================

    const MAX_U64: u64 = 18446744073709551615;

    const SEED: vector<u8> = b"governance";

    const GOVERNANCE_TOKEN_DESCRIPTION: vector<u8> = b"This governance token is used for voting of the campaign";
    const GOVERNANCE_TOKEN_FUNGIBLE_ASSET_SYMBOL: vector<u8> = b"G$";
    const GOVERNANCE_TOKEN_DECIMALS: u8 = 0;
    const COMMEMORATIVE_NFT_URI: vector<u8> = b"ipfs://bafybeib6itg4r3gadsqnk2acjixctbv6aelyor264sbs63m2tpugw33qui";

    //==============================================================================================
    // Error codes
    //==============================================================================================

    const ERROR_NO_VOTING_POWER: u64 = 0;
    const ERROR_CAMPAIGN_NOT_FINISHED: u64 = 1;


    //==============================================================================================
    // Module Structs
    //==============================================================================================

    /*
        Proposal
    */
    struct Proposal has store{
        milestone: u64,
        is_resolved: bool,
        yes: u64,
        no: u64,
        min_threshold: u64
    }

    struct NftToken has key {
        // Used for editing the token data
        mutator_ref: token::MutatorRef,
        // Used for burning the token
        burn_ref: token::BurnRef,
        // Used for transfering the token
        transfer_ref: object::TransferRef
    }

    /*
        Information to be used in the module
    */
    struct State has key {
        cap: SignerCapability,
        gov_collection_name: vector<u8>,
        gov_token_name: vector<u8>,
        raiser: address,
        //<campaign_obj_add, Proposal>
        proposals: SimpleMap<address, Proposal>,
        //commemorative nft receiver list
        final_backers: vector<address>,
        //commemorative nft minted
        nft_minted: u64
    }

    /*
        The token type for this module's governance token
    */
    struct GovernanceToken has key {
        mint_ref: fungible_asset::MintRef,
        burn_ref: fungible_asset::BurnRef,
    }


    //==============================================================================================
    // Event structs
    //==============================================================================================


    //==============================================================================================
    // Functions
    //==============================================================================================

    /*
    Setting up a new governance for each campaign
    */
    public(friend) fun initialize(
        campaign_obj_signer: &signer,
        gov_collection_name: vector<u8>,
        gov_token_name: vector<u8>,
        gov_token_uri: vector<u8>,
        raiser: address,
    ){
        // Create the resource account using the admin account and the provide SEED constant
        let (resource_signer, resource_cap) = account::create_resource_account(campaign_obj_signer, SEED);

        let state = State{
            cap: resource_cap,
            gov_collection_name,
            gov_token_name,
            raiser,
            proposals: simple_map::new(),
            final_backers: vector::empty(),
            nft_minted: 0
        };
        move_to<State>(campaign_obj_signer, state);

        let gov_token_collection_name = string::utf8(gov_collection_name);
        // Create an unlimited NFT collection for tokens
        collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(GOVERNANCE_TOKEN_DESCRIPTION),
            gov_token_collection_name,
            option::none(),
            string::utf8(gov_token_uri),
        );
        create_governance_token(&resource_signer, gov_collection_name, gov_token_name, gov_token_uri);
        let index = string::index_of(&gov_token_collection_name, &string::utf8(b":")) + 1;
        let campaign_name = string::sub_string(&gov_token_collection_name, index, string::length(&gov_token_collection_name));
        let nft_desc = string::utf8(b"This is a commemorative NFT issued upon the completion of campaign <");
        string::append(&mut nft_desc, campaign_name);
        string::append(&mut nft_desc, string::utf8(b">. Thank you for your support!"));
        // Create an unlimited NFT collection for commemorative NFT
        collection::create_unlimited_collection(
            &resource_signer,
            nft_desc,
            campaign_name,
            option::none(),
            string::utf8(COMMEMORATIVE_NFT_URI),
        );

    }

    /*
        Create a proposal
        @param proposer - signer representing the account who is creating the proposal
        @param execution_hash - A hash of the proposal's execution script module
        @param metadata_location - The location of the proposal's metadata (used by the voting module)
        @param metadata_hash - The hash of the proposal's metadata (used by the voting module)
    */
    public(friend) fun create_proposal(
        campaign_obj_add: address,
        milestone: u64,
        min_threshold: u64
    )acquires State {
        let state = borrow_global_mut<State>(campaign_obj_add);
        if(simple_map::contains_key(&state.proposals, &campaign_obj_add)){
            let proposal = simple_map::borrow_mut(&mut state.proposals, &campaign_obj_add);
            proposal.milestone = milestone;
            proposal.is_resolved = false;
            proposal.yes = 0;
            proposal.no = 0;
            proposal.min_threshold = min_threshold;
        }else{
            let proposal = Proposal{
                milestone,
                is_resolved: false,
                yes: 0,
                no: 0,
                min_threshold
            };
            simple_map::add(&mut state.proposals, campaign_obj_add, proposal);
        };
    }

    /*
        Vote for a specific proposal
        @param voter - signer representing the account who is voting
        @param proposal_id - The id of the proposal to vote for
        @param should_pass - Whether the voter wants the proposal to pass or not
    */
    public(friend) fun vote (
        voter: &signer,
        should_pass: bool,
        campaign_obj_add: address,
        milestone: u64,
    ) acquires State {
        let voter_address = signer::address_of(voter);
        let voting_power = user_gov_token_balance(voter_address, campaign_obj_add);
        let state = borrow_global_mut<State>(campaign_obj_add);
        let proposal = simple_map::borrow_mut(&mut state.proposals, &campaign_obj_add);
        assert!(voting_power > 0, ERROR_NO_VOTING_POWER);
        if(should_pass){
            proposal.yes = proposal.yes + voting_power;
        }else{
            proposal.no = proposal.no + voting_power;
        };
        if(milestone == 4){
            vector::push_back(&mut state.final_backers, voter_address);
        };
    }

    public(friend) fun resolve_proposal(campaign_obj_add: address): bool acquires State{
        let state = borrow_global_mut<State>(campaign_obj_add);
        let proposal = simple_map::borrow_mut(&mut state.proposals, &campaign_obj_add);
        if(proposal.yes >= proposal.min_threshold){
            proposal.is_resolved = true;
        };
        proposal.is_resolved
    }

    public(friend) fun mint_fungible_token(
        amount: u64,
        buyer_address: address,
        campaign_obj_add: address
    ) acquires GovernanceToken, State {
        let state = borrow_global<State>(campaign_obj_add);
        let acc_token = borrow_global<GovernanceToken>(
            get_gov_token_address(
                campaign_obj_add,
                state.gov_collection_name,
                state.gov_token_name
            ));
        let minted_token = fungible_asset::mint(&acc_token.mint_ref,amount);
        primary_fungible_store::deposit(buyer_address, minted_token);
    }

    public(friend) fun distribute_NFT(
        campaign_obj_add: address,
        campaign_name: String,
    ) acquires State, GovernanceToken {
        let final_backers;
        {
            let state = borrow_global_mut<State>(campaign_obj_add);
            let proposal = simple_map::borrow_mut(&mut state.proposals, &campaign_obj_add);
            assert!(proposal.milestone == 4 && proposal.is_resolved == true, ERROR_CAMPAIGN_NOT_FINISHED);
            final_backers = state.final_backers;
        };
        let i = 0;
        while(i < vector::length(&final_backers)){
            let owner_address = *vector::borrow(&final_backers, i);
            mint_NFT_token_internal(owner_address, campaign_obj_add, campaign_name);
            burn_fungible_token(owner_address, campaign_obj_add);
            i = i + 1;
        };

    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================
    /*
        Create the fungible governance token
        @param creator - signer representing the creator of the collection
    */
    inline fun create_governance_token(
        creator: &signer,
        gov_collection_name: vector<u8>,
        gov_token_name: vector<u8>,
        gov_token_uri: vector<u8>,
    ) {
        // Create a new named token
        let token_constructor_ref = token::create_named_token(
            creator,
            string::utf8(gov_collection_name),
            string::utf8(GOVERNANCE_TOKEN_DESCRIPTION),
            string::utf8(gov_token_name),
            option::none(),
            string::utf8(gov_token_uri)
        );

        let obj_signer = object::generate_signer(&token_constructor_ref);

        // Create a fungible asset for the gov token with the following aspects:
        //          - max supply: no max supply
        //          - name: FOOD_TOKEN_DESCRFOOD_TOKEN_FUNGIBLE_ASSET_NAMEIPTION
        //          - symbol: FOOD_TOKEN_FUNGIBLE_ASSET_SYMBOL
        //          - decimals: FOOD_TOKEN_DECIMALS
        //          - icon uri: FOOD_TOKEN_ICON_URI
        //          - project uri: FOOD_TOKEN_PROJECT_URI
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &token_constructor_ref,
            option::none(),
            string::utf8(gov_token_name),
            string::utf8(GOVERNANCE_TOKEN_FUNGIBLE_ASSET_SYMBOL),
            GOVERNANCE_TOKEN_DECIMALS,
            string::utf8(gov_token_uri),
            string::utf8(gov_token_uri)
        );

        // Create a new GovToken object and move it to the token's object signer
        let new_acc_token = GovernanceToken{
            mint_ref: fungible_asset::generate_mint_ref(&token_constructor_ref),
            burn_ref: fungible_asset::generate_burn_ref(&token_constructor_ref),
        };

        move_to(&obj_signer,new_acc_token);
    }

    inline fun burn_fungible_token(
        owner_address: address,
        campaign_obj_add: address
    ) acquires GovernanceToken, State {
        let amount = user_gov_token_balance(owner_address, campaign_obj_add);
        let state = borrow_global<State>(campaign_obj_add);
        let token_address = get_gov_token_address(campaign_obj_add, state.gov_collection_name, state.gov_token_name);
        let acc_token = borrow_global<GovernanceToken>(token_address);
        let acc_token_obj = object::address_to_object<GovernanceToken>(token_address);
        let metadata_obj = object::convert<GovernanceToken, Metadata>(acc_token_obj);
        let store = primary_fungible_store::primary_store(
            owner_address,
            metadata_obj
        );
        fungible_asset::burn_from(&acc_token.burn_ref, store, amount);
    }

    inline fun mint_NFT_token_internal(
        owner_address: address,
        campaign_obj_add: address,
        campaign_name: String
    ) acquires State {
        let state = borrow_global_mut<State>(campaign_obj_add);
        let res_signer = account::create_signer_with_capability(&state.cap);
        let token_name = campaign_name;
        let no = string_utils::format1(&b"#{}",state.nft_minted);
        string::append(&mut token_name, no);
        let token_const_ref = token::create_named_token(
            &res_signer,
            campaign_name,
            string::utf8(b"Thank you for your support!"),
            token_name,
            option::none(),
            string::utf8(COMMEMORATIVE_NFT_URI)
        );

        let obj_signer = object::generate_signer(&token_const_ref);
        let obj_add = object::address_from_constructor_ref(&token_const_ref);

        // Transfer the token to the reviewer account
        object::transfer_raw(&res_signer, obj_add, owner_address);

        // Create the ReviewToken object and move it to the new token object signer
        let new_nft_token = NftToken {
            mutator_ref: token::generate_mutator_ref(&token_const_ref),
            burn_ref: token::generate_burn_ref(&token_const_ref),
            transfer_ref: object::generate_transfer_ref(&token_const_ref),
        };

        move_to<NftToken>(&obj_signer, new_nft_token);
        state.nft_minted = state.nft_minted + 1;
    }

    /*
    Retrieves the address of this module's resource account
*/
    inline fun get_resource_account_address(campaign_obj_add: address): address {
        account::create_resource_address(&campaign_obj_add, SEED)
    }

    inline fun get_gov_token_address(
        campaign_obj_add: address,
        gov_collection_name: vector<u8>,
        gov_token_name: vector<u8>,
    ): address {
        // Return the address of the gov token
        token::create_token_address(
            &get_resource_account_address(campaign_obj_add),
            &string::utf8(gov_collection_name),
            &string::utf8(gov_token_name)
        )
    }


    //==============================================================================================
    // View functions
    //==============================================================================================

    #[view]
    public fun user_gov_token_balance(
        owner_addr: address,
        campaign_obj_add: address,
    ): u64 acquires State{
        let state = borrow_global<State>(campaign_obj_add);
        let acc_token_obj = object::address_to_object<GovernanceToken>(
            get_gov_token_address(
                campaign_obj_add,
                state.gov_collection_name,
                state.gov_token_name
            ));
        let metadata_obj = object::convert<GovernanceToken, Metadata>(acc_token_obj);
        let store = primary_fungible_store::ensure_primary_store_exists(owner_addr, metadata_obj);
        fungible_asset::balance(store)
    }

    #[view]
    public fun how_many_more_votes_required(
        campaign_obj_add: address,
    ): u64 acquires State{
        let state = borrow_global<State>(campaign_obj_add);
        let proposal = simple_map::borrow(&state.proposals, &campaign_obj_add);
        if(proposal.yes + proposal.no >= proposal.min_threshold){
            0
        }else{
            proposal.min_threshold - (proposal.yes + proposal.no)
        }
    }

}