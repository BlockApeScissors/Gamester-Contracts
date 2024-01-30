/*
           ██████████   █████████   ████████  
           ██      ██   ██     ██   ██            
           ██      ██   ██     ██   ██            
           ██████████   █████████   ████████      
           ██      ██   ██     ██         ██      
           ██      ██   ██     ██         ██
           ██████████   ██     ██   ████████    
           
         █████████████████████████████████████
         
                   Block, Ape, Scissors
           
*/

// SPDX-License-Identifier: MIT
// Created by Dan and Jack

pragma solidity >=0.6.0 <0.8.9;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/smartcontractkit/chainlink/blob/master/contracts/src/v0.8/VRFConsumerBase.sol";


interface IReferrals {
    
    //Pays Referrer passed as initial uint user ID, value passed as msg.value. Returns the userID of the payee, if he is unregistered it registers him and pays it.
    function payReferrerAndRegister(uint256) external payable returns(uint256);
    
    //Pays Referrer passed as initial uint user ID, value passed as msg.value.
    function payReferrer(uint256) external payable;
    
    //Allows a user to change the referrer address to 
    function changeReferrerAddress(address payable) external;
    
    //Allows Referrer to withdraw his accrued funds
    function withdrawReferralFunds() external;
    
    //Allows a user to query his referrer information with his address
    function queryReferrerByAddress(address) external view returns(uint256, uint256, uint256, uint256, uint256, bool);
    
}


/**
 * @title BAS Collectables contract
 * @dev Extends ERC721 Non-Fungible Token Standard basic implementation
 */
