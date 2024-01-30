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

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

pragma solidity 0.8.4;

/**
  @title A place to lock BAS tokens and GamesterNFTs
 */
contract Vault is ReentrancyGuard, IERC721Receiver {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address basToken;
    address gamesterNft;

     /**
     * Mappings of address to locked items, BAS and NFTs
     */
    mapping(address => uint) userBasBalances;
    mapping(address => EnumerableSet.UintSet) userNftBalance;
    mapping(uint => bool) isNFTLocked;

    /**
      @notice Initialise the BASVault
      @param _basToken the address of the BAS token ERC20
      @param _gamesterNft the address of the Gamester ERC721
     */
    constructor(address _basToken, address _gamesterNft ) {
        basToken = _basToken;
        gamesterNft = _gamesterNft;
    }

    /**
      @notice Lock a amount of BAS in the vault
      @param _amount the amount of BAS tokens to lock in the vault
     */
    function lockBas(uint _amount) external {
      IERC20(basToken).safeTransferFrom(msg.sender, address(this), _amount);
      userBasBalances[msg.sender] = userBasBalances[msg.sender].add(_amount);
    }

    /**
      @notice Withdraw a amount of BAS that is locked in the contract
      @param _amount the amount of BAS tokens to withdraw from the vault
     */
    function withdrawBas(uint _amount) external {
      // TODO (Dan): we should check if there is underflow here with withdrawl, or ensure that it doesn't happen
      require(userBasBalances[msg.sender] >= _amount, "Amount too high");
      require(_amount > 0, "Amount must be greater than 0");
      IERC20(basToken).transfer(msg.sender, _amount);
      userBasBalances[msg.sender] = userBasBalances[msg.sender].sub(_amount);
    }

    /**
      @notice Returns the amount of BAS tokens locked for a wallet
      @param _wallet the address for a wallet
      @return The amount of BAS locked for the given wallet
     */
    function getLockedBas(address _wallet) external view returns(uint) {
      return userBasBalances[_wallet];
    }

    /**
      @notice Lock a given Gamester in the contract
      @param _tokenID the token id of the gamester that should be locked in the vault
     */
    function lockGamester(uint _tokenID) external {
      // TODO (Dan): do we need to check that the owner of this token is the sender
      IERC721(gamesterNft).safeTransferFrom(msg.sender, address(this), _tokenID);
      EnumerableSet.add(userNftBalance[msg.sender],_tokenID);
      isNFTLocked[_tokenID] = true;
    }

    /**
      @notice Return the amount of Gamester NFTs in the vault for a wallet
      @param _wallet the address for a wallet
      @return The amount of Gamester NFTs locked
     */
    function getAmountOfLockedGamesters(address _wallet) external view returns(uint) {
      return EnumerableSet.length(userNftBalance[_wallet]);
    }

    /**
      @notice Returns the token id of Gamester NFTs in the vault for a wallet at a index
      @param _wallet the address for a wallet
      @param index the index of the locked NFT in the Vault
      @return tokenId The Token ID of the Gamester NFTs locked at the given index in the valut
      @dev This can be used with getAmountOfLockedGamesters() to iterate over the locked Gamester NFTs
     */
    function getLockedGamester(address _wallet, uint index) external view returns(uint tokenId) {
      //TODO Jdcarbeck check that this returns only if the user has something, 0 is not a valid return value
      return EnumerableSet.at(userNftBalance[_wallet], index);
    }


    /**
      @notice Checks if a given _tokenID is locked in the vault
      @param _tokenID the id of the Gamester NFT to check
      @return If the passed token is currently locked in the valut
     */
    function isGamesterLocked(uint _tokenID) external view returns(bool){
      return isNFTLocked[_tokenID];
    }

    /**
      @notice Withdraw a given Gamester that is locked in the contract
      @param _tokenID the id of the Gamester NFT to withdraw
     */
    function withdrawGamester(uint _tokenID) external {
      require(EnumerableSet.contains(userNftBalance[msg.sender],_tokenID) == true, "NFT not of user");
      IERC721(gamesterNft).safeTransferFrom(address(this), msg.sender, _tokenID);
      EnumerableSet.remove(userNftBalance[msg.sender],_tokenID);
      isNFTLocked[_tokenID] = false;
    }

    /**
      @notice implemenation of onERC721Received, used as a callback for safeTransferFrom
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}