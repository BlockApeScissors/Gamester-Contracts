// SPDX-License-Identifier: MIT

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


pragma solidity 0.8.4;


import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
    @title a interface for interacting with the Gamester NFT collection
    @dev the interface here can be used in other smart contracts which need to interface with the Gamester collection
 */
interface IBASCollection {
    function Combinations() external view returns(uint);
    function TokenTraits(uint _index) external view returns(string memory name, uint uniqueTypes, uint mask, uint mask_size);
    function getCollectable(uint token) external view returns(uint[] memory traits, uint value, uint rarity);
    function getTrait(uint token, uint trait_n) external view returns(uint traitType);
    function getTraitCount(uint trait_n, uint type_n, uint gender) external view returns(uint type_count);
    function getTokenTraitsLength() external view returns(uint length);
    function getAllTraits(uint token) external view returns(uint[] memory);
    function getCollectableRarity(uint token) external view returns(uint rarity);
}


/** 
    @title Selects a random set of Gamester traits to be used for discounts
 */
contract GamesterSelect is Ownable, VRFConsumerBase {

    using SafeMath for uint256;
    using Address for address;

    //Address of gamester collection, and interface
    address gamesterNft;
    IBASCollection collection;

    //Chainlink randomness
    uint randomness;

    /**
     * Variables used for Chainlink VRF RNG
     */
    uint internal link_fee = 0.2 * 10 ** 18 wei; //0.2 LINK (BSC)
    address internal _link = 0x404460C6A5EdE2D891e8297795264fDe62ADBB75;
    address internal _vrfCoordinator = 0x747973a5A2a4Ae1D3a8fDF5479f1514F65Db9C31;
    bytes32 internal keyHash = 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c;

     /** 
        @notice Constuctor for the GamesterSelect Contract
        @param _basc the address to the Gamester NFT collection
     */
    constructor(address _basc)
      VRFConsumerBase(_vrfCoordinator, _link) {
        gamesterNft = _basc;
        collection = IBASCollection(gamesterNft);
    }

    /** 
        @notice Uses Link fund stored in this contract to request randomness from Chainlink VRF
        @dev This is only called by the owner wallet
     */
    function getRandomNumber() public onlyOwner returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= link_fee, "Not enough LINK - fill contract with faucet");
        requestId = requestRandomness(keyHash, link_fee);
        return requestId;
    }

    /** 
        @notice Function to handle return of Chainlink VRF, sets the global randomneess
        @dev This function is not called directly but outside by Chainlink VRF
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        randomness = _randomness;
    }

    /** 
        @notice Using the random value and traits defined in the gamester collection, return a trait type
        @dev This functions copys the functionailty of getTrait() in gamester contract.
        @param trait_n a index of a trait whose value should be returned
        @return traitType A uint that is the value of the random gamester at trait n
     */
    function getTrait(uint trait_n) public view returns(uint traitType){
        uint traits_len = collection.getTokenTraitsLength();
        require(trait_n < traits_len, "Index out of bounds.");

        uint randomValue = randomness & collection.Combinations();
        
        uint ops = trait_n;
        uint index = 0; 
        // while there are operations remaining shift right the randomValue by the size of each traits mask_size
        while(ops > 0){
            (string memory name, uint uniqueTypes, uint mask, uint mask_size) = collection.TokenTraits(index);
            uint traitMaskSize = mask_size;
            randomValue = randomValue >> traitMaskSize;
            ops--;
            index++;
        }
        (string memory name, uint uniqueTypes, uint mask, uint mask_size) = collection.TokenTraits(trait_n);
        uint maskedValue = randomValue & mask;
        traitType = maskedValue % uniqueTypes;
    }

    /** 
        @notice Using the random value and traits defined in the gamester collection, return all trait types in a list of uint
        @dev This functions return value can be compared with the gamesters collection getAllTraits() return value
        @return token_traits A list of uints that represents the trait types of the random gamester
     */
    function getTraits() public view returns(uint[] memory token_traits) {
        uint traits_len = collection.getTokenTraitsLength();
        token_traits = new uint[](traits_len);
        for(uint i = 0; i < traits_len; i++){
            token_traits[i] = getTrait(i);
        }
    }
}