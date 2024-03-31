# CrowdWeave
Functions:
1. create_campaign
    - Takes in variables:
        - campaign_name: String,
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
    - Called by raiser
2. join_campaign
    - Takes in variables:
        - entry_sum: u64,
          campaign_obj_add: address,
    - Called by any user
3. start_campaign
    - Takes in variables: campaign_obj_add: address
    - Called by raiser
4. milestone_completion_proposal
    - Takes in variables:
        - campaign_obj_add: address,
          milestone: u64, // milestone 1,2,3,4
          proof: String,
    - Called by raiser
5. vote_proposal
    - Takes in variables:
        - campaign_obj_add: address,
          milestone: u64, // milestone 1,2,3,4
          should_pass: bool
    - Called by raiser
6. conclude_milestone
    - Takes in variables:
        - campaign_obj_add: address, milestone: u64
    - Called by raiser

7. conclude_campaign
    - Takes in variables:
        - campaign_obj_add: address
    - Called by raiser

8. cancel_campaign
    - Takes in variables:
        - campaign_obj_add: address
    - Called by raiser