contract BASCollection is ERC721Enumerable, Ownable, VRFConsumerBase {
    using SafeMath for uint256;
    
    /**
     * Variables used for Chainlink VRF RNG
     */
    uint256 internal link_fee = 0.2 * 10 ** 18 wei; // 0.2 LINK (BSC)
    address internal _link = 0x404460C6A5EdE2D891e8297795264fDe62ADBB75;
    address internal _vrfCoordinator = 0x747973a5A2a4Ae1D3a8fDF5479f1514F65Db9C31;
    bytes32 internal keyHash = 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c;
    
    mapping(bytes32 => uint) public requestIdToRandomness;
    
    /**
     * Variables for referrals 
     */
    IReferrals referral;
    uint public constant referralFee = 20_000_000_000_000_000 wei; // 0.02 BNB

    /**
     * Variables/Constants for BASC Sale
     */
    uint256 public constant BASC_FEE = 330_000_000_000_000_000 wei; // 0.33 BNB
    uint public constant maxBASCPurchase = 10;
    string private _customBaseURI = "";
    uint256 public MAX_BASC;
    bool public saleIsActive = false;
    bool public saleIsPublic = false;
    uint public lastNFTRevealed = 0;
    mapping(uint => bool) public tokenRevealed;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public hasMinted;
    
    /**
     * Variables for BASC Token
     */
    mapping(uint => uint) public tokenValues;
    struct Trait {
        string name;
        uint uniqueTypes;
        uint mask;
        uint mask_size; 
    }
    mapping(uint => mapping(uint => uint)) public typeCounts;
    // Represents a mask of the significant bits for a token value
    uint public Combinations = 0;
    Trait[] public TokenTraits;
    
    
    /**
     * Ensures that a given list of traits is valid
     */
    modifier ValidTraits(uint[] memory traits){
        // BASC must have more than 1 trait
        bool isValid = traits.length > 0;
        uint shiftSum = 0;
        for(uint i=0; i < traits.length; i++){
            // Check if trait is power of 2
            isValid = isValid && traitIsValid(traits[i]);
            shiftSum += (traits[i] - 1);
        }
        // the number of significant bits to represent a BASC is less than max bits of 256
        require(isValid && (shiftSum < 256));
        _;
    }
    
    
    /**
     * Ensures that a mint is valid using the senders address and amount of tokens to mint
     */
    modifier ValidMint(uint mintNumber) {
        if(saleIsActive){
            require(BASC_FEE.mul(mintNumber) == msg.value, "Ether value sent is not correct");
            require(mintNumber <= maxBASCPurchase, "Can only mint 10 tokens at a time during presale");
            require(hasMinted[msg.sender] == false, "This wallet has already minted.");
            if(saleIsPublic){
                _;
            } else {
            require(whitelist[msg.sender], "Sale is not yet public.");
            _;
            }
            
        } else {
            require(owner() == _msgSender(), "Sale must be active to mint.");
            _;
        } 
    }
    
    
    /**
     * Checks that the unique types is > 0 and power of 2
     */
    function traitIsValid(uint traitTypes) internal pure returns(bool isValid){
        isValid = (traitTypes > 0) && (traitTypes & (traitTypes - 1) == 0);
    }
    
    
    constructor(string memory name, string memory symbol, uint maxNftSupply,
                string[] memory tokenTraitNames, uint[] memory tokenTraits,
                address _referrals) 
        ValidTraits(tokenTraits)
        ERC721(name, symbol) 
        VRFConsumerBase(_vrfCoordinator, _link) {
            require(keccak256(abi.encodePacked((tokenTraitNames[0]))) == keccak256(abi.encodePacked(("Gender"))), "First Attribute must be a gender");
            require(tokenTraits[0] == 2, "First Attribute must be a gender");
            
            MAX_BASC = maxNftSupply;
            
            // Create Trait and add to TokenTraits
            for(uint i = 0; i < tokenTraitNames.length; i++){
                uint types = tokenTraits[i];
                uint mask = types - 1;
                uint masksize = 1;
                while(1 << masksize < types) masksize++;
                TokenTraits.push(Trait(tokenTraitNames[i], types, mask, masksize));
                
                // Add significant bits used to Combinations
                Combinations = Combinations << masksize;
                Combinations += mask;
            }
            
            referral = IReferrals(_referrals);
    }
    
    
    /**
     * Function used to withdraw funds from contract 
     */
    function withdraw() public onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }
    
    
    /**
     * Add addresses to presale whitelist
     */
    function addToWhitelist(address[] memory addresses) public onlyOwner {
        for(uint i=0; i < addresses.length; i++){
            whitelist[addresses[i]] = true;
        }
    }
    
    
    /**
     * Overrides virtual _baseURI() used in ERC721 _tokenURI() to use custom value
     */
    function _baseURI() internal view override returns (string memory) {
        return _customBaseURI;
    }


    /**
     * Sets the baseURI to a string value
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _customBaseURI = baseURI;
    }


    /*
    * Pause sale if active, make active if paused
    */
    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }
    
    
    /*
     * Make sale open to the public if private, make sale private if public
     */
    function flipPublicState() public onlyOwner {
        saleIsPublic = !saleIsPublic;
    }
    
    
    /** 
     * Requests randomness 
     */
    function getRandomNumber() public onlyOwner returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= link_fee, "Not enough LINK - fill contract with faucet");
        requestId = requestRandomness(keyHash, link_fee);
        return requestId;
    }
    
    
    /**
     * callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        requestIdToRandomness[requestId] = randomness;
    }
    
    
    /**
     * Function when given a requestId for randomness and a amount (n),
     * will RNG tokenValues for n tokens that have been minted but not revealed
     */
    function reveal(bytes32 requestId, uint revealAmount) public onlyOwner {
        require(requestIdToRandomness[requestId] != 0, "Randomness has not been fullfilled for this requestId yet.");
        require((revealAmount.add(lastNFTRevealed)) <= MAX_BASC, "Reveal amount indexes past max number of tokens.");
        require((revealAmount.add(lastNFTRevealed)) <= totalSupply(), "Reveal amount indexs past current total supply.");
        // Capture randomness from chainlink callback
        uint randomness = requestIdToRandomness[requestId];
        
        // Generate a random value for the last revealed token => n (revealAmount amount)
        uint nextMintId = lastNFTRevealed + revealAmount;
        for(; lastNFTRevealed < nextMintId; lastNFTRevealed++) {
            uint randomValue = uint256(keccak256(abi.encode(randomness, lastNFTRevealed)));
            if(tokenRevealed[lastNFTRevealed] == false) { //Safty check to make sure token random values are not overwritten
                tokenValues[lastNFTRevealed] = randomValue;
                tokenRevealed[lastNFTRevealed] = true;
                updateCounts(lastNFTRevealed);
            }
        }
    }
    
    
    /**
     * Function that updates the counts of types for each trait for token
     */
    function updateCounts(uint token) internal {
        uint gender = getGender(token);
        for(uint i = 0; i < TokenTraits.length; i++) {
            Trait memory trait = TokenTraits[i];
            uint traitType = getTrait(token, i);
            uint traitTypeIndex = uint(keccak256(abi.encode(trait.name, traitType)));
            typeCounts[gender][traitTypeIndex]++;
        }
    }
    

    /**
    * Mints BAS Collectable
    */
    function mintBASC(uint numberOfTokens, uint _refID) public payable ValidMint (numberOfTokens) returns(uint minterRefId) {
        require(totalSupply().add(numberOfTokens) <= MAX_BASC, "Purchase would exceed max supply of the BAS collection");
        
        for(uint i = 0; i < numberOfTokens; i++) {
            uint mintIndex = totalSupply();
            if (totalSupply() < MAX_BASC) {
                _safeMint(msg.sender, mintIndex);
            }
        }
        
        //Pay the referrer, if not owner
        if(msg.sender != owner()){
            hasMinted[msg.sender] = true;
            minterRefId = referral.payReferrerAndRegister{value: referralFee.mul(numberOfTokens)}(_refID);
        }
    }
    
    
    /**
     * Given a token id reutrns a tokens traits rarity and int representing significant bits of its random value
     */
    function getCollectable(uint token) public view returns(uint[] memory traits, uint value, uint rarity) {
        require(tokenRevealed[token], "Token has not yet been revealed.");
        value = tokenValues[token] & Combinations;
        traits = getAllTraits(token);
        rarity = getCollectableRarity(token);
    }
    
    
    /**
     * Given a attribute index return the value of the attribute
     */
    function getTrait(uint token, uint trait_n) public view returns(uint traitType){
        require(tokenRevealed[token], "Token has not yet been revealed.");
        require(trait_n < TokenTraits.length, "Index out of bounds.");
        uint randomValue = tokenValues[token];
        
        uint ops = trait_n;
        uint index = 0; 
        // while there are operations remaining shift right the randomValue by the size of each traits mask_size
        while(ops > 0){
            uint traitMaskSize = TokenTraits[index].mask_size;
            randomValue = randomValue >> traitMaskSize;
            ops--;
            index++;
        }
        
        uint maskedValue = randomValue & TokenTraits[trait_n].mask;
        traitType = maskedValue % TokenTraits[trait_n].uniqueTypes;
    }
    
    
    /**
     * A gender is the first Trait, in a BASC check the value for the first trait
     */
    function getGender(uint token) internal view returns(uint gender){
        require(tokenRevealed[token], "Token has not yet been revealed.");
        gender = getTrait(token, 0);
    }
    
    
    /**
     * Get the number NFTs with a specified type for a given trait
     */
    function getTraitCount(uint trait_n, uint type_n, uint gender) public view returns(uint type_count){
        require(trait_n < TokenTraits.length, "Index out of bounds.");
        require(type_n < TokenTraits[trait_n].uniqueTypes, "Index out of bounds.");
        require(gender < 2, "Gender out of bounds");
        string memory traitName = TokenTraits[trait_n].name;
        type_count = typeCounts[gender][uint(keccak256(abi.encode(traitName, type_n)))];
    }
    
    
    /** 
     * Get the number of traits for the token
     */
    function getTokenTraitsLength() public view returns(uint length){
        length = TokenTraits.length;
    }
    
    
    /**
     * Given a token return a array of all trait values
     */
    function getAllTraits(uint token) public view returns(uint[] memory) {
        uint[] memory token_traits = new uint[](TokenTraits.length);
        for(uint i = 0; i < TokenTraits.length; i++){
            token_traits[i] = getTrait(token, i);
        }
        return token_traits;
    }
    
    
    /**
     * Get the rarity of a collectable i.e sum(traitTypeCount * traitTypes)
     */
    function getCollectableRarity(uint token) public view returns (uint rarity){
        require(tokenRevealed[token], "Token has not yet been revealed.");
        rarity = 0;
        uint gender = getGender(token);
        for(uint i = 0; i < TokenTraits.length; i++){
            uint traitType = getTrait(token, i);
            string memory traitName = TokenTraits[i].name;
            uint traitCount = TokenTraits[i].uniqueTypes;
            uint traitTypeCount = typeCounts[gender][uint(keccak256(abi.encode(traitName, traitType)))];
            rarity += traitTypeCount * traitCount;
        }
    }
}