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
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
  @title A interface for a NFT collection being launched through the launchpad
 */
interface launchPadNft {
  function batchMint(uint _amount, address _recipient) external;

}

/**
  @title A interface for a vault where users can lock/withdraw bas and their gamester NFTs
 */
interface BASVault {
  function getLockedBas(address _wallet) external view returns(uint);
  function getAmountOfLockedGamesters(address _wallet) external view returns(uint);
  function getLockedGamester(address _wallet, uint index) external view returns(uint tokenId);
  function isGamesterLocked(uint _tokenID) external view returns(bool);
}

/**
  @title A interface for getting the randomly selected Gamester trait types from the Gamester Select contract
 */
interface BASGamesterSelect {
  function getTraits() external view returns(uint[] memory token_traits);
}

/**
    @title a interface for interacting with the Gamester NFT collection
    @dev the interface here can be used in other smart contracts which need to interface with the Gamester collection
 */
interface BASCollection {
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
  @title BAS Launchpad Contract
  @notice Allows for discounts on time and price based on BAS locked and Gamester NFTs being staked
 */
contract Launchpad is Ownable, ReentrancyGuard {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /**
      The launchpad version, this should change as this contract is iterated upon
     */
    uint public contract_version = 1;

    address dead = 0x0000000000000000000000000000000000000000; 
    address basVault;
    address gamesterSelect;
    address gamesterNft;

    BASCollection collection;
    BASVault vault;
    BASGamesterSelect gamester_select;

    /**
      Tranches of time discounts based on locked items
     */
    uint[] public lockThresholds;
    uint[] public lockThresholdTimes;

    /**
     * Traches of discounts based on matching traits
     */
     uint[][] public matchingTraits;
     uint[] public matchingTraitsDiscounts;

    /**
      Struct representing a sale run through the launch pad
     */
    struct launchSale {
      address nftContract;
      uint nftPrice;
      uint saleStartTimestamp;
      uint royality; 
      address saleBeneficiary;
      address basBeneficiary;
    }
    mapping(address => launchSale) contractToLaunchSale;

    /**
      @notice The constructor for the Launchpad contract
      @param _collection the address of the Gamester NFT collection
      @param _vault the address to the BAS vaul where resources are locked
      @param _gamester_select the address to the GamesterSelect contract
     */
    constructor(address _collection, address _vault, address _gamester_select) {
        gamesterNft = _collection;
        gamesterSelect = _gamester_select;
        basVault = _vault;
        collection = BASCollection(gamesterNft);
        vault = BASVault(basVault);
        gamester_select = BASGamesterSelect(gamester_select);
    }

/// ====== Admin Controls ======
    /** 
      @notice Adds a NFT collection contract to the set of contracts that the launchpad provides discount to
      @param _nftContract the address of collection being launched
      @param _nftPrice the base price for a single token in the collection
      @param _saleStartTimestamp a unix timestamp (seconds) for when the sale begins
      @param _saleBeneficiary the address to recieve sale royalties
      @param _basBeneficiary the address to recieve bas rewards
      @dev Only callable by owner address
     */
    function addLaunchSale(address _nftContract, uint _nftPrice, uint _saleStartTimestamp, uint _royality,
                           address _saleBeneficiary, address _basBeneficiary) external onlyOwner {
      //_nftContract must be a contract address
      require(Address.isContract(_nftContract) == true, "Not Valid Contract");
      // Timestamp needs to in the future
      contractToLaunchSale[_nftContract] =  launchSale(_nftContract, _nftPrice, _saleStartTimestamp, _royality, _saleBeneficiary, _basBeneficiary);
    }

    /** 
      @notice Removes a launch from set of launches
      @param _nftContract the address of the collection that should be removed from the launchpad
      @dev Only callable by owner address
     */
    function removeLaunchSale(address _nftContract) external onlyOwner {
      require(Address.isContract(_nftContract)==true, "Not Valid Contract");
      delete contractToLaunchSale[_nftContract]; // Safe to do because struct has no mapping in it
    }

    /**
      @notice Sets the thresholds for locked bas and their respective time discounts
      @param _lockThresholds a list of uints which specify the amount of Bas needed to be locked
      @param _lockThresholdTimes a list of uint which specify the discount in time in seconds
      @dev Only callable by owner, the locked amount and discount should be the same index in both lists
     */
    function setThresholdVariables(uint[] memory _lockThresholds, uint[] memory _lockThresholdTimes) external onlyOwner {
      require(_lockThresholds.length == _lockThresholdTimes.length, "Elements not the same length");
      lockThresholds = _lockThresholds;
      lockThresholdTimes = _lockThresholdTimes;
    }

    /**
      @notice Sets the traits needed to be matched for locked Gamester NFT and their respective price discounts
      @param _matchingTraits a 2d array specifying the trait indexs that need to be matched
      @param _matchingTraitsDiscounts a uint array specifying a the precentatage price to pay (95 = 5% discount, 60 = 40% discount)
      @dev Only Callable by owner
     */
    function setDiscountVariables(uint[][] memory _matchingTraits, uint[] memory _matchingTraitsDiscounts) external onlyOwner {
      require(_matchingTraits.length == _matchingTraitsDiscounts.length, "Elements not the same length");
      matchingTraits = _matchingTraits;
      matchingTraitsDiscounts = _matchingTraitsDiscounts;
    }


/// ====== User Methods ======
    /**
      @notice Validates a order, respective of a wallets discounts from locked bas and Gamester NFTs
      @param _nftContract the address for the NFT collection which is being purchased
      @param _amount the amount of NFT tokens that are being purchased in the transacation
      @dev Used to validate a transaction with the buy method
     */
    modifier validOrder(address _nftContract, uint _amount) {
        uint price = contractToLaunchSale[_nftContract].nftPrice;
        uint price_discount = priceDiscount(msg.sender);
        bool full_amount = msg.value == (price_discount.mul(_amount).mul(price)).div(100);

        uint sale_time = contractToLaunchSale[_nftContract].saleStartTimestamp;
        uint sale_time_discount = timeDiscount(msg.sender);
        bool on_time = sale_time.sub(sale_time_discount) <= block.timestamp;

        require(full_amount, "Funds sent are incorrect!");
        require(on_time, "Too early to sale!");
        _;
    }

    /**
      @notice Retrive the launch metadata for a collection address
      @param _nftContract the address of the NFT collection being launched through the launchpad
     */
    function getLaunchSale(address _nftContract) external view returns(launchSale memory){
        return contractToLaunchSale[_nftContract];
    }

    /**
      @notice View the time discount in secounds for a wallet
      @param _user the address for which the time discount should be returned
      @return The discount in seconds for the passed user
      @dev this function will return the max time discount based on the locked bas, helper function to validOrder
    */
    function timeDiscount(address _user) public view returns (uint) {
      uint max_discount = 0;
      for(uint i = 0; i < lockThresholds.length; i++) {
        if (vault.getLockedBas(_user) >= lockThresholds[i]) {
          if(lockThresholdTimes[i] > max_discount) max_discount = lockThresholdTimes[i];
        } 
      }
      return max_discount;
    }

   /**
      @notice View the price discount as a percentage of the total price for a wallet
      @param _user the address for which the price discount should be returned
      @return The discount as a percentage of the total price (100 = 0% discount, 80 = 20% discount, 95 = 5% discount)
      @dev This function will return the max price discount (i.e smallest percentage of total price), helper function to validOrder
    */
    function priceDiscount(address _user) public view returns (uint) {
      uint best_discount = 100;
      for(uint i = 0; i < vault.getAmountOfLockedGamesters(_user); i++){
        uint token_id = vault.getLockedGamester(_user, i);
        for(uint j = 0; j < matchingTraits.length; j++){
          if(traitsMatch(token_id, matchingTraits[j])){
              uint discount = matchingTraitsDiscounts[j];
              if(discount < best_discount) best_discount = discount;
          }
        }  
      }
      return best_discount;
    }

    /**
      @notice Checks if a Gamester NFT matches several Traits of the randomly selected Gamester
      @param token_id the token id of Gamester NFT to check if traits match
      @param traitsToMatch A list of uints which represent the index of traits to check
      @return If all the traits match, only true when they all match
      @dev the order of traitsToMatch doesn't matter, helper function to validOrder
     */
    function traitsMatch(uint token_id, uint[] memory traitsToMatch) public view returns (bool) {
      require(BASVault(basVault).isGamesterLocked(token_id), "The NFT is not locked in the BASVault");
      bool traits_match = true;

      uint[] memory nft = BASCollection(gamesterNft).getAllTraits(token_id);
      uint[] memory selected_attributes = BASGamesterSelect(gamesterSelect).getTraits();
      for(uint i = 0; i < traitsToMatch.length; i++){
        uint trait_index = traitsToMatch[i];
        traits_match = traits_match && (nft[trait_index] == selected_attributes[trait_index]);
      }
      return traits_match;
    }

    /**
      @notice The method used to buy a particular n tokens of a luanchpad collection, respective of discounts
      @param _nftContract the address of the collection to buy from
      @param _amount the number of tokens to by from the collection
      @param _referralId the id of the referer to send rewards to
      @dev The discount calculations and validation are all done in the modifer validOrder, if succeeds then the user can mint
     */
    function buy(address _nftContract, uint _amount, uint _referralId) external payable validOrder(_nftContract, _amount) {
      ///TODO (Dan): We need to add the referal logic here
      launchPadNft(_nftContract).batchMint(_amount, msg.sender);
      // Send money to NFT_wallet
      uint value = msg.value;
      launchSale memory sale = contractToLaunchSale[_nftContract];
      uint royality = (sale.royality.mul(value).div(100));
      payable(sale.saleBeneficiary).transfer(royality);
      payable(sale.basBeneficiary).transfer(value.sub(royality));
      // Send money to bas beneficiary
    }
}