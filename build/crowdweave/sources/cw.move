module deployer::cw {

    //==============================================================================================
    // Dependencies
    //==============================================================================================

    use deployer::dao;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::account::{Self, SignerCapability};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_token_objects::collection::{Self};
    use aptos_token_objects::token;
    use aptos_framework::object;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::string_utils;
    use std::bcs;
    use aptos_std::debug;

    #[test_only]
    use aptos_framework::aptos_coin::{Self};

    //==============================================================================================
    // Errors
    //==============================================================================================

    const ERROR_SIGNER_NOT_RAISER: u64 = 0;
    const ERROR_OTHER: u64 = 1;
    const ERROR_CAMPAIGN_HAS_STARTED: u64 = 2;
    const ERROR_CAMPAIGN_NOT_STARTED: u64 = 3;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 4;
    const ERROR_USER_ALREADY_VOTED: u64 = 5;
    const ERROR_INCOMPLETED_MILESTONES_REMAINED: u64 = 6;
    const ERROR_NOT_RESOLVED: u64 = 7;
    const ERROR_NOT_FUNDED: u64 = 8;
    const ERROR_VOTING_NOT_STARTED: u64 = 9;
    const ERROR_USER_ALREADY_JOINED_CAMPAIGN: u64 = 10;
    const ERROR_NOT_MORE_THAN_HALF_VOTED: u64 = 11;

    //==============================================================================================
    // Constants
    //==============================================================================================

    const SEED: vector<u8> = b"cw";
    const GENERAL_COLLECTION_NAME: vector<u8> = b"Campaign collection";
    const CAMPAIGN_DESCRIPTION: vector<u8> = b"Campaign description";
    const CAMPAIGN_URI: vector<u8> = b"governance token uri"; //todo: replace

    //==============================================================================================
    // Module Structs
    //==============================================================================================

    /*
    Custom Information to be used in the game
*/
    struct Campaign has key {
        cap: SignerCapability,
        campaign_name: String,
        token_name: String,
        token_uri: String,
        min_entry_price: u64,
        unit_price: u64,
        start_time: u64,
        target: u64,
        //details of each milestone
        milestones: vector<String>,
        // votes of each milestone
        votes: vector<MilestoneVotes>,
        //proof of milestone completion
        proof: vector<String>,
        //backer, amount
        backer: SimpleMap<address, u64>,
        backer_add: vector<address>,
        total_supply: u64,
        campaign_started_bool: bool,
        campaign_completed_bool: bool,
        cancel_campaign_bool: bool,
        // Events
        join_campaign_events: u64,
        vote_events: u64,
        milestone_completed_events: u64
    }

    /*
    Information to be used in the module
*/
    struct State has key {
        cap: SignerCapability,
        // <campaign object address, owner address>
        campaigns: SimpleMap<address, address>,
        // Events
        campaign_created_events: u64,
    }

    struct MilestoneVotes has store, copy, drop{
        voted: vector<address>,
    }

    //==============================================================================================
    // Event structs
    //==============================================================================================
    #[event]
    struct JoinCampaignEvent has store, drop {
        // user
        user: address,
        entry_sum: u64,
        // timestamp
        timestamp: u64
    }

    #[event]
    struct VotedEvent has store, drop {
        user: address,
        milestone: u64,
        // timestamp
        timestamp: u64
    }

    #[event]
    struct MilestoneCompletedEvent has store, drop {
        milestone: u64,
        // timestamp
        timestamp: u64
    }

    #[event]
    struct MilestoneFailedEvent has store, drop {
        milestone: u64,
        // timestamp
        timestamp: u64
    }


    //==============================================================================================
    // Functions
    //==============================================================================================

    fun init_module(deployer: &signer) {
        let (resource_signer, resource_cap) = account::create_resource_account(deployer, SEED);
        collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(CAMPAIGN_DESCRIPTION),
            string::utf8(GENERAL_COLLECTION_NAME),
            option::none(),
            string::utf8(CAMPAIGN_URI),
        );
        // Create the State global resource and move it to the admin account
        let state = State{
            cap: resource_cap,
            campaigns: simple_map::new(),
            campaign_created_events: 0,
        };
        move_to<State>(deployer, state);
    }

    // create campaign
    public entry fun create_campaign(
        raiser: &signer,
        campaign_name: String,
        start_time: u64,
        min_entry_price: u64,
        unit_price: u64,
        token_name: String,
        token_uri: String,
        target: u64,
        m1: String,
        m2: String,
        m3: String,
        m4: String
    ) acquires State {
        let state = borrow_global_mut<State>(@deployer);
        let campaign_collection_name = string_utils::format1(&b"Campaign#{}:",state.campaign_created_events);
        let (resource_signer, resource_cap) = account::create_resource_account(raiser, bcs::to_bytes(&timestamp::now_seconds()));
        coin::register<AptosCoin>(&resource_signer);
        let campaign = Campaign {
            cap: resource_cap,
            campaign_name,
            token_name,
            token_uri,
            min_entry_price,
            unit_price,
            start_time,
            target,
            milestones: vector[m1,m2,m3,m4],
            votes: vector::empty(),
            proof: vector::empty(),
            backer: simple_map::new(),
            backer_add: vector::empty(),
            total_supply: 0,
            campaign_started_bool: false,
            campaign_completed_bool: false,
            cancel_campaign_bool: false,
            join_campaign_events: 0,
            vote_events: 0,
            milestone_completed_events: 0
        };
        string::append(&mut campaign_collection_name, campaign_name);
        let token_constructor_ref = token::create_named_token(
            &account::create_signer_with_capability(&state.cap),
            string::utf8(GENERAL_COLLECTION_NAME),
            string::utf8(CAMPAIGN_DESCRIPTION),
            campaign_collection_name,
            option::none(),
            token_uri
        );
        let obj_signer = object::generate_signer(&token_constructor_ref);
        move_to(&obj_signer, campaign);
        simple_map::add(&mut state.campaigns, signer::address_of(&obj_signer), signer::address_of(raiser));
        assert_enough_apt(signer::address_of(raiser), target*20/100);
        coin::transfer<AptosCoin>(raiser, signer::address_of(&resource_signer), target*20/100);
        dao::initialize(
            &obj_signer,
            *string::bytes(&campaign_collection_name),
            *string::bytes(&token_name),
            *string::bytes(&token_uri),
            signer::address_of(raiser)
        );
        state.campaign_created_events = state.campaign_created_events +1;
    }

    // front-end needs to set the min_entry_price & unit_price according to the one set in create_campaign
    public entry fun join_campaign(
        user: &signer,
        entry_sum: u64,
        campaign_obj_add: address,
    ) acquires Campaign {
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        assert_campaign_not_started(campaign.campaign_started_bool);
        let user_add = signer::address_of(user);
        assert_enough_apt(user_add, entry_sum);
        // Payment
        let resource_signer = &account::create_signer_with_capability(&campaign.cap);
        coin::transfer<AptosCoin>(user, signer::address_of(resource_signer), entry_sum);

        vector::push_back(&mut campaign.backer_add, user_add);
        simple_map::add(&mut campaign.backer, user_add, entry_sum);
        campaign.total_supply = campaign.total_supply + entry_sum;
        event::emit(JoinCampaignEvent {
            user: user_add,
            entry_sum,
            timestamp: timestamp::now_seconds()
        });
        campaign.join_campaign_events = campaign.join_campaign_events + 1;
    }

    public entry fun start_campaign(raiser: &signer, campaign_obj_add: address) acquires State, Campaign{
        let state = borrow_global_mut<State>(@deployer);
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        assert_campaign_not_started(campaign.campaign_started_bool);
        assert_raiser(campaign_obj_add, signer::address_of(raiser), state.campaigns);
        assert_ready_to_start(campaign.target, campaign.total_supply);
        campaign.campaign_started_bool = true;
        let i = 0;
        while(i < vector::length(&campaign.backer_add)){
            let user_add = *vector::borrow(&campaign.backer_add, i);
            let entry_sum= *simple_map::borrow(&campaign.backer, &user_add);
            dao::mint_fungible_token(entry_sum, user_add, campaign_obj_add);
            i = i + 1;
        };
    }

    public entry fun milestone_completion_proposal(
        raiser: &signer,
        campaign_obj_add: address,
        milestone: u64, // milestone 1,2,3,4
        proof: String,
    ) acquires State, Campaign{
        let state = borrow_global_mut<State>(@deployer);
        assert_raiser(campaign_obj_add, signer::address_of(raiser), state.campaigns);
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        assert_campaign_started(campaign.campaign_started_bool);
        if(vector::length(&campaign.votes) == milestone && campaign.milestone_completed_events == milestone-1){
            vector::pop_back(&mut campaign.votes);
        };
        vector::push_back(&mut campaign.votes, MilestoneVotes {voted: vector::empty()});

        let min_vote_threshold = campaign.total_supply/2 + campaign.total_supply%2;
        dao::create_proposal(campaign_obj_add, milestone, min_vote_threshold);
        vector::push_back(&mut campaign.proof, proof);
    }

    public entry fun vote_proposal(
        user: &signer,
        campaign_obj_add: address,
        milestone: u64, // milestone 1,2,3,4
        should_pass: bool
    ) acquires Campaign{
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        assert_campaign_started(campaign.campaign_started_bool);
        assert_voting_started(campaign.votes, milestone);
        assert_not_voted(vector::borrow(&campaign.votes, milestone-1).voted, signer::address_of(user));
        dao::vote(user, should_pass, campaign_obj_add, milestone);
        vector::push_back(&mut vector::borrow_mut(&mut campaign.votes, milestone-1).voted, signer::address_of(user));
        event::emit(VotedEvent {
            user: signer::address_of(user),
            milestone,
            timestamp: timestamp::now_seconds()
        });
        campaign.vote_events = campaign.vote_events + 1;
    }

    
    public entry fun conclude_milestone(raiser: &signer, campaign_obj_add: address, milestone: u64) acquires State, Campaign{
        let state = borrow_global_mut<State>(@deployer);
        assert_raiser(campaign_obj_add, signer::address_of(raiser), state.campaigns);
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        assert_more_than_half_voted(dao::how_many_more_votes_required(campaign_obj_add));
        if(dao::resolve_proposal(campaign_obj_add)){
            event::emit(MilestoneCompletedEvent {
                milestone,
                timestamp: timestamp::now_seconds()
            });
            campaign.milestone_completed_events = campaign.milestone_completed_events + 1;
            let resource_signer = &account::create_signer_with_capability(&campaign.cap);
            coin::transfer<AptosCoin>(resource_signer, @raiser, campaign.target/4);
        };
        event::emit(MilestoneFailedEvent {
            milestone,
            timestamp: timestamp::now_seconds()
        });

    }

    public entry fun conclude_campaign(raiser: &signer, campaign_obj_add: address) acquires State, Campaign{
        let state = borrow_global_mut<State>(@deployer);
        assert_raiser(campaign_obj_add, signer::address_of(raiser), state.campaigns);
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        let resource_signer = &account::create_signer_with_capability(&campaign.cap);
        assert_all_milestones_completed( campaign.milestone_completed_events);
        campaign.campaign_completed_bool = true;
        dao::distribute_NFT(campaign_obj_add, campaign.campaign_name);
        coin::transfer<AptosCoin>(resource_signer, signer::address_of(raiser), campaign.target*18/100);
        coin::transfer<AptosCoin>(resource_signer, @treasury, coin::balance<AptosCoin>(signer::address_of(resource_signer)));
    }

    public entry fun cancel_campaign(raiser: &signer, campaign_obj_add: address) acquires State, Campaign{
        let state = borrow_global_mut<State>(@deployer);
        assert_raiser(campaign_obj_add, signer::address_of(raiser), state.campaigns);
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        let resource_signer = &account::create_signer_with_capability(&campaign.cap);
        assert_campaign_not_started(campaign.campaign_started_bool);
        let i = 0;
        while(i < vector::length(&campaign.backer_add)){
            let user_add = *vector::borrow(&campaign.backer_add, i);
            let entry_sum= *simple_map::borrow(&campaign.backer, &user_add);
            coin::transfer<AptosCoin>(resource_signer, user_add, entry_sum);
            i = i + 1;
        };
        coin::transfer<AptosCoin>(resource_signer, signer::address_of(raiser), campaign.target*18/100);
        coin::transfer<AptosCoin>(resource_signer, @treasury, coin::balance<AptosCoin>(signer::address_of(resource_signer)));
        campaign.cancel_campaign_bool = true;
    }
    //==============================================================================================
    // Helper functions
    //==============================================================================================


    //==============================================================================================
    // View functions
    //==============================================================================================

    #[view]
    public fun is_voting_open(campaign_obj_add: address):bool acquires Campaign {
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        campaign.campaign_started_bool && !campaign.campaign_completed_bool
    }

    #[view]
    public fun get_collection_address(): address acquires State {
        let state = borrow_global_mut<State>(@deployer);
        collection::create_collection_address(
            &signer::address_of(&account::create_signer_with_capability(&state.cap)),
            &string::utf8(GENERAL_COLLECTION_NAME)
        )
    }

    #[view]
    public fun get_milestones_details(campaign_obj_add: address): vector<String> acquires Campaign {
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        campaign.milestones
    }

    #[view]
    public fun get_proof(campaign_obj_add: address): vector<String> acquires Campaign {
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        campaign.proof
    }

    #[view]
    public fun get_campaign_vals(campaign_obj_add: address): vector<u64> acquires Campaign {
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        vector[campaign.start_time, campaign.min_entry_price, campaign.unit_price, campaign.target, campaign.total_supply]
    }

    #[view]
    public fun get_no_completed_milestones(campaign_obj_add: address): u64 acquires Campaign {
        let campaign = borrow_global_mut<Campaign>(campaign_obj_add);
        campaign.milestone_completed_events
    }

    //==============================================================================================
    // Validation functions
    //==============================================================================================

    inline fun assert_raiser(obj_add: address, owner: address, campaigns: SimpleMap<address, address>) {
        assert!(*simple_map::borrow(&campaigns, &obj_add) == owner, ERROR_SIGNER_NOT_RAISER);
    }

    inline fun assert_campaign_not_started(started: bool) {
        assert!(!started, ERROR_CAMPAIGN_HAS_STARTED);
    }

    inline fun assert_campaign_started(started: bool) {
        assert!(started, ERROR_CAMPAIGN_NOT_STARTED);
    }

    inline fun assert_enough_apt(user: address, entry_sum: u64) {
        assert!(coin::balance<AptosCoin>(user) >= entry_sum, ERROR_INSUFFICIENT_BALANCE);
    }

    inline fun assert_not_voted(voted_list: vector<address>, user: address) {
        assert!(!vector::contains(&voted_list, &user), ERROR_USER_ALREADY_VOTED);
    }

    inline fun assert_all_milestones_completed(completed: u64) {
        assert!(completed == 4, ERROR_INCOMPLETED_MILESTONES_REMAINED);
    }

    inline fun assert_ready_to_start(target: u64, sum: u64) {
        assert!(sum >= target, ERROR_NOT_FUNDED);
    }

    inline fun assert_voting_started(votes: vector<MilestoneVotes>, milestone: u64) {
        assert!(vector::length(&votes) == milestone, ERROR_VOTING_NOT_STARTED);
    }

    inline fun assert_user_not_joined(backers: vector<address>, user: address) {
        assert!(!vector::contains(&backers, &user), ERROR_USER_ALREADY_JOINED_CAMPAIGN);
    }

    inline fun assert_more_than_half_voted(remaining_required_votes: u64) {
        assert!(remaining_required_votes == 0, ERROR_NOT_MORE_THAN_HALF_VOTED);
    }
    //==============================================================================================
    // Test functions
    //==============================================================================================

    #[test(deployer = @deployer)]
    fun test_init_module_success(
        deployer: &signer
    ) {
        let deployer_address = signer::address_of(deployer);
        account::create_account_for_test(deployer_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(deployer);

        assert!(exists<State>(deployer_address),0);
    }

    #[test(deployer = @deployer, raiser = @raiser, user = @0xA)]
    fun test_join_campaign_success(
        deployer: &signer,
        raiser: &signer,
        user: &signer,
    ) acquires State, Campaign {
        let deployer_address = signer::address_of(deployer);
        let raiser_address = signer::address_of(raiser);
        let user_address = signer::address_of(user);
        account::create_account_for_test(deployer_address);
        account::create_account_for_test(raiser_address);
        account::create_account_for_test(user_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(raiser);
        coin::register<AptosCoin>(user);
        let min_entry_price = 10000000; //0.1APT
        aptos_coin::mint(&aptos_framework, raiser_address, min_entry_price*20/100);
        aptos_coin::mint(&aptos_framework, user_address, min_entry_price);
        init_module(deployer);

        let campaign_name = string::utf8(b"test");
        let unit_price = 10000000; //0.1APT
        let token_name = string::utf8(b"test_token");
        let token_uri = string::utf8(b"test_token_uri");
        let target = 10000000; //0.1APT
        let m1 = string::utf8(b"m1");
        let m2 = string::utf8(b"m2");
        let m3 = string::utf8(b"m3");
        let m4 = string::utf8(b"m4");
        create_campaign(
            raiser,
            campaign_name,
            timestamp::now_seconds(),
            min_entry_price,
            unit_price,
            token_name,
            token_uri,
            target,
            m1,
            m2,
            m3,
            m4
        );

        let name = string::utf8(b"Campaign#0:");
        let resource_account_address = account::create_resource_address(&deployer_address, SEED);
        string::append(&mut name, campaign_name);
        let expected_campaign_obj_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(GENERAL_COLLECTION_NAME),
            &name
        );
        join_campaign(user, min_entry_price, expected_campaign_obj_address);

        let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
        assert!(campaign.join_campaign_events == 1, 1);
        assert!(campaign.total_supply == target, 1);
        assert!(vector::length(&campaign.backer_add) == 1, 1);
        assert!(vector::contains(&campaign.backer_add, &user_address), 1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer, raiser = @raiser, user = @0xA)]
    fun test_start_campaign_success(
        deployer: &signer,
        raiser: &signer,
        user: &signer,
    ) acquires State, Campaign {
        let deployer_address = signer::address_of(deployer);
        let raiser_address = signer::address_of(raiser);
        let user_address = signer::address_of(user);
        account::create_account_for_test(deployer_address);
        account::create_account_for_test(raiser_address);
        account::create_account_for_test(user_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(raiser);
        coin::register<AptosCoin>(user);
        let min_entry_price = 10000000; //0.1APT
        aptos_coin::mint(&aptos_framework, raiser_address, min_entry_price*20/100);
        aptos_coin::mint(&aptos_framework, user_address, min_entry_price);
        init_module(deployer);

        let campaign_name = string::utf8(b"test");
        let unit_price = 10000000; //0.1APT
        let token_name = string::utf8(b"test_token");
        let token_uri = string::utf8(b"test_token_uri");
        let target = 10000000; //0.1APT
        let m1 = string::utf8(b"m1");
        let m2 = string::utf8(b"m2");
        let m3 = string::utf8(b"m3");
        let m4 = string::utf8(b"m4");
        create_campaign(
            raiser,
            campaign_name,
            timestamp::now_seconds(),
            min_entry_price,
            unit_price,
            token_name,
            token_uri,
            target,
            m1,
            m2,
            m3,
            m4
        );


        let name = string::utf8(b"Campaign#0:");
        let resource_account_address = account::create_resource_address(&deployer_address, SEED);
        string::append(&mut name, campaign_name);
        let expected_campaign_obj_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(GENERAL_COLLECTION_NAME),
            &name
        );
        join_campaign(user, min_entry_price, expected_campaign_obj_address);
        start_campaign(raiser, expected_campaign_obj_address);

        let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
        assert!(campaign.campaign_started_bool, 1);
        assert!(dao::user_gov_token_balance(user_address, expected_campaign_obj_address) == min_entry_price, 1);
        let res_signer = account::create_signer_with_capability(&campaign.cap);
        assert!(coin::balance<AptosCoin>(signer::address_of(&res_signer)) == min_entry_price + min_entry_price*20/100, 1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer, raiser = @raiser, treasury = @treasury, user = @0xA)]
    fun test_cancel_campaign_success(
        deployer: &signer,
        raiser: &signer,
        treasury: &signer,
        user: &signer,
    ) acquires State, Campaign {
        let deployer_address = signer::address_of(deployer);
        let raiser_address = signer::address_of(raiser);
        let treasury_address = signer::address_of(treasury);
        let user_address = signer::address_of(user);
        account::create_account_for_test(deployer_address);
        account::create_account_for_test(raiser_address);
        account::create_account_for_test(treasury_address);
        account::create_account_for_test(user_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(raiser);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(treasury);
        let min_entry_price = 10000000; //0.1APT
        aptos_coin::mint(&aptos_framework, raiser_address, min_entry_price*20/100);
        aptos_coin::mint(&aptos_framework, user_address, min_entry_price);
        init_module(deployer);

        let campaign_name = string::utf8(b"test");
        let unit_price = 10000000; //0.1APT
        let token_name = string::utf8(b"test_token");
        let token_uri = string::utf8(b"test_token_uri");
        let target = 10000000; //0.1APT
        let m1 = string::utf8(b"m1");
        let m2 = string::utf8(b"m2");
        let m3 = string::utf8(b"m3");
        let m4 = string::utf8(b"m4");
        create_campaign(
            raiser,
            campaign_name,
            timestamp::now_seconds(),
            min_entry_price,
            unit_price,
            token_name,
            token_uri,
            target,
            m1,
            m2,
            m3,
            m4
        );


        let name = string::utf8(b"Campaign#0:");
        let resource_account_address = account::create_resource_address(&deployer_address, SEED);
        string::append(&mut name, campaign_name);
        let expected_campaign_obj_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(GENERAL_COLLECTION_NAME),
            &name
        );
        join_campaign(user, min_entry_price, expected_campaign_obj_address);
        cancel_campaign(raiser, expected_campaign_obj_address);

        let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
        assert!(campaign.cancel_campaign_bool, 1);
        assert!(coin::balance<AptosCoin>(raiser_address) == target*18/100, 1);
        assert!(coin::balance<AptosCoin>(treasury_address) == target*2/100, 1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer, raiser = @raiser, user = @0xA)]
    fun test_vote_success(
        deployer: &signer,
        raiser: &signer,
        user: &signer,
    ) acquires State, Campaign {
        let deployer_address = signer::address_of(deployer);
        let raiser_address = signer::address_of(raiser);
        let user_address = signer::address_of(user);
        account::create_account_for_test(deployer_address);
        account::create_account_for_test(raiser_address);
        account::create_account_for_test(user_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(raiser);
        coin::register<AptosCoin>(user);
        let min_entry_price = 10000000; //0.1APT
        aptos_coin::mint(&aptos_framework, raiser_address, min_entry_price*20/100);
        aptos_coin::mint(&aptos_framework, user_address, min_entry_price);
        init_module(deployer);

        let campaign_name = string::utf8(b"test");
        let unit_price = 10000000; //0.1APT
        let token_name = string::utf8(b"test_token");
        let token_uri = string::utf8(b"test_token_uri");
        let target = 10000000; //0.1APT
        let m1 = string::utf8(b"m1");
        let m2 = string::utf8(b"m2");
        let m3 = string::utf8(b"m3");
        let m4 = string::utf8(b"m4");
        create_campaign(
            raiser,
            campaign_name,
            timestamp::now_seconds(),
            min_entry_price,
            unit_price,
            token_name,
            token_uri,
            target,
            m1,
            m2,
            m3,
            m4
        );


        let name = string::utf8(b"Campaign#0:");
        let resource_account_address = account::create_resource_address(&deployer_address, SEED);
        string::append(&mut name, campaign_name);
        let expected_campaign_obj_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(GENERAL_COLLECTION_NAME),
            &name
        );
        join_campaign(user, min_entry_price, expected_campaign_obj_address);
        start_campaign(raiser, expected_campaign_obj_address);
        let proof = string::utf8(b"proof");
        milestone_completion_proposal(raiser, expected_campaign_obj_address, 1, proof);
        vote_proposal(user, expected_campaign_obj_address, 1,true);

        let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
        assert!(campaign.vote_events == 1, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer, raiser = @raiser, treasury = @treasury, user = @0xA)]
    fun test_conclude_milestone_success(
        deployer: &signer,
        raiser: &signer,
        treasury: &signer,
        user: &signer,
    ) acquires State, Campaign {
        let deployer_address = signer::address_of(deployer);
        let raiser_address = signer::address_of(raiser);
        let treasury_address = signer::address_of(treasury);
        let user_address = signer::address_of(user);
        account::create_account_for_test(deployer_address);
        account::create_account_for_test(raiser_address);
        account::create_account_for_test(treasury_address);
        account::create_account_for_test(user_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(raiser);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(treasury);
        let min_entry_price = 10000000; //0.1APT
        aptos_coin::mint(&aptos_framework, raiser_address, min_entry_price*20/100);
        aptos_coin::mint(&aptos_framework, user_address, min_entry_price);
        init_module(deployer);

        let campaign_name = string::utf8(b"test");
        let unit_price = 10000000; //0.1APT
        let token_name = string::utf8(b"test_token");
        let token_uri = string::utf8(b"test_token_uri");
        let target = 10000000; //0.1APT
        let m1 = string::utf8(b"m1");
        let m2 = string::utf8(b"m2");
        let m3 = string::utf8(b"m3");
        let m4 = string::utf8(b"m4");
        create_campaign(
            raiser,
            campaign_name,
            timestamp::now_seconds(),
            min_entry_price,
            unit_price,
            token_name,
            token_uri,
            target,
            m1,
            m2,
            m3,
            m4
        );


        let name = string::utf8(b"Campaign#0:");
        let resource_account_address = account::create_resource_address(&deployer_address, SEED);
        string::append(&mut name, campaign_name);
        let expected_campaign_obj_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(GENERAL_COLLECTION_NAME),
            &name
        );
        join_campaign(user, min_entry_price, expected_campaign_obj_address);
        start_campaign(raiser, expected_campaign_obj_address);
        let proof = string::utf8(b"proof");
        milestone_completion_proposal(raiser, expected_campaign_obj_address, 1, proof);
        vote_proposal(user, expected_campaign_obj_address, 1,true);
        timestamp::fast_forward_seconds(1);
        conclude_milestone(raiser, expected_campaign_obj_address, 1);

        let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
        assert!(campaign.milestone_completed_events == 1, 1);
        assert!(coin::balance<AptosCoin>(raiser_address) == target/4, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer, raiser = @raiser, treasury = @treasury, user = @0xA)]
    fun test_conclude_milestone_fail(
        deployer: &signer,
        raiser: &signer,
        treasury: &signer,
        user: &signer,
    ) acquires State, Campaign {
        let deployer_address = signer::address_of(deployer);
        let raiser_address = signer::address_of(raiser);
        let treasury_address = signer::address_of(treasury);
        let user_address = signer::address_of(user);
        account::create_account_for_test(deployer_address);
        account::create_account_for_test(raiser_address);
        account::create_account_for_test(treasury_address);
        account::create_account_for_test(user_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) =
            aptos_coin::initialize_for_test(&aptos_framework);
        coin::register<AptosCoin>(raiser);
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(treasury);
        let min_entry_price = 10000000; //0.1APT
        aptos_coin::mint(&aptos_framework, raiser_address, min_entry_price*20/100);
        aptos_coin::mint(&aptos_framework, user_address, min_entry_price);
        init_module(deployer);

        let campaign_name = string::utf8(b"test");
        let unit_price = 10000000; //0.1APT
        let token_name = string::utf8(b"test_token");
        let token_uri = string::utf8(b"test_token_uri");
        let target = 10000000; //0.1APT
        let m1 = string::utf8(b"m1");
        let m2 = string::utf8(b"m2");
        let m3 = string::utf8(b"m3");
        let m4 = string::utf8(b"m4");
        create_campaign(
            raiser,
            campaign_name,
            timestamp::now_seconds(),
            min_entry_price,
            unit_price,
            token_name,
            token_uri,
            target,
            m1,
            m2,
            m3,
            m4
        );


        let name = string::utf8(b"Campaign#0:");
        let resource_account_address = account::create_resource_address(&deployer_address, SEED);
        string::append(&mut name, campaign_name);
        let expected_campaign_obj_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(GENERAL_COLLECTION_NAME),
            &name
        );
        join_campaign(user, min_entry_price, expected_campaign_obj_address);
        start_campaign(raiser, expected_campaign_obj_address);
        let proof = string::utf8(b"proof");
        milestone_completion_proposal(raiser, expected_campaign_obj_address,  1, proof);
        vote_proposal(user, expected_campaign_obj_address, 1,false);
        timestamp::fast_forward_seconds(1);
        conclude_milestone(raiser, expected_campaign_obj_address, 1);
        {
            let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
            assert!(campaign.milestone_completed_events == 0, 1);
        };

        milestone_completion_proposal(raiser, expected_campaign_obj_address, 1, proof);
        vote_proposal(user, expected_campaign_obj_address, 1,true);
        timestamp::fast_forward_seconds(1);
        conclude_milestone(raiser, expected_campaign_obj_address, 1);
        let campaign = borrow_global<Campaign>(expected_campaign_obj_address);
        assert!(campaign.milestone_completed_events == 1, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

}